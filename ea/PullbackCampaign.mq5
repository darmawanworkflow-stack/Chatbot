//+------------------------------------------------------------------+
//| PullbackCampaign.mq5                                             |
//| Kampanye modal kecil (mis. $10 -> $100) dengan sinyal Pullback   |
//| EMA M5 searah tren H1 (lolos uji M5SignalLab Jul-Agu & Sep-Okt). |
//|                                                                  |
//| Lot = bagian modal kampanye yang dipertaruhkan per trade (dibagi |
//| kerugian per lot di SL), minimal lot terkecil broker. Dengan $10 |
//| lot terkecil 0.01 sudah berarti risiko ~30-60% per trade.        |
//|                                                                  |
//| Tester : kampanye virtual $10 diulang terus; tiap kampanye       |
//|          selesai saat mencapai target atau modal tidak cukup     |
//|          untuk 1 trade lagi. Ringkasan dicetak di Journal.       |
//| Live   : modal = equity akun; EA berhenti saat target tercapai   |
//|          atau equity tidak cukup untuk 1 trade lagi.             |
//|                                                                  |
//| RISIKO SANGAT TINGGI.                                            |
//+------------------------------------------------------------------+
#property copyright "Chatbot repo"
#property version   "1.00"
#property description "Kampanye $10 -> $100 dengan sinyal Pullback EMA M5. Risiko sangat tinggi."

#include <Trade\Trade.mqh>

input group "=== Kampanye ==="
input double InpStartBank     = 10.0;       // Modal awal kampanye (USD)
input double InpTarget        = 100.0;      // Target modal (USD)
input double InpRiskFrac      = 0.33;       // Bagian modal yang dipertaruhkan per trade (0.33 = 33%)

input group "=== Sinyal & exit (sama dengan M5SignalLab) ==="
input double InpSLATR         = 1.5;        // SL = x ATR(14) M5
input double InpRR            = 3.0;        // TP = RR x SL
input int    InpMaxHoldBars   = 48;         // Tutup paksa setelah N bar M5
input int    InpCloseHour     = 20;         // Tutup posisi jam ini (server)
input int    InpTradeFrom     = 7;          // Mulai entry jam (server)
input int    InpTradeTo       = 18;         // Berhenti entry jam (server)
input double InpMaxSpreadUSD  = 0.30;       // Spread maks saat entry (USD)
input double InpCommissionLot = 11.0;       // Komisi round-turn per 1 lot

input long   InpMagic         = 20261102;   // Magic number

CTrade   trade;
int      hE20 = INVALID_HANDLE, hE50 = INVALID_HANDLE, hAtr = INVALID_HANDLE, hH1 = INVALID_HANDLE;
datetime lastBar = 0;

double   bank = 0;           // modal kampanye berjalan (realized)
int      campTrades = 0;
datetime campStart = 0;
bool     liveStopped = false;
int      nCamp = 0, nWin = 0, nBust = 0;
int      tradesWin = 0, tradesBust = 0;
double   peakSum = 0, campPeak = 0;

bool IsTester()
  {
   return MQLInfoInteger(MQL_TESTER) != 0;
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   hE20 = iMA(_Symbol, PERIOD_M5, 20, 0, MODE_EMA, PRICE_CLOSE);
   hE50 = iMA(_Symbol, PERIOD_M5, 50, 0, MODE_EMA, PRICE_CLOSE);
   hAtr = iATR(_Symbol, PERIOD_M5, 14);
   hH1  = iMA(_Symbol, PERIOD_H1, 50, 0, MODE_EMA, PRICE_CLOSE);
   if(hE20 == INVALID_HANDLE || hE50 == INVALID_HANDLE || hAtr == INVALID_HANDLE || hH1 == INVALID_HANDLE)
      return INIT_FAILED;
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(50);
   trade.SetTypeFillingBySymbol(_Symbol);
   NewCampaign();
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   if(IsTester())
      PrintSummary();
   IndicatorRelease(hE20);
   IndicatorRelease(hE50);
   IndicatorRelease(hAtr);
   IndicatorRelease(hH1);
   Comment("");
  }

void NewCampaign()
  {
   bank = IsTester() ? InpStartBank : AccountInfoDouble(ACCOUNT_EQUITY);
   campTrades = 0;
   campStart = TimeCurrent();
   campPeak = bank;
  }

double Buf(const int h, const int shift)
  {
   double a[1];
   if(CopyBuffer(h, 0, shift, 1, a) != 1)
      return 0;
   return a[0];
  }

int CountPositions()
  {
   int c = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(PositionGetTicket(i) > 0 && PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == InpMagic)
         c++;
   return c;
  }

int H1Bias()
  {
   double e1 = Buf(hH1, 1), e4 = Buf(hH1, 4);
   double c = iClose(_Symbol, PERIOD_H1, 1);
   if(e1 <= 0 || e4 <= 0)
      return 0;
   if(c > e1 && e1 > e4)
      return 1;
   if(c < e1 && e1 < e4)
      return -1;
   return 0;
  }

double LossPerLot(const double slDist)
  {
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tv <= 0)
      tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tv <= 0 || ts <= 0)
      return 0;
   return slDist / ts * tv + InpCommissionLot;
  }

//--- lot untuk modal kampanye; 0 bila modal tidak cukup untuk lot terkecil
double CampaignLots(const double slDist)
  {
   double lpl = LossPerLot(slDist);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(lpl <= 0)
      return 0;
   if(vmin * lpl >= bank)          // satu kali SL dengan lot terkecil sudah menghabiskan modal
      return 0;
   double lots = MathFloor(bank * InpRiskFrac / lpl / step + 1e-9) * step;
   return MathMax(lots, vmin);
  }

//+------------------------------------------------------------------+
void EndCampaign(const bool win)
  {
   nCamp++;
   if(win)
     {
      nWin++;
      tradesWin += campTrades;
     }
   else
     {
      nBust++;
      tradesBust += campTrades;
     }
   peakSum += campPeak;
   PrintFormat("[Kampanye %d] %s -> %s  modal akhir %.2f, puncak %.2f, %d trade  %s", nCamp,
               TimeToString(campStart, TIME_DATE), TimeToString(TimeCurrent(), TIME_DATE),
               bank, campPeak, campTrades, win ? "TARGET" : "HABIS");
   if(IsTester())
      NewCampaign();
   else
     {
      liveStopped = true;
      Comment(StringFormat("PullbackCampaign selesai: %s (equity %.2f).", win ? "TARGET TERCAPAI" : "MODAL HABIS", bank));
     }
  }

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD || !HistoryDealSelect(trans.deal))
      return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagic || HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol)
      return;
   bank += HistoryDealGetDouble(trans.deal, DEAL_PROFIT) + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION) +
           HistoryDealGetDouble(trans.deal, DEAL_SWAP) + HistoryDealGetDouble(trans.deal, DEAL_FEE);
   if(HistoryDealGetInteger(trans.deal, DEAL_ENTRY) == DEAL_ENTRY_IN)
      campTrades++;
   campPeak = MathMax(campPeak, bank);
  }

void TimeExits()
  {
   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0 || PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      datetime op = (datetime)PositionGetInteger(POSITION_TIME);
      if(now - op >= (long)InpMaxHoldBars * 300 || dt.hour >= InpCloseHour || op < (datetime)(now - (now % 86400)))
         trade.PositionClose(tk);
     }
  }

void Enter(const bool buy)
  {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask - bid > InpMaxSpreadUSD)
      return;
   double atr = Buf(hAtr, 1);
   if(atr <= 0)
      return;
   double sl = InpSLATR * atr;
   double lots = CampaignLots(sl);
   if(lots <= 0)
      return;
   double px = buy ? ask : bid;
   double slp = NormalizeDouble(buy ? px - sl : px + sl, _Digits);
   double tpp = NormalizeDouble(buy ? px + InpRR * sl : px - InpRR * sl, _Digits);
   if(buy)
      trade.Buy(lots, _Symbol, 0, slp, tpp, "CAMP|PB");
   else
      trade.Sell(lots, _Symbol, 0, slp, tpp, "CAMP|PB");
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   if(liveStopped)
      return;
   TimeExits();

   // kampanye selesai hanya saat tidak ada posisi terbuka
   if(CountPositions() == 0)
     {
      if(bank >= InpTarget)
        {
         EndCampaign(true);
         return;
        }
      double atrNow = Buf(hAtr, 1);
      double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      if(atrNow > 0 && vmin * LossPerLot(InpSLATR * atrNow) >= bank)
        {
         EndCampaign(false);
         return;
        }
     }

   datetime b = iTime(_Symbol, PERIOD_M5, 0);
   if(b == lastBar)
      return;
   lastBar = b;

   if(!IsTester())
      Comment(StringFormat("PullbackCampaign | modal %.2f -> target %.2f | trade %d", bank, InpTarget, campTrades));

   if(CountPositions() > 0)
      return;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.hour < InpTradeFrom || dt.hour >= InpTradeTo)
      return;
   int bias = H1Bias();
   if(bias == 0)
      return;

   double c1 = iClose(_Symbol, PERIOD_M5, 1), o1 = iOpen(_Symbol, PERIOD_M5, 1);
   double l1 = iLow(_Symbol, PERIOD_M5, 1), h1 = iHigh(_Symbol, PERIOD_M5, 1);
   double e20 = Buf(hE20, 1), e50 = Buf(hE50, 1);
   if(bias > 0 && e20 > e50 && l1 <= e20 && c1 > e20 && c1 > o1)
      Enter(true);
   else if(bias < 0 && e20 < e50 && h1 >= e20 && c1 < e20 && c1 < o1)
      Enter(false);
  }

//+------------------------------------------------------------------+
void PrintSummary()
  {
   Print("===== PullbackCampaign: $", DoubleToString(InpStartBank, 0), " -> $", DoubleToString(InpTarget, 0),
         ", risiko ", DoubleToString(InpRiskFrac * 100, 0), "% per trade =====");
   PrintFormat("Kampanye selesai : %d", nCamp);
   PrintFormat("Mencapai target  : %d (%.1f%%)", nWin, nCamp > 0 ? 100.0 * nWin / nCamp : 0);
   PrintFormat("Modal habis      : %d (%.1f%%)", nBust, nCamp > 0 ? 100.0 * nBust / nCamp : 0);
   PrintFormat("Rata-rata trade  : %.1f per kampanye sukses, %.1f per kampanye habis",
               nWin > 0 ? (double)tradesWin / nWin : 0, nBust > 0 ? (double)tradesBust / nBust : 0);
   PrintFormat("Rata-rata puncak modal per kampanye: %.2f", nCamp > 0 ? peakSum / nCamp : 0);
   PrintFormat("Kampanye terakhir belum selesai: modal %.2f setelah %d trade", bank, campTrades);
  }
//+------------------------------------------------------------------+
