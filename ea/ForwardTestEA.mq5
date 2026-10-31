//+------------------------------------------------------------------+
//| ForwardTestEA.mq5  (EA, simpan di MQL5/Experts)                  |
//| Uji maju otomatis di AKUN DEMO untuk dua hipotesis riset:        |
//|                                                                  |
//|  NP  Pullback di jendela berita (sama dengan NewsPullbackArrows):|
//|      jam 07-18, 30 mnt sebelum s/d 60 mnt sesudah berita USD     |
//|      high; tren H1 + EMA20/50 M5 + candle pullback ke EMA20.     |
//|      SL 1.5 ATR, TP 3R, tutup paksa setelah 48 candle.           |
//|  AL  Awal fase "selaras penuh" (sama dengan tanda emas           |
//|      TechnicalMap): H4, H1, M15, M5 baru saja searah, jam 07-18. |
//|      SL 2 ATR tanpa TP; keluar saat M15 tidak lagi searah atau   |
//|      setelah 96 candle.                                          |
//|                                                                  |
//| Lot kecil berbasis risiko %. Setiap trade selesai dicatat ke     |
//| MQL5/Files/forwardtest_log.csv (dengan hasil dalam R) dan        |
//| ringkasan per strategi tampil di chart (pojok kiri bawah).       |
//| HANYA UNTUK AKUN DEMO.                                           |
//+------------------------------------------------------------------+
#property copyright "Chatbot repo"
#property version   "1.00"
#property description "Uji maju otomatis (demo): pullback saat berita + awal selaras penuh multi-timeframe."

#include <Trade\Trade.mqh>

input group "=== Umum ==="
input bool   InpDemoOnly      = true;        // Tolak berjalan di akun real
input double InpRiskPct       = 0.5;         // Risiko per trade (% equity)
input double InpCommissionLot = 11.0;        // Komisi round-turn per 1 lot (untuk ukuran lot)
input double InpMaxSpreadUSD  = 0.50;        // Spread maks saat entry (USD)
input int    InpFromHour      = 7;           // Jam mulai entry (server)
input int    InpToHour        = 18;          // Jam berhenti entry (server)
input long   InpMagic         = 20261103;    // Magic number
input string InpLogFile       = "forwardtest_log.csv"; // File log di MQL5/Files

input group "=== NP: pullback saat berita ==="
input bool   InpUseNP         = true;        // Aktifkan
input int    InpBeforeMin     = 30;          // Jendela: menit sebelum berita
input int    InpAfterMin      = 60;          // Jendela: menit sesudah berita
input double InpNPSLATR       = 1.5;         // SL = x ATR(14) M5
input double InpNPRR          = 3.0;         // TP = RR x SL
input int    InpNPHold        = 48;          // Tutup paksa setelah N candle
input string InpCalendarCsv   = "calendar_USD.csv"; // Jadwal berita (opsional) di MQL5/Files

input group "=== AL: awal selaras penuh ==="
input bool   InpUseAL         = true;        // Aktifkan
input double InpALSLATR       = 2.0;         // SL = x ATR(14) M5
input int    InpALHold        = 96;          // Tutup paksa setelah N candle

CTrade   trade;
ENUM_TIMEFRAMES TFS[3] = {PERIOD_M15, PERIOD_H1, PERIOD_H4};
int      hE20[3], hE50[3];
datetime lastBar = 0, lastCalRefresh = 0;
int      prevAlign = 0;
bool     alignInit = false;
datetime newsT[];
string   newsName[];
const string PFX = "FTEA_";

//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpDemoOnly && AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_REAL)
     {
      Alert("ForwardTestEA hanya untuk akun DEMO. Matikan InpDemoOnly bila benar-benar ingin di akun real.");
      return INIT_FAILED;
     }
   for(int k = 0; k < 3; k++)
     {
      hE20[k] = iMA(_Symbol, TFS[k], 20, 0, MODE_EMA, PRICE_CLOSE);
      hE50[k] = iMA(_Symbol, TFS[k], 50, 0, MODE_EMA, PRICE_CLOSE);
      if(hE20[k] == INVALID_HANDLE || hE50[k] == INVALID_HANDLE)
         return INIT_FAILED;
     }
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(50);
   trade.SetTypeFillingBySymbol(_Symbol);
   LoadNews();
   if(!FileIsExist(InpLogFile))
     {
      int h = FileOpen(InpLogFile, FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
      if(h != INVALID_HANDLE)
        {
         FileWrite(h, "open_time", "close_time", "strategi", "arah", "lot", "entry", "exit", "profit_usd", "risk_usd", "R", "catatan");
         FileClose(h);
        }
     }
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, PFX);
  }

//+------------------------------------------------------------------+
//| Jadwal berita (CSV + kalender MT5)                               |
//+------------------------------------------------------------------+
void AddNews(const datetime t, const string name)
  {
   int n = ArraySize(newsT);
   for(int i = 0; i < n; i++)
      if(newsT[i] == t)
         return;
   ArrayResize(newsT, n + 1);
   ArrayResize(newsName, n + 1);
   newsT[n] = t;
   newsName[n] = name;
  }

void LoadNews()
  {
   ArrayResize(newsT, 0);
   ArrayResize(newsName, 0);
   datetime from = TimeCurrent() - 2 * 86400;
   int h = FileOpen(InpCalendarCsv, FILE_READ | FILE_CSV | FILE_ANSI, ',');
   if(h != INVALID_HANDLE)
     {
      for(int k = 0; k < 7 && !FileIsEnding(h); k++)
         FileReadString(h);
      while(!FileIsEnding(h))
        {
         string ts = FileReadString(h), cur = FileReadString(h), imp = FileReadString(h), ev = FileReadString(h);
         FileReadString(h);
         FileReadString(h);
         FileReadString(h);
         datetime t = StringToTime(ts);
         if(imp == "high" && t >= from)
            AddNews(t, ev);
        }
      FileClose(h);
     }
   MqlCalendarValue v[];
   int n = CalendarValueHistory(v, from, TimeTradeServer() + 14 * 86400, "US", NULL);
   for(int i = 0; i < n; i++)
     {
      MqlCalendarEvent ev;
      if(CalendarEventById(v[i].event_id, ev) && ev.importance == CALENDAR_IMPORTANCE_HIGH)
         AddNews(v[i].time, ev.name);
     }
   lastCalRefresh = TimeCurrent();
  }

bool InNewsWindow(const datetime t, string &name)
  {
   for(int i = 0; i < ArraySize(newsT); i++)
      if((newsT[i] >= t && newsT[i] - t <= InpBeforeMin * 60) || (newsT[i] < t && t - newsT[i] <= InpAfterMin * 60))
        {
         name = newsName[i];
         return true;
        }
   return false;
  }

//+------------------------------------------------------------------+
//| Indikator                                                        |
//+------------------------------------------------------------------+
double Buf(const int h, const int shift)
  {
   double a[1];
   if(CopyBuffer(h, 0, shift, 1, a) != 1)
      return 0;
   return a[0];
  }

//--- tren TF (k: 0=M15, 1=H1, 2=H4) dari bar terakhir yang sudah tutup
int TrendTF(const int k)
  {
   double e20 = Buf(hE20[k], 1), e50 = Buf(hE50[k], 1), c = iClose(_Symbol, TFS[k], 1);
   if(e20 <= 0 || e50 <= 0)
      return 0;
   if(c > e50 && e20 > e50)
      return 1;
   if(c < e50 && e20 < e50)
      return -1;
   return 0;
  }

//--- bias H1 versi riset NP: close H1 vs EMA50 H1 dan arah EMA50 (3 bar)
int H1Bias()
  {
   double e1 = Buf(hE50[1], 1), e4 = Buf(hE50[1], 4), c = iClose(_Symbol, PERIOD_H1, 1);
   if(e1 <= 0 || e4 <= 0)
      return 0;
   if(c > e1 && e1 > e4)
      return 1;
   if(c < e1 && e1 < e4)
      return -1;
   return 0;
  }

//--- EMA20/50 & ATR(14) Wilder M5 pada candle tutup terakhir (sama dengan riset & indikator)
bool M5State(double &e20, double &e50, double &atr, MqlRates &bar)
  {
   MqlRates r[];
   int n = CopyRates(_Symbol, PERIOD_M5, 1, 800, r);    // lama -> baru, tanpa candle berjalan
   if(n < 300)
      return false;
   double a20 = 2.0 / 21.0, a50 = 2.0 / 51.0;
   e20 = e50 = r[0].close;
   atr = r[0].high - r[0].low;
   for(int i = 1; i < n; i++)
     {
      double tr = MathMax(r[i].high - r[i].low, MathMax(MathAbs(r[i].high - r[i - 1].close), MathAbs(r[i].low - r[i - 1].close)));
      e20 = a20 * r[i].close + (1 - a20) * e20;
      e50 = a50 * r[i].close + (1 - a50) * e50;
      atr = tr / 14.0 + (1 - 1.0 / 14.0) * atr;
     }
   bar = r[n - 1];
   return true;
  }

//+------------------------------------------------------------------+
//| Order                                                            |
//+------------------------------------------------------------------+
bool HasPos(const string tag, ulong &ticket, long &dir, datetime &opened)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0 || PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      if(StringFind(PositionGetString(POSITION_COMMENT), "FT|" + tag) != 0)
         continue;
      ticket = tk;
      dir = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 1 : -1;
      opened = (datetime)PositionGetInteger(POSITION_TIME);
      return true;
     }
   return false;
  }

double LossPerLot(const double slDist)
  {
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tv <= 0)
      tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   return (tv > 0 && ts > 0) ? slDist / ts * tv : 0;
  }

void Open(const string tag, const int d, const double slDist, const double tpDist, const string note)
  {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK), bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask - bid > InpMaxSpreadUSD)
     {
      PrintFormat("%s dilewati: spread %.2f", tag, ask - bid);
      return;
     }
   double lpl = LossPerLot(slDist);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP), vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(lpl <= 0)
      return;
   double lots = MathFloor(AccountInfoDouble(ACCOUNT_EQUITY) * InpRiskPct / 100.0 / (lpl + InpCommissionLot) / step + 1e-9) * step;
   lots = MathMax(lots, vmin);
   double px = d > 0 ? ask : bid;
   double sl = NormalizeDouble(px - d * slDist, _Digits);
   double tp = tpDist > 0 ? NormalizeDouble(px + d * tpDist, _Digits) : 0;
   double riskUsd = lots * lpl;
   // komentar menyimpan strategi & risiko (USD) untuk menghitung R saat posisi ditutup
   string cmt = StringFormat("FT|%s|%.2f", tag, riskUsd);
   bool ok = d > 0 ? trade.Buy(lots, _Symbol, 0, sl, tp, cmt) : trade.Sell(lots, _Symbol, 0, sl, tp, cmt);
   PrintFormat("%s %s %.2f lot, SL %.2f%s, risiko $%.2f (%s) -> %s", tag, d > 0 ? "BUY" : "SELL", lots, sl,
               tp > 0 ? StringFormat(" TP %.2f", tp) : "", riskUsd, note, ok ? "OK" : trade.ResultRetcodeDescription());
  }

//+------------------------------------------------------------------+
//| Log & statistik                                                  |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD || !HistoryDealSelect(trans.deal))
      return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagic || HistoryDealGetInteger(trans.deal, DEAL_ENTRY) != DEAL_ENTRY_OUT)
      return;
   long pos = HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
   if(!HistorySelectByPosition(pos))
      return;
   string cmt = "", tag = "?";
   double risk = 0, entry = 0, lots = 0, profit = 0;
   datetime ot = 0;
   long dir = 0;
   for(int i = 0; i < HistoryDealsTotal(); i++)
     {
      ulong tk = HistoryDealGetTicket(i);
      profit += HistoryDealGetDouble(tk, DEAL_PROFIT) + HistoryDealGetDouble(tk, DEAL_COMMISSION) + HistoryDealGetDouble(tk, DEAL_SWAP);
      if(HistoryDealGetInteger(tk, DEAL_ENTRY) == DEAL_ENTRY_IN)
        {
         cmt = HistoryDealGetString(tk, DEAL_COMMENT);
         entry = HistoryDealGetDouble(tk, DEAL_PRICE);
         lots = HistoryDealGetDouble(tk, DEAL_VOLUME);
         ot = (datetime)HistoryDealGetInteger(tk, DEAL_TIME);
         dir = HistoryDealGetInteger(tk, DEAL_TYPE) == DEAL_TYPE_BUY ? 1 : -1;
        }
     }
   string p[];
   if(StringSplit(cmt, '|', p) >= 3)
     {
      tag = p[1];
      risk = StringToDouble(p[2]);
     }
   double R = risk > 0 ? profit / risk : 0;
   int h = FileOpen(InpLogFile, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
   if(h != INVALID_HANDLE)
     {
      FileSeek(h, 0, SEEK_END);
      FileWrite(h, TimeToString(ot, TIME_DATE | TIME_MINUTES), TimeToString((datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME), TIME_DATE | TIME_MINUTES),
                tag, dir > 0 ? "BUY" : "SELL", DoubleToString(lots, 2), DoubleToString(entry, _Digits),
                DoubleToString(HistoryDealGetDouble(trans.deal, DEAL_PRICE), _Digits), DoubleToString(profit, 2),
                DoubleToString(risk, 2), DoubleToString(R, 2), HistoryDealGetString(trans.deal, DEAL_COMMENT));
      FileClose(h);
     }
   PrintFormat("Tutup %s: %+.2f USD = %+.2fR", tag, profit, R);
  }

void Stats(const string tag, int &n, int &w, double &sumR)
  {
   n = 0;
   w = 0;
   sumR = 0;
   if(!HistorySelect(0, TimeCurrent() + 86400))
      return;
   for(int i = 0; i < HistoryDealsTotal(); i++)
     {
      ulong tk = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(tk, DEAL_MAGIC) != InpMagic || HistoryDealGetInteger(tk, DEAL_ENTRY) != DEAL_ENTRY_IN)
         continue;
      string p[];
      if(StringSplit(HistoryDealGetString(tk, DEAL_COMMENT), '|', p) < 3 || p[1] != tag)
         continue;
      long pos = HistoryDealGetInteger(tk, DEAL_POSITION_ID);
      double risk = StringToDouble(p[2]), prof = 0;
      bool closed = false;
      for(int j = 0; j < HistoryDealsTotal(); j++)
        {
         ulong tj = HistoryDealGetTicket(j);
         if(HistoryDealGetInteger(tj, DEAL_POSITION_ID) != pos)
            continue;
         prof += HistoryDealGetDouble(tj, DEAL_PROFIT) + HistoryDealGetDouble(tj, DEAL_COMMISSION) + HistoryDealGetDouble(tj, DEAL_SWAP);
         if(HistoryDealGetInteger(tj, DEAL_ENTRY) == DEAL_ENTRY_OUT)
            closed = true;
        }
      if(!closed || risk <= 0)
         continue;
      n++;
      sumR += prof / risk;
      if(prof > 0)
         w++;
     }
  }

void Panel(const string status)
  {
   string lines[6];
   int n1, w1, n2, w2;
   double r1, r2;
   Stats("NP", n1, w1, r1);
   Stats("AL", n2, w2, r2);
   lines[0] = "ForwardTestEA (DEMO) - uji maju hipotesis riset";
   lines[1] = StringFormat("NP berita : %3d trade, win %3.0f%%, total %+6.1fR, rata %+.2fR", n1, n1 > 0 ? 100.0 * w1 / n1 : 0, r1, n1 > 0 ? r1 / n1 : 0);
   lines[2] = StringFormat("AL selaras: %3d trade, win %3.0f%%, total %+6.1fR, rata %+.2fR", n2, n2 > 0 ? 100.0 * w2 / n2 : 0, r2, n2 > 0 ? r2 / n2 : 0);
   lines[3] = "Acuan riset: NP +0.06..+0.24R, AL +0.15..+0.19R";
   lines[4] = StringFormat("Status: %s", StringSubstr(status, 0, 54));
   lines[5] = "Log: MQL5/Files/" + InpLogFile;
   for(int i = 0; i < 6; i++)
     {
      string id = PFX + IntegerToString(i);
      ObjectCreate(0, id, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, id, OBJPROP_CORNER, CORNER_LEFT_LOWER);
      ObjectSetInteger(0, id, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
      ObjectSetInteger(0, id, OBJPROP_XDISTANCE, 8);
      ObjectSetInteger(0, id, OBJPROP_YDISTANCE, 10 + (5 - i) * 13);
      ObjectSetString(0, id, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, id, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, id, OBJPROP_COLOR, i == 0 ? clrGold : clrWhiteSmoke);
      ObjectSetInteger(0, id, OBJPROP_SELECTABLE, false);
      ObjectSetString(0, id, OBJPROP_TEXT, lines[i]);
     }
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   datetime b = iTime(_Symbol, PERIOD_M5, 0);
   if(b == lastBar)
      return;
   lastBar = b;
   if(TimeCurrent() - lastCalRefresh > 3600)
      LoadNews();

   double e20, e50, atr;
   MqlRates bar;
   if(!M5State(e20, e50, atr, bar) || atr <= 0)
      return;
   int tr15 = TrendTF(0), tr60 = TrendTF(1), tr240 = TrendTF(2);
   int tr5 = (bar.close > e50 && e20 > e50) ? 1 : ((bar.close < e50 && e20 < e50) ? -1 : 0);
   int align = (tr240 != 0 && tr60 == tr240 && tr15 == tr240 && tr5 == tr240) ? tr240 : 0;
   MqlDateTime dt;
   TimeToStruct(bar.time, dt);
   bool session = dt.hour >= InpFromHour && dt.hour < InpToHour;
   string status = "menunggu";

   // ---- kelola posisi ----
   ulong tk;
   long dir;
   datetime opened;
   if(HasPos("AL", tk, dir, opened))
     {
      if(tr15 != dir || TimeCurrent() - opened >= (long)InpALHold * 300)
         trade.PositionClose(tk);
     }
   if(HasPos("NP", tk, dir, opened) && TimeCurrent() - opened >= (long)InpNPHold * 300)
      trade.PositionClose(tk);

   // ---- AL: awal selaras penuh ----
   if(!alignInit)
     {
      prevAlign = align;              // jangan masuk di candle pertama setelah EA dipasang
      alignInit = true;
     }
   else
     {
      if(InpUseAL && session && align != 0 && align != prevAlign && !HasPos("AL", tk, dir, opened))
        {
         Open("AL", align, InpALSLATR * atr, 0, "awal selaras penuh");
         status = "AL masuk " + (align > 0 ? "BUY" : "SELL");
        }
      prevAlign = align;
     }

   // ---- NP: pullback di jendela berita ----
   string nm = "";
   bool inNews = InNewsWindow(bar.time, nm);
   if(InpUseNP && session && inNews && !HasPos("NP", tk, dir, opened))
     {
      int bias = H1Bias();
      int d = 0;
      if(bias > 0 && e20 > e50 && bar.low <= e20 && bar.close > e20 && bar.close > bar.open)
         d = 1;
      else if(bias < 0 && e20 < e50 && bar.high >= e20 && bar.close < e20 && bar.close < bar.open)
         d = -1;
      if(d != 0)
        {
         Open("NP", d, InpNPSLATR * atr, InpNPRR * InpNPSLATR * atr, nm);
         status = "NP masuk " + (d > 0 ? "BUY" : "SELL") + " (" + nm + ")";
        }
     }
   if(status == "menunggu")
      status = inNews ? "jendela berita: " + nm : (align != 0 ? "fase selaras penuh berjalan" : "menunggu sinyal");
   Panel(status);
  }
//+------------------------------------------------------------------+
