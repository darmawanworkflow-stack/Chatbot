//+------------------------------------------------------------------+
//| SessionORB.mq5                                                   |
//| Opening Range Breakout per sesi (London & New York).             |
//|  1. Catat high/low selama jendela range (mis. sesi Asia).        |
//|  2. Saat range selesai: Buy Stop di atas high, Sell Stop di      |
//|     bawah low (OCO, satu terisi -> yang lain dihapus).           |
//|  3. SL = sebagian dari lebar range, TP = RR x SL.                |
//|  4. Pending dihapus di akhir jendela entry, posisi ditutup pada  |
//|     jam tutup harian.                                            |
//| Semua jam memakai WAKTU SERVER broker.                           |
//+------------------------------------------------------------------+
#property copyright "Chatbot repo"
#property version   "1.01"
#property description "Session Opening Range Breakout (XAUUSD). Uji di Strategy Tester & demo dulu."

#include <Trade\Trade.mqh>

input group "=== Umum ==="
input long   InpMagic          = 20261030;   // Magic number
input double InpRiskPct        = 1.0;        // Risiko per trade (% equity)
input double InpCommissionLot  = 11.0;       // Komisi round-turn per 1 lot (uang akun)
input bool   InpForceMinLot    = false;      // Paksa lot minimum walau risiko > target
input int    InpMaxSpreadPts   = 50;         // Spread maks saat memasang order (points)
input int    InpSlippage       = 30;         // Slippage (points)

input group "=== Sesi London ==="
input bool   InpUseLondon      = true;       // Aktifkan sesi London
input string InpLonRangeStart  = "00:00";    // Range mulai (HH:MM server)
input string InpLonRangeEnd    = "07:00";    // Range selesai = order dipasang
input string InpLonEntryEnd    = "11:00";    // Pending dihapus jam ini

input group "=== Sesi New York ==="
input bool   InpUseNY          = true;       // Aktifkan sesi New York
input string InpNyRangeStart   = "11:00";    // Range mulai (HH:MM server)
input string InpNyRangeEnd     = "13:30";    // Range selesai = order dipasang
input string InpNyEntryEnd     = "16:00";    // Pending dihapus jam ini

input group "=== Order & exit ==="
input int    InpBufferPts      = 20;         // Jarak order dari high/low range (points)
input double InpSLFrac         = 0.5;        // SL = x lebar range (0.5 = tengah range)
input double InpRR             = 2.0;        // TP = RR x jarak SL
input double InpBER            = 1.0;        // Geser SL ke entry setelah profit x R (0 = off)
input string InpCloseTime      = "20:00";    // Tutup semua posisi jam ini
input double InpMinRangeD1     = 0.10;       // Range minimum (x ATR harian)
input double InpMaxRangeD1     = 0.70;       // Range maksimum (x ATR harian)

input group "=== Filter berita (kalender MT5, tidak jalan di tester) ==="
input bool   InpUseNews        = true;       // Aktifkan filter berita
input string InpNewsCurrencies = "USD";      // Mata uang, pisahkan koma
input int    InpNewsBeforeMin  = 30;         // Jangan pasang order N menit sebelum berita
input int    InpNewsAfterMin   = 15;         // ... sampai N menit sesudah berita

//--- globals
CTrade   trade;
int      hAtrD1 = INVALID_HANDLE;
datetime lastBar = 0;
string   SESS_TAGS[] = {"LO", "NY"};
datetime sessDone[2];          // hari (00:00) saat sesi sudah diproses
string   sessInfo[2];          // keterangan untuk dashboard
string   sessWait[2];          // alasan terakhir sesi belum terpasang
int      sessWaitR[2];
//--- penghitung keputusan per sesi
#define R_PLACED   0
#define R_NODATA   1
#define R_HOLIDAY  2
#define R_SMALL    3
#define R_BIG      4
#define R_NEWS     5
#define R_PASSED   6
#define R_SPREAD   7
#define R_COUNT    8
string   REASON_NAMES[R_COUNT] = {"order dipasang", "data M1/ATR tidak tersedia", "data range kurang (libur)",
                                  "range terlalu sempit", "range terlalu lebar", "berita",
                                  "harga sudah lewat level", "spread tinggi sampai jendela habis"};
int      reasonCnt[2][R_COUNT];

void Note(const int s, const int r, const string msg)
  {
   sessInfo[s] = msg;
   if(r >= 0)
      reasonCnt[s][r]++;
   Print("[", SESS_TAGS[s], "] ", TimeToString(TimeCurrent(), TIME_DATE), " ", msg);
  }

//+------------------------------------------------------------------+
int ParseHHMM(const string s)
  {
   string p[];
   if(StringSplit(s, ':', p) != 2)
      return -1;
   int h = (int)StringToInteger(p[0]), m = (int)StringToInteger(p[1]);
   if(h < 0 || h > 23 || m < 0 || m > 59)
      return -1;
   return h * 60 + m;
  }

datetime DayStart(const datetime t)
  {
   return (datetime)(t - (t % 86400));
  }

string TagFromComment(const string c)
  {
   int p = StringFind(c, "|");
   if(p < 0 || StringLen(c) < p + 3)
      return "";
   return StringSubstr(c, p + 1, 2);
  }

bool OurSymbolMagicPos()
  {
   return PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagic;
  }

bool OurSymbolMagicOrd()
  {
   return OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == InpMagic;
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   string times[] = {InpLonRangeStart, InpLonRangeEnd, InpLonEntryEnd,
                     InpNyRangeStart, InpNyRangeEnd, InpNyEntryEnd, InpCloseTime};
   for(int i = 0; i < ArraySize(times); i++)
      if(ParseHHMM(times[i]) < 0)
        {
         Print("Format jam salah: ", times[i], " (pakai HH:MM)");
         return INIT_PARAMETERS_INCORRECT;
        }
   if(ParseHHMM(InpLonRangeStart) >= ParseHHMM(InpLonRangeEnd) || ParseHHMM(InpLonRangeEnd) >= ParseHHMM(InpLonEntryEnd) ||
      ParseHHMM(InpNyRangeStart) >= ParseHHMM(InpNyRangeEnd) || ParseHHMM(InpNyRangeEnd) >= ParseHHMM(InpNyEntryEnd))
     {
      Print("Urutan jam harus: range mulai < range selesai < entry selesai (dalam hari yang sama)");
      return INIT_PARAMETERS_INCORRECT;
     }
   hAtrD1 = iATR(_Symbol, PERIOD_D1, 14);
   if(hAtrD1 == INVALID_HANDLE)
      return INIT_FAILED;
   if(InpUseNews && MQLInfoInteger(MQL_TESTER))
      Print("Catatan: kalender ekonomi tidak tersedia di Strategy Tester, filter berita tidak aktif saat backtest.");
   for(int s = 0; s < 2; s++)
     {
      sessDone[s] = 0;
      sessInfo[s] = "-";
      sessWait[s] = "";
      sessWaitR[s] = R_NODATA;
      for(int r = 0; r < R_COUNT; r++)
         reasonCnt[s][r] = 0;
     }
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippage);
   trade.SetTypeFillingBySymbol(_Symbol);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   PrintStats();
   if(hAtrD1 != INVALID_HANDLE)
      IndicatorRelease(hAtrD1);
   Comment("");
  }

//+------------------------------------------------------------------+
//| Order & posisi                                                   |
//+------------------------------------------------------------------+
int CountPositions(const string tag)
  {
   int c = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(PositionGetTicket(i) > 0 && OurSymbolMagicPos() &&
         (tag == "" || TagFromComment(PositionGetString(POSITION_COMMENT)) == tag))
         c++;
   return c;
  }

int CountPending(const string tag)
  {
   int c = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
      if(OrderGetTicket(i) > 0 && OurSymbolMagicOrd() &&
         (tag == "" || TagFromComment(OrderGetString(ORDER_COMMENT)) == tag))
         c++;
   return c;
  }

void CancelPending(const string tag)
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong tk = OrderGetTicket(i);
      if(tk > 0 && OurSymbolMagicOrd() &&
         (tag == "" || TagFromComment(OrderGetString(ORDER_COMMENT)) == tag))
         trade.OrderDelete(tk);
     }
  }

double NormalizeLots(double lots)
  {
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(step <= 0)
      step = vmin;
   lots = MathFloor(lots / step + 1e-9) * step;
   return MathMin(MathMax(lots, 0.0), vmax);
  }

double CalcLots(const double slDist)
  {
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tv <= 0)
      tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(tv <= 0 || ts <= 0 || slDist <= 0)
      return 0;
   double lossPerLot = slDist / ts * tv + MathMax(InpCommissionLot, 0.0);
   double lots = NormalizeLots(AccountInfoDouble(ACCOUNT_EQUITY) * InpRiskPct / 100.0 / lossPerLot);
   if(lots < vmin)
     {
      if(!InpForceMinLot)
        {
         PrintFormat("Lot minimum %.2f melebihi risiko %.1f%% (SL=%.2f). Order dilewati.", vmin, InpRiskPct, slDist);
         return 0;
        }
      lots = vmin;
     }
   return lots;
  }

double MinDist()
  {
   long sl = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long fr = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   return (MathMax(sl, fr) + 2) * _Point;
  }

bool PlaceStop(const bool buy, double price, double slDist, const double rr, const string tag)
  {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double md  = MinDist();
   if(buy ? price < ask + md : price > bid - md)
     {
      PrintFormat("%s %s dilewati: harga sudah melewati level %.2f", tag, buy ? "Buy Stop" : "Sell Stop", price);
      return false;
     }
   slDist = MathMax(slDist, md);
   price  = NormalizeDouble(price, _Digits);
   double sl = NormalizeDouble(buy ? price - slDist : price + slDist, _Digits);
   double tp = NormalizeDouble(buy ? price + rr * slDist : price - rr * slDist, _Digits);
   double lots = CalcLots(slDist);
   if(lots <= 0)
      return false;

   double margin = 0;
   if(OrderCalcMargin(buy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, _Symbol, lots, price, margin) &&
      margin > AccountInfoDouble(ACCOUNT_MARGIN_FREE) * 0.9)
     {
      Print("Margin tidak cukup, order dilewati.");
      return false;
     }
   string cmt = "ORB|" + tag;
   bool ok = buy ? trade.BuyStop(lots, price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, cmt)
                 : trade.SellStop(lots, price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, cmt);
   if(!ok)
      PrintFormat("%s gagal: %d %s", cmt, trade.ResultRetcode(), trade.ResultRetcodeDescription());
   return ok;
  }

//+------------------------------------------------------------------+
//| Filter berita                                                    |
//+------------------------------------------------------------------+
bool NewsBlocked(string &name)
  {
   name = "";
   if(!InpUseNews || MQLInfoInteger(MQL_TESTER))
      return false;
   datetime now = TimeTradeServer();
   string cur[];
   int nc = StringSplit(InpNewsCurrencies, ',', cur);
   for(int c = 0; c < nc; c++)
     {
      StringTrimLeft(cur[c]);
      StringTrimRight(cur[c]);
      if(cur[c] == "")
         continue;
      MqlCalendarValue v[];
      int nv = CalendarValueHistory(v, now - InpNewsAfterMin * 60, now + InpNewsBeforeMin * 60, NULL, cur[c]);
      for(int i = 0; i < nv; i++)
        {
         MqlCalendarEvent ev;
         if(CalendarEventById(v[i].event_id, ev) && ev.importance == CALENDAR_IMPORTANCE_HIGH)
           {
            name = cur[c] + " " + ev.name;
            return true;
           }
        }
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Logika sesi                                                      |
//+------------------------------------------------------------------+
//--- kembalikan true bila sesi selesai diproses hari ini (order dipasang atau range tidak layak)
bool SetupSession(const int s, const datetime rs, const datetime re)
  {
   string tag = SESS_TAGS[s];
   double hi[], lo[];
   int need = (int)((re - rs) / 60);
   int nh = CopyHigh(_Symbol, PERIOD_M1, rs, re - 1, hi);
   int nl = CopyLow(_Symbol, PERIOD_M1, rs, re - 1, lo);
   if(nh <= 0 || nl <= 0)
     {
      sessWait[s] = StringFormat("CopyHigh/Low gagal (err %d)", GetLastError());
      sessWaitR[s] = R_NODATA;
      return false;                       // data belum siap, coba lagi bar berikutnya
     }
   if(nh < need / 2)
     {
      Note(s, R_HOLIDAY, StringFormat("data range kurang: %d dari %d bar", nh, need));
      return true;
     }
   double rHigh = hi[ArrayMaximum(hi)];
   double rLow  = lo[ArrayMinimum(lo)];
   double range = rHigh - rLow;

   double atr[1];
   if(CopyBuffer(hAtrD1, 0, 1, 1, atr) != 1 || atr[0] <= 0)
     {
      sessWait[s] = StringFormat("ATR D1 belum tersedia (err %d)", GetLastError());
      sessWaitR[s] = R_NODATA;
      return false;
     }
   double ratio = range / atr[0];
   if(ratio < InpMinRangeD1 || ratio > InpMaxRangeD1)
     {
      Note(s, ratio < InpMinRangeD1 ? R_SMALL : R_BIG,
           StringFormat("range %.2f = %.2f x ATR D1 (%.2f), batas %.2f-%.2f -> dilewati",
                        range, ratio, atr[0], InpMinRangeD1, InpMaxRangeD1));
      return true;
     }

   string news;
   if(NewsBlocked(news))
     {
      Note(s, R_NEWS, "dilewati, berita: " + news);
      return true;
     }
   double spreadPts = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point;
   if(spreadPts > InpMaxSpreadPts)
     {
      sessInfo[s] = StringFormat("menunggu spread turun (%.0f)", spreadPts);
      sessWait[s] = StringFormat("spread %.0f > %d", spreadPts, InpMaxSpreadPts);
      sessWaitR[s] = R_SPREAD;
      return false;                       // coba lagi bar berikutnya sampai jendela entry habis
     }

   double buf = InpBufferPts * _Point;
   double slDist = InpSLFrac * range + buf;
   bool b = PlaceStop(true, rHigh + buf, slDist, InpRR, tag);
   bool sl = PlaceStop(false, rLow - buf, slDist, InpRR, tag);
   Note(s, (b || sl) ? R_PLACED : R_PASSED,
        StringFormat("range %.2f-%.2f (%.2f = %.2f x ATR) | buy stop %s | sell stop %s",
                     rLow, rHigh, range, ratio, b ? "OK" : "-", sl ? "OK" : "-"));
   return true;
  }

void ProcessSessions()
  {
   datetime now = TimeCurrent();
   datetime d0  = DayStart(now);
   bool   use[2]   = {InpUseLondon, InpUseNY};
   string rsS[2]   = {InpLonRangeStart, InpNyRangeStart};
   string reS[2]   = {InpLonRangeEnd, InpNyRangeEnd};
   string eeS[2]   = {InpLonEntryEnd, InpNyEntryEnd};

   for(int s = 0; s < 2; s++)
     {
      if(!use[s])
         continue;
      datetime rs = d0 + ParseHHMM(rsS[s]) * 60;
      datetime re = d0 + ParseHHMM(reS[s]) * 60;
      datetime ee = d0 + ParseHHMM(eeS[s]) * 60;
      if(now >= ee)
        {
         // sesi jatuh tempo hari ini tapi tidak pernah selesai diproses
         if(sessDone[s] != d0)
           {
            Note(s, sessWaitR[s], "tidak terpasang sampai jendela habis: " + sessWait[s]);
            sessDone[s] = d0;
           }
         if(CountPending(SESS_TAGS[s]) > 0)
            CancelPending(SESS_TAGS[s]);
         continue;
        }
      if(now >= re && sessDone[s] != d0)
        {
         sessWait[s] = "belum ada bar baru";
         if(SetupSession(s, rs, re))
            sessDone[s] = d0;
        }
     }
  }

//--- break-even & tutup harian
void ManagePositions()
  {
   datetime now = TimeCurrent();
   datetime d0  = DayStart(now);
   datetime closeAt = d0 + ParseHHMM(InpCloseTime) * 60;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0 || !OurSymbolMagicPos())
         continue;
      datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
      if(now >= closeAt || opened < d0)
        {
         trade.PositionClose(tk);
         continue;
        }
      if(InpBER <= 0)
         continue;
      bool   buy  = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl   = PositionGetDouble(POSITION_SL);
      double tp   = PositionGetDouble(POSITION_TP);
      if(sl == 0 || (buy ? sl >= open : sl <= open))
         continue;                         // SL sudah di entry atau lebih baik
      double risk = MathAbs(open - sl);
      double px   = SymbolInfoDouble(_Symbol, buy ? SYMBOL_BID : SYMBOL_ASK);
      double prof = buy ? px - open : open - px;
      if(prof >= InpBER * risk)
        {
         double be = NormalizeDouble(buy ? open + 5 * _Point : open - 5 * _Point, _Digits);
         if(buy ? px - be >= MinDist() : be - px >= MinDist())
            trade.PositionModify(tk, be, tp);
        }
     }
  }

//+------------------------------------------------------------------+
//| OCO: satu sisi terisi -> hapus sisi lainnya                      |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD || !HistoryDealSelect(trans.deal))
      return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagic ||
      HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol ||
      HistoryDealGetInteger(trans.deal, DEAL_ENTRY) != DEAL_ENTRY_IN)
      return;
   string c = "";
   ulong ord = (ulong)HistoryDealGetInteger(trans.deal, DEAL_ORDER);
   if(ord > 0 && HistoryOrderSelect(ord))
      c = HistoryOrderGetString(ord, ORDER_COMMENT);
   if(c == "")
      c = HistoryDealGetString(trans.deal, DEAL_COMMENT);
   string tag = TagFromComment(c);
   if(tag != "")
      CancelPending(tag);
  }

//+------------------------------------------------------------------+
//| Statistik per sesi (dicetak saat backtest selesai)               |
//+------------------------------------------------------------------+
void PrintStats()
  {
   if(!HistorySelect(0, TimeCurrent() + 86400))
      return;
   long   pid[];
   int    ptag[];
   double pnet[];
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
         ArrayResize(pclosed, np);
         pid[idx] = pos;
         ptag[idx] = -1;
         pnet[idx] = 0;
         pclosed[idx] = false;
        }
      pnet[idx] += HistoryDealGetDouble(tk, DEAL_PROFIT) + HistoryDealGetDouble(tk, DEAL_COMMISSION) +
                   HistoryDealGetDouble(tk, DEAL_SWAP) + HistoryDealGetDouble(tk, DEAL_FEE);
      if(HistoryDealGetInteger(tk, DEAL_ENTRY) == DEAL_ENTRY_IN)
        {
         ulong ord = (ulong)HistoryDealGetInteger(tk, DEAL_ORDER);
         string c = (ord > 0) ? HistoryOrderGetString(ord, ORDER_COMMENT) : "";
         if(c == "")
            c = HistoryDealGetString(tk, DEAL_COMMENT);
         string tag = TagFromComment(c);
         ptag[idx] = (tag == "LO") ? 0 : (tag == "NY") ? 1 : -1;
        }
      else
         pclosed[idx] = true;
     }

   int cnt[2] = {0, 0}, wins[2] = {0, 0};
   double gp[2] = {0, 0}, gl[2] = {0, 0};
   for(int j = 0; j < np; j++)
     {
      int k = ptag[j];
      if(k < 0 || !pclosed[j])
         continue;
      cnt[k]++;
      if(pnet[j] > 0)
        {
         wins[k]++;
         gp[k] += pnet[j];
        }
      else
         gl[k] += -pnet[j];
     }
   Print("===== Keputusan per sesi (berapa hari) =====");
   for(int k = 0; k < 2; k++)
      for(int r = 0; r < R_COUNT; r++)
         if(reasonCnt[k][r] > 0)
            PrintFormat("%s  %-38s %4d", SESS_TAGS[k], REASON_NAMES[r], reasonCnt[k][r]);
   Print("===== Statistik ORB per sesi (", _Symbol, ", magic ", InpMagic, ") =====");
   Print("Sesi  Trades  Win%    Net        PF");
   for(int k = 0; k < 2; k++)
     {
      double wr = cnt[k] > 0 ? 100.0 * wins[k] / cnt[k] : 0;
      string pf = gl[k] > 0 ? DoubleToString(gp[k] / gl[k], 2) : (gp[k] > 0 ? "inf" : "-");
      PrintFormat("%-4s  %6d  %5.1f  %9.2f  %6s", SESS_TAGS[k], cnt[k], wr, gp[k] - gl[k], pf);
     }
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   ManagePositions();

   // cadangan OCO bila komentar tidak terbaca di OnTradeTransaction
   for(int s = 0; s < 2; s++)
      if(CountPositions(SESS_TAGS[s]) > 0 && CountPending(SESS_TAGS[s]) > 0)
         CancelPending(SESS_TAGS[s]);

   datetime t = iTime(_Symbol, PERIOD_M1, 0);
   if(t == lastBar)
      return;
   lastBar = t;
   ProcessSessions();

   Comment(StringFormat("Session ORB  |  server %s\nLondon: %s\nNew York: %s\nPosisi %d | Pending %d",
                        TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES),
                        InpUseLondon ? sessInfo[0] : "off", InpUseNY ? sessInfo[1] : "off",
                        CountPositions(""), CountPending("")));
  }
//+------------------------------------------------------------------+
