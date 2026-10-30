//+------------------------------------------------------------------+
//| VideoScalper.mq5                                                 |
//| Scalping gaya video: sesi singkat (mis. 20 menit) dengan modal   |
//| kecil (mis. $10), Buy Stop / Sell Stop berjarak dekat, dan lot   |
//| yang naik mengikuti saldo sesi.                                  |
//|                                                                  |
//| Live/demo : sesi dimulai saat EA dipasang, berhenti otomatis     |
//|             saat target, batas rugi, atau waktu habis.           |
//| Tester    : sesi dijalankan berulang pada jam-jam terjadwal,     |
//|             masing-masing mulai dari bankroll virtual $10, lalu  |
//|             distribusi hasil semua sesi dicetak di Journal.      |
//|                                                                  |
//| RISIKO SANGAT TINGGI. Bankroll sesi bisa habis dalam hitungan    |
//| menit. Gunakan hanya uang yang siap hilang seluruhnya.           |
//+------------------------------------------------------------------+
#property copyright "Chatbot repo"
#property version   "1.10"
#property description "Sesi scalping singkat bermodal kecil (gaya video). Risiko sangat tinggi."

#include <Trade\Trade.mqh>

enum ENUM_MODEL
  {
   MODEL_GRID = 0,      // Grid dua arah (seperti video)
   MODEL_TREND = 1,     // Ladder searah tren EMA
   MODEL_STRADDLE = 2   // Straddle high/low N bar (OCO)
  };

input group "=== Sesi ==="
input bool   InpStartNow       = true;       // Live: mulai 1 sesi saat EA dipasang
input string InpSessionTimes   = "07:00,10:00,13:30,16:00"; // Jadwal sesi (HH:MM server), dipakai di tester / bila StartNow=false
input int    InpSessionMinutes = 20;         // Lama sesi (menit)
input double InpBankroll       = 10.0;       // Modal per sesi (USD)
input double InpTargetMult     = 5.0;        // Berhenti bila modal sesi mencapai x kali lipat
input double InpBustUSD        = 1.0;        // Berhenti bila modal sesi turun ke (USD)

input group "=== Model ==="
input ENUM_MODEL InpModel      = MODEL_GRID; // Model
input double InpStepUSD        = 1.0;        // Jarak antar order (USD harga gold)
input double InpGridOffset     = 0.5;        // Level grid di kelipatan jarak + offset (0.5 -> x.50 seperti video)
input int    InpLevels         = 3;          // Jumlah order per sisi
input double InpTPSteps        = 1.0;        // TP = x jarak
input double InpSLSteps        = 2.0;        // SL = x jarak (0 = tanpa SL, hanya batas modal sesi)
input double InpTrailSteps     = 0.0;        // Trailing = x jarak (0 = off)
input int    InpEmaFast        = 20;         // EMA cepat (model tren)
input int    InpEmaSlow        = 50;         // EMA lambat (model tren)
input int    InpLookback       = 10;         // Bar high/low (model straddle)

input group "=== Lot ==="
input double InpLotPer10       = 0.01;       // Lot per $10 modal sesi (naik mengikuti saldo)
input double InpMaxLot         = 2.0;        // Lot maksimum per order
input int    InpMaxPositions   = 6;          // Maks posisi terbuka

input group "=== Lain-lain ==="
input double InpMaxSpreadUSD   = 0.30;       // Spread maks untuk memasang order (USD harga)
input long   InpMagic          = 20261031;   // Magic number
input int    InpSlippage       = 30;         // Slippage (points)

#define OUT_TIME   0
#define OUT_TARGET 1
#define OUT_BUST   2

CTrade   trade;
int      hEmaF = INVALID_HANDLE, hEmaS = INVALID_HANDLE;
int      slotMin[];
datetime slotDone[];
bool     inSess   = false;
bool     liveDone = false;
datetime sessStart = 0, sessEnd = 0, lastBar = 0;
double   lastSyncPx = 0;
double   sessBank  = 0;      // modal awal sesi berjalan
double   sessRealized = 0;   // profit+komisi deal yang sudah terjadi di sesi ini
double   sessPeak = 0;
double   resFinal[];
int      resOut[];

//+------------------------------------------------------------------+
int OnInit()
  {
   string parts[];
   int n = StringSplit(InpSessionTimes, ',', parts);
   ArrayResize(slotMin, 0);
   for(int i = 0; i < n; i++)
     {
      StringTrimLeft(parts[i]);
      StringTrimRight(parts[i]);
      if(parts[i] == "")
         continue;
      string hm[];
      if(StringSplit(parts[i], ':', hm) != 2)
        {
         Print("Format jam salah: ", parts[i]);
         return INIT_PARAMETERS_INCORRECT;
        }
      int k = ArraySize(slotMin);
      ArrayResize(slotMin, k + 1);
      slotMin[k] = (int)StringToInteger(hm[0]) * 60 + (int)StringToInteger(hm[1]);
     }
   ArrayResize(slotDone, ArraySize(slotMin));
   for(int i = 0; i < ArraySize(slotDone); i++)
      slotDone[i] = 0;

   hEmaF = iMA(_Symbol, PERIOD_M1, InpEmaFast, 0, MODE_EMA, PRICE_CLOSE);
   hEmaS = iMA(_Symbol, PERIOD_M1, InpEmaSlow, 0, MODE_EMA, PRICE_CLOSE);
   if(hEmaF == INVALID_HANDLE || hEmaS == INVALID_HANDLE)
      return INIT_FAILED;
   if(InpStepUSD <= 0 || InpLevels < 1 || InpSessionMinutes < 1 || InpBankroll <= 0)
      return INIT_PARAMETERS_INCORRECT;

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippage);
   trade.SetTypeFillingBySymbol(_Symbol);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   if(inSess)
      EndSession(OUT_TIME);
   PrintSummary();
   IndicatorRelease(hEmaF);
   IndicatorRelease(hEmaS);
   Comment("");
  }

bool IsTester()
  {
   return MQLInfoInteger(MQL_TESTER) != 0;
  }

//+------------------------------------------------------------------+
//| Posisi & order                                                   |
//+------------------------------------------------------------------+
int CountPositions()
  {
   int c = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(PositionGetTicket(i) > 0 && PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == InpMagic)
         c++;
   return c;
  }

double Floating()
  {
   double s = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(PositionGetTicket(i) > 0 && PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == InpMagic)
         s += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   return s;
  }

void CancelPending()
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong tk = OrderGetTicket(i);
      if(tk > 0 && OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == InpMagic)
         trade.OrderDelete(tk);
     }
  }

void CloseAll()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk > 0 && PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagic)
         trade.PositionClose(tk);
     }
  }

double SessEquity()
  {
   return sessBank + sessRealized + Floating();
  }

double SessLots()
  {
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double bank = MathMax(sessBank + sessRealized, 0.0);
   double lots = MathMin(bank / 10.0 * InpLotPer10, InpMaxLot);
   if(step <= 0)
      step = vmin;
   lots = MathFloor(lots / step + 1e-9) * step;
   return MathMin(MathMax(lots, vmin), vmax);
  }

double MinDist()
  {
   long sl = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long fr = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   return (MathMax(sl, fr) + 2) * _Point;
  }

void PlaceStop(const bool buy, double price, const double lots)
  {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double md  = MinDist();
   if(buy ? price < ask + md : price > bid - md)
      return;
   price = NormalizeDouble(price, _Digits);
   double sl = 0, tp = 0;
   if(InpSLSteps > 0)
      sl = NormalizeDouble(buy ? price - MathMax(InpSLSteps * InpStepUSD, md) : price + MathMax(InpSLSteps * InpStepUSD, md), _Digits);
   if(InpTPSteps > 0)
      tp = NormalizeDouble(buy ? price + MathMax(InpTPSteps * InpStepUSD, md) : price - MathMax(InpTPSteps * InpStepUSD, md), _Digits);
   if(buy)
      trade.BuyStop(lots, price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "VS");
   else
      trade.SellStop(lots, price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "VS");
  }

int TrendDir()
  {
   double f[1], s[1];
   if(CopyBuffer(hEmaF, 0, 1, 1, f) != 1 || CopyBuffer(hEmaS, 0, 1, 1, s) != 1)
      return 0;
   double c = iClose(_Symbol, PERIOD_M1, 1);
   if(f[0] > s[0] && c > f[0])
      return 1;
   if(f[0] < s[0] && c < f[0])
      return -1;
   return 0;
  }

bool SpreadOK()
  {
   return SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID) <= InpMaxSpreadUSD;
  }

//--- ada posisi searah yang dibuka di sekitar level ini?
bool HasPosAt(const bool buy, const double level)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(PositionGetTicket(i) > 0 && PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == InpMagic &&
         (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) == buy &&
         MathAbs(PositionGetDouble(POSITION_PRICE_OPEN) - level) < InpStepUSD * 0.5)
         return true;
   return false;
  }

bool HasOrderAt(const bool buy, const double level)
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
      if(OrderGetTicket(i) > 0 && OrderGetString(ORDER_SYMBOL) == _Symbol &&
         OrderGetInteger(ORDER_MAGIC) == InpMagic &&
         (OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_BUY_STOP) == buy &&
         MathAbs(OrderGetDouble(ORDER_PRICE_OPEN) - level) < InpStepUSD * 0.1)
         return true;
   return false;
  }

//--- grid tetap di level kelipatan jarak (seperti video): order yang sudah ada tidak digeser,
//    hanya level baru ditambah saat harga bergerak dan level yang terlalu jauh dihapus
void SyncLattice(const bool doBuy, const bool doSell)
  {
   double S   = InpStepUSD;
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double md  = MinDist();
   double lots = SessLots();
   bool full = CountPositions() >= InpMaxPositions;
   int lv = InpLevels;

   double up = MathCeil((ask + md - InpGridOffset) / S) * S + InpGridOffset;
   if(up < ask + md)
      up += S;
   double dn = MathFloor((bid - md - InpGridOffset) / S) * S + InpGridOffset;
   if(dn > bid - md)
      dn -= S;
   double eps = S * 0.1;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong tk = OrderGetTicket(i);
      if(tk == 0 || OrderGetString(ORDER_SYMBOL) != _Symbol || OrderGetInteger(ORDER_MAGIC) != InpMagic)
         continue;
      bool   b  = OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_BUY_STOP;
      double p  = OrderGetDouble(ORDER_PRICE_OPEN);
      bool keep = !full && MathAbs(OrderGetDouble(ORDER_VOLUME_INITIAL) - lots) < 1e-8 &&
                  (b ? doBuy && p <= up + (lv - 1) * S + eps
                     : doSell && p >= dn - (lv - 1) * S - eps);
      if(!keep)
         trade.OrderDelete(tk);
     }
   if(full || !SpreadOK())
      return;
   for(int k = 0; k < lv; k++)
     {
      double lu = NormalizeDouble(up + k * S, _Digits);
      double ld = NormalizeDouble(dn - k * S, _Digits);
      if(doBuy && !HasOrderAt(true, lu) && !HasPosAt(true, lu))
         PlaceStop(true, lu, lots);
      if(doSell && !HasOrderAt(false, ld) && !HasPosAt(false, ld))
         PlaceStop(false, ld, lots);
     }
  }

void RefreshOrders()
  {
   switch(InpModel)
     {
      case MODEL_GRID:
         SyncLattice(true, true);
         break;
      case MODEL_TREND:
        {
         int d = TrendDir();
         SyncLattice(d > 0, d < 0);
         break;
        }
      case MODEL_STRADDLE:
        {
         CancelPending();
         if(CountPositions() > 0 || !SpreadOK())
            break;
         double hi[], lo[];
         if(CopyHigh(_Symbol, PERIOD_M1, 1, InpLookback, hi) != InpLookback ||
            CopyLow(_Symbol, PERIOD_M1, 1, InpLookback, lo) != InpLookback)
            break;
         double lots = SessLots();
         double buf = 0.1 * InpStepUSD;
         PlaceStop(true, hi[ArrayMaximum(hi)] + buf, lots);
         PlaceStop(false, lo[ArrayMinimum(lo)] - buf, lots);
         break;
        }
     }
  }

void Trail()
  {
   if(InpTrailSteps <= 0)
      return;
   double dist = InpTrailSteps * InpStepUSD;
   double md = MinDist();
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0 || PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      bool buy = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double px = SymbolInfoDouble(_Symbol, buy ? SYMBOL_BID : SYMBOL_ASK);
      if((buy ? px - open : open - px) < dist)
         continue;
      double nsl = NormalizeDouble(buy ? px - dist : px + dist, _Digits);
      bool better = sl == 0 || (buy ? nsl > sl + _Point : nsl < sl - _Point);
      if(better && (buy ? px - nsl >= md : nsl - px >= md))
         trade.PositionModify(tk, nsl, PositionGetDouble(POSITION_TP));
     }
  }

//+------------------------------------------------------------------+
//| Siklus sesi                                                      |
//+------------------------------------------------------------------+
void StartSession()
  {
   sessBank = InpBankroll;
   if(!IsTester())
      sessBank = MathMin(InpBankroll, AccountInfoDouble(ACCOUNT_EQUITY));
   sessRealized = 0;
   sessPeak = sessBank;
   sessStart = TimeCurrent();
   sessEnd = sessStart + InpSessionMinutes * 60;
   inSess = true;
   lastBar = 0;
   if(!IsTester())
      PrintFormat("Sesi dimulai: modal %.2f, target %.2f, batas %.2f, sampai %s",
                  sessBank, sessBank * InpTargetMult, InpBustUSD, TimeToString(sessEnd, TIME_MINUTES));
  }

double RealizedFromHistory()
  {
   double s = 0;
   if(!HistorySelect(sessStart, TimeCurrent() + 60))
      return sessRealized;
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
     {
      ulong tk = HistoryDealGetTicket(i);
      if(tk == 0 || HistoryDealGetInteger(tk, DEAL_MAGIC) != InpMagic || HistoryDealGetString(tk, DEAL_SYMBOL) != _Symbol)
         continue;
      s += HistoryDealGetDouble(tk, DEAL_PROFIT) + HistoryDealGetDouble(tk, DEAL_COMMISSION) +
           HistoryDealGetDouble(tk, DEAL_SWAP) + HistoryDealGetDouble(tk, DEAL_FEE);
     }
   return s;
  }

void EndSession(const int outcome)
  {
   CancelPending();
   CloseAll();
   double fin = MathMax(sessBank + RealizedFromHistory(), 0.0);
   int k = ArraySize(resFinal);
   ArrayResize(resFinal, k + 1);
   ArrayResize(resOut, k + 1);
   resFinal[k] = fin;
   resOut[k] = outcome;
   string os = outcome == OUT_TARGET ? "TARGET" : outcome == OUT_BUST ? "HABIS" : "WAKTU";
   PrintFormat("[Sesi %d] %s  %.2f -> %.2f (%.2fx, puncak %.2f)  %s", k + 1,
               TimeToString(sessStart, TIME_DATE | TIME_MINUTES), sessBank, fin, fin / sessBank, sessPeak, os);
   inSess = false;
   if(!IsTester() && InpStartNow)
     {
      liveDone = true;
      Comment(StringFormat("VideoScalper: sesi selesai (%s). Hasil %.2f -> %.2f\nLepas & pasang ulang EA untuk sesi baru.", os, sessBank, fin));
     }
  }

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(!inSess || trans.type != TRADE_TRANSACTION_DEAL_ADD || !HistoryDealSelect(trans.deal))
      return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagic || HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol)
      return;
   sessRealized += HistoryDealGetDouble(trans.deal, DEAL_PROFIT) + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION) +
                   HistoryDealGetDouble(trans.deal, DEAL_SWAP) + HistoryDealGetDouble(trans.deal, DEAL_FEE);
   // straddle: satu sisi terisi -> hapus sisi lain
   if(InpModel == MODEL_STRADDLE && HistoryDealGetInteger(trans.deal, DEAL_ENTRY) == DEAL_ENTRY_IN)
      CancelPending();
  }

void OnTick()
  {
   if(inSess)
     {
      double eq = SessEquity();
      sessPeak = MathMax(sessPeak, eq);
      if(eq >= sessBank * InpTargetMult)
         EndSession(OUT_TARGET);
      else if(eq <= InpBustUSD)
         EndSession(OUT_BUST);
      else if(TimeCurrent() >= sessEnd)
         EndSession(OUT_TIME);
      else
        {
         Trail();
         datetime b = iTime(_Symbol, PERIOD_M1, 0);
         double px = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         bool moved = InpModel != MODEL_STRADDLE && MathAbs(px - lastSyncPx) >= InpStepUSD * 0.5;
         if(b != lastBar || moved)
           {
            lastBar = b;
            lastSyncPx = px;
            RefreshOrders();
           }
         if(!IsTester())
            Comment(StringFormat("VideoScalper SESI BERJALAN\nModal sesi: %.2f (awal %.2f, target %.2f, batas %.2f)\nSisa waktu: %d menit | Lot: %.2f | Posisi: %d",
                                 eq, sessBank, sessBank * InpTargetMult, InpBustUSD,
                                 (int)((sessEnd - TimeCurrent()) / 60), SessLots(), CountPositions()));
        }
      return;
     }

   if(!IsTester() && InpStartNow)
     {
      if(!liveDone)
         StartSession();
      return;
     }

   // jadwal: mulai sesi bila baru lewat jam slot (toleransi 2 menit)
   datetime now = TimeCurrent();
   datetime d0 = (datetime)(now - (now % 86400));
   for(int i = 0; i < ArraySize(slotMin); i++)
     {
      datetime t = d0 + slotMin[i] * 60;
      if(now >= t && now < t + 120 && slotDone[i] != d0)
        {
         slotDone[i] = d0;
         StartSession();
         break;
        }
     }
  }

//+------------------------------------------------------------------+
//| Ringkasan semua sesi                                             |
//+------------------------------------------------------------------+
void PrintSummary()
  {
   int n = ArraySize(resFinal);
   if(n == 0)
      return;
   int nT = 0, nB = 0, nW = 0, nFlat = 0;
   double sum = 0, best = 0;
   int buckets[6] = {0, 0, 0, 0, 0, 0};
   for(int i = 0; i < n; i++)
     {
      if(resOut[i] == OUT_TARGET)
         nT++;
      else if(resOut[i] == OUT_BUST)
         nB++;
      else
         nW++;
      sum += resFinal[i];
      if(MathAbs(resFinal[i] - InpBankroll) < 0.005)
         nFlat++;
      best = MathMax(best, resFinal[i]);
      double m = resFinal[i] / InpBankroll;
      int b = m < 0.5 ? 0 : m < 1.0 ? 1 : m < 2.0 ? 2 : m < 5.0 ? 3 : m < 10.0 ? 4 : 5;
      buckets[b]++;
     }
   double sorted[];
   ArrayCopy(sorted, resFinal);
   ArraySort(sorted);
   double median = sorted[n / 2];
   Print("===== Ringkasan VideoScalper: ", n, " sesi, modal ", DoubleToString(InpBankroll, 2), " per sesi =====");
   PrintFormat("Mencapai target %.0fx : %4d (%.1f%%)", InpTargetMult, nT, 100.0 * nT / n);
   PrintFormat("Habis (<= %.2f)      : %4d (%.1f%%)", InpBustUSD, nB, 100.0 * nB / n);
   PrintFormat("Selesai karena waktu : %4d (%.1f%%), %d di antaranya tanpa trade", nW, 100.0 * nW / n, nFlat);
   PrintFormat("Rata-rata akhir %.2f (%.2fx) | median %.2f | terbaik %.2f", sum / n, sum / n / InpBankroll, median, best);
   string lbl[6] = {"< 0.5x", "0.5-1x", "1-2x", "2-5x", "5-10x", ">= 10x"};
   for(int b = 0; b < 6; b++)
      PrintFormat("  %-7s %4d (%.1f%%)", lbl[b], buckets[b], 100.0 * buckets[b] / n);
   Print("Rata-rata akhir > modal berarti model ini untung bila diulang terus; < modal berarti rugi.");
  }

//--- kriteria optimizer (pilih "Custom max"): rata-rata kelipatan modal per sesi
double OnTester()
  {
   int n = ArraySize(resFinal);
   if(n < 30)
      return 0;
   double sum = 0;
   for(int i = 0; i < n; i++)
      sum += resFinal[i];
   return sum / n / InpBankroll;
  }
//+------------------------------------------------------------------+
