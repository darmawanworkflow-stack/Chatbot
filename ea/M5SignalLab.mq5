//+------------------------------------------------------------------+
//| M5SignalLab.mq5                                                  |
//| Mengukur kualitas beberapa sinyal M5 dengan target 3R yang sama. |
//| Ketiga sinyal berjalan bersamaan (masing-masing maks 1 posisi),  |
//| risiko kecil per trade, lalu hasil per sinyal dalam satuan R     |
//| dicetak di Journal saat backtest selesai.                        |
//|                                                                  |
//|  LB  London breakout : candle M5 tutup di luar range Asia        |
//|                        (00:00-07:00), dicek 07:00-11:00          |
//|  PB  Pullback EMA    : tren H1 + EMA20>EMA50 M5, harga menyentuh |
//|                        EMA20 lalu candle M5 tutup searah tren    |
//|  MO  Momentum        : candle M5 tutup menembus high/low 48 bar  |
//|                        (4 jam) searah tren H1                    |
//| Semua jam memakai waktu server broker.                           |
//+------------------------------------------------------------------+
#property copyright "Chatbot repo"
#property version   "1.00"
#property description "Uji kualitas sinyal M5 (target 3R). Untuk Strategy Tester."

#include <Trade\Trade.mqh>

input group "=== Risiko & exit ==="
input double InpRiskPct       = 0.5;        // Risiko per trade (% equity) - kecil, hanya untuk mengukur
input double InpCommissionLot = 11.0;       // Komisi round-turn per 1 lot
input double InpSLATR         = 1.5;        // SL = x ATR(14) M5
input double InpRR            = 3.0;        // TP = RR x SL
input int    InpMaxHoldBars   = 48;         // Tutup paksa setelah N bar M5 (48 = 4 jam)
input int    InpCloseHour     = 20;         // Tutup semua posisi jam ini (server)
input double InpMaxSpreadUSD  = 0.30;       // Spread maks saat entry (USD)

input group "=== Sinyal ==="
input bool   InpUseLB         = true;       // London breakout
input bool   InpUsePB         = true;       // Pullback EMA searah tren H1
input bool   InpUseMO         = true;       // Momentum breakout 4 jam
input int    InpTradeFrom     = 7;          // PB/MO: mulai jam (server)
input int    InpTradeTo       = 18;         // PB/MO: berhenti entry jam (server)
input int    InpAsiaEnd       = 7;          // LB: range Asia 00:00 - jam ini
input int    InpLBUntil       = 11;         // LB: entry paling lambat jam ini
input int    InpMOBars        = 48;         // MO: jumlah bar high/low

input long   InpMagic         = 20261101;   // Magic number

CTrade   trade;
int      hE20 = INVALID_HANDLE, hE50 = INVALID_HANDLE, hAtr = INVALID_HANDLE, hH1 = INVALID_HANDLE;
datetime lastBar = 0;
datetime lbDone  = 0;
string   TAGS[3]  = {"LB", "PB", "MO"};
string   NAMES[3] = {"London breakout", "Pullback EMA", "Momentum 4 jam"};

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
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   PrintStats();
   IndicatorRelease(hE20);
   IndicatorRelease(hE50);
   IndicatorRelease(hAtr);
   IndicatorRelease(hH1);
  }

double Buf(const int h, const int shift)
  {
   double a[1];
   if(CopyBuffer(h, 0, shift, 1, a) != 1)
      return 0;
   return a[0];
  }

string TagOf(const string c)
  {
   int p = StringFind(c, "|");
   return (p < 0) ? "" : StringSubstr(c, p + 1, 2);
  }

bool HasPos(const string tag)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(PositionGetTicket(i) > 0 && PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == InpMagic && TagOf(PositionGetString(POSITION_COMMENT)) == tag)
         return true;
   return false;
  }

//--- +1 naik, -1 turun, 0 netral: close H1 vs EMA50 H1 dan arah EMA
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

double LotsFor(const double slDist)
  {
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tv <= 0)
      tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(tv <= 0 || ts <= 0 || slDist <= 0)
      return 0;
   double lossPerLot = slDist / ts * tv + InpCommissionLot;
   double lots = AccountInfoDouble(ACCOUNT_EQUITY) * InpRiskPct / 100.0 / lossPerLot;
   lots = MathFloor(lots / step + 1e-9) * step;
   return lots < vmin ? 0 : lots;
  }

void Enter(const bool buy, const string tag)
  {
   if(HasPos(tag))
      return;
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask - bid > InpMaxSpreadUSD)
      return;
   double atr = Buf(hAtr, 1);
   if(atr <= 0)
      return;
   double sl = InpSLATR * atr;
   double lots = LotsFor(sl);
   if(lots <= 0)
      return;
   double px = buy ? ask : bid;
   double slp = NormalizeDouble(buy ? px - sl : px + sl, _Digits);
   double tpp = NormalizeDouble(buy ? px + InpRR * sl : px - InpRR * sl, _Digits);
   string cmt = "LAB|" + tag;
   if(buy)
      trade.Buy(lots, _Symbol, 0, slp, tpp, cmt);
   else
      trade.Sell(lots, _Symbol, 0, slp, tpp, cmt);
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

//+------------------------------------------------------------------+
void OnTick()
  {
   TimeExits();
   datetime b = iTime(_Symbol, PERIOD_M5, 0);
   if(b == lastBar)
      return;
   lastBar = b;

   datetime now = TimeCurrent();
   datetime d0 = (datetime)(now - (now % 86400));
   MqlDateTime dt;
   TimeToStruct(now, dt);
   double c1 = iClose(_Symbol, PERIOD_M5, 1);
   double o1 = iOpen(_Symbol, PERIOD_M5, 1);
   double l1 = iLow(_Symbol, PERIOD_M5, 1);
   double h1 = iHigh(_Symbol, PERIOD_M5, 1);
   if(c1 <= 0)
      return;

   // --- LB: London breakout
   if(InpUseLB && lbDone != d0 && dt.hour >= InpAsiaEnd && dt.hour < InpLBUntil)
     {
      double hi[], lo[];
      datetime rs = d0, re = d0 + InpAsiaEnd * 3600 - 1;
      int nh = CopyHigh(_Symbol, PERIOD_M5, rs, re, hi);
      int nl = CopyLow(_Symbol, PERIOD_M5, rs, re, lo);
      if(nh > 30 && nl > 30)
        {
         double rH = hi[ArrayMaximum(hi)], rL = lo[ArrayMinimum(lo)];
         if(c1 > rH)
           {
            Enter(true, "LB");
            lbDone = d0;
           }
         else if(c1 < rL)
           {
            Enter(false, "LB");
            lbDone = d0;
           }
        }
     }

   if(dt.hour < InpTradeFrom || dt.hour >= InpTradeTo)
      return;
   int bias = H1Bias();
   if(bias == 0)
      return;

   // --- PB: pullback ke EMA20 M5 searah tren
   if(InpUsePB)
     {
      double e20 = Buf(hE20, 1), e50 = Buf(hE50, 1);
      if(bias > 0 && e20 > e50 && l1 <= e20 && c1 > e20 && c1 > o1)
         Enter(true, "PB");
      if(bias < 0 && e20 < e50 && h1 >= e20 && c1 < e20 && c1 < o1)
         Enter(false, "PB");
     }

   // --- MO: tembus high/low 4 jam searah tren
   if(InpUseMO)
     {
      double hi[], lo[];
      if(CopyHigh(_Symbol, PERIOD_M5, 2, InpMOBars, hi) == InpMOBars &&
         CopyLow(_Symbol, PERIOD_M5, 2, InpMOBars, lo) == InpMOBars)
        {
         if(bias > 0 && c1 > hi[ArrayMaximum(hi)])
            Enter(true, "MO");
         if(bias < 0 && c1 < lo[ArrayMinimum(lo)])
            Enter(false, "MO");
        }
     }
  }

//+------------------------------------------------------------------+
//| Statistik per sinyal dalam satuan R (sudah termasuk biaya)       |
//+------------------------------------------------------------------+
void PrintStats()
  {
   if(!HistorySelect(0, TimeCurrent() + 86400))
      return;
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   long   pid[];
   int    ptag[];
   double pnet[], prisk[];
   bool   pclosed[];
   int    np = 0;

   for(int i = 0; i < HistoryDealsTotal(); i++)
     {
      ulong tk = HistoryDealGetTicket(i);
      if(tk == 0 || HistoryDealGetInteger(tk, DEAL_MAGIC) != InpMagic || HistoryDealGetString(tk, DEAL_SYMBOL) != _Symbol)
         continue;
      long t = HistoryDealGetInteger(tk, DEAL_TYPE);
      if(t != DEAL_TYPE_BUY && t != DEAL_TYPE_SELL)
         continue;
      long pos = HistoryDealGetInteger(tk, DEAL_POSITION_ID);
      int idx = -1;
      for(int j = np - 1; j >= 0; j--)
         if(pid[j] == pos)
           {
            idx = j;
            break;
           }
      if(idx < 0)
        {
         idx = np++;
         ArrayResize(pid, np);
         ArrayResize(ptag, np);
         ArrayResize(pnet, np);
         ArrayResize(prisk, np);
         ArrayResize(pclosed, np);
         pid[idx] = pos;
         ptag[idx] = -1;
         pnet[idx] = 0;
         prisk[idx] = 0;
         pclosed[idx] = false;
        }
      pnet[idx] += HistoryDealGetDouble(tk, DEAL_PROFIT) + HistoryDealGetDouble(tk, DEAL_COMMISSION) +
                   HistoryDealGetDouble(tk, DEAL_SWAP) + HistoryDealGetDouble(tk, DEAL_FEE);
      if(HistoryDealGetInteger(tk, DEAL_ENTRY) == DEAL_ENTRY_IN)
        {
         ulong ord = (ulong)HistoryDealGetInteger(tk, DEAL_ORDER);
         string c = HistoryOrderGetString(ord, ORDER_COMMENT);
         if(c == "")
            c = HistoryDealGetString(tk, DEAL_COMMENT);
         string tg = TagOf(c);
         for(int k = 0; k < 3; k++)
            if(TAGS[k] == tg)
               ptag[idx] = k;
         double slp = HistoryOrderGetDouble(ord, ORDER_SL);
         double ep  = HistoryDealGetDouble(tk, DEAL_PRICE);
         double vol = HistoryDealGetDouble(tk, DEAL_VOLUME);
         if(slp > 0 && ts > 0)
            prisk[idx] = MathAbs(ep - slp) / ts * tv * vol + InpCommissionLot * vol;
        }
      else
         pclosed[idx] = true;
     }

   Print("===== M5SignalLab: hasil per sinyal (target ", DoubleToString(InpRR, 1), "R, biaya termasuk) =====");
   Print("Sinyal            Trade  Win%   Rata2 R   Total R    PF");
   for(int k = 0; k < 3; k++)
     {
      int n = 0, w = 0;
      double sumR = 0, gp = 0, gl = 0;
      for(int j = 0; j < np; j++)
        {
         if(ptag[j] != k || !pclosed[j] || prisk[j] <= 0)
            continue;
         double r = pnet[j] / prisk[j];
         n++;
         sumR += r;
         if(r > 0)
           {
            w++;
            gp += r;
           }
         else
            gl -= r;
        }
      string pf = gl > 0 ? DoubleToString(gp / gl, 2) : "-";
      PrintFormat("%-16s %6d  %5.1f  %+7.3f  %+8.2f  %5s", NAMES[k], n, n > 0 ? 100.0 * w / n : 0,
                  n > 0 ? sumR / n : 0, sumR, pf);
     }
   PrintFormat("Acuan: target %.0fR butuh win rate > %.0f%% untuk impas (sebelum biaya). Rata2 R > 0 = punya edge.",
               InpRR, 100.0 / (InpRR + 1));
  }
//+------------------------------------------------------------------+
