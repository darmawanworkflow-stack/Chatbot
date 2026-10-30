//+------------------------------------------------------------------+
//| NewsPullbackArrows.mq5  (INDIKATOR, simpan di MQL5/Indicators)   |
//| Panah sinyal M5 untuk hipotesis riset "pullback searah tren H1   |
//| di jendela berita USD high-impact" (lihat ea/research).          |
//|                                                                  |
//| Sinyal (pada candle M5 yang sudah tutup):                        |
//|  - jam server 07:00-18:00                                        |
//|  - dalam jendela berita: 30 menit sebelum s/d 60 menit sesudah   |
//|    rilis USD high-impact                                         |
//|  - BUY : tren H1 naik (close H1 > EMA50 H1, EMA50 naik vs 3 bar  |
//|          lalu), EMA20 > EMA50 M5, low menyentuh EMA20, candle    |
//|          tutup di atas EMA20 dan bullish. SELL kebalikannya.     |
//|  - Masuk di open candle berikutnya, SL 1.5 x ATR(14), TP 3R,     |
//|    tutup paksa setelah 48 candle (4 jam).                        |
//|                                                                  |
//| Jadwal berita: file MQL5/Files/calendar_USD.csv (ExportCalendar) |
//| ditambah kalender MT5 langsung untuk berita terbaru/akan datang. |
//|                                                                  |
//| HIPOTESIS, BELUM TERBUKTI. Untuk uji maju di akun demo.          |
//+------------------------------------------------------------------+
#property copyright "Chatbot repo"
#property version   "1.01"
#property description "Panah pullback M5 di jendela berita USD. Hipotesis riset, uji di demo."
#property indicator_chart_window
#property indicator_buffers 4
#property indicator_plots   4
#property indicator_label1  "BUY berita"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrLime
#property indicator_width1  3
#property indicator_label2  "SELL berita"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrRed
#property indicator_width2  3
#property indicator_label3  "BUY tanpa berita"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrDarkGray
#property indicator_width3  1
#property indicator_label4  "SELL tanpa berita"
#property indicator_type4   DRAW_ARROW
#property indicator_color4  clrDarkGray
#property indicator_width4  1

input int    InpBeforeMin   = 30;            // Jendela: menit sebelum berita
input int    InpAfterMin    = 60;            // Jendela: menit sesudah berita
input int    InpFromHour    = 7;             // Jam mulai (server)
input int    InpToHour      = 18;            // Jam selesai (server)
input double InpSLATR       = 1.5;           // SL = x ATR(14)
input double InpRR          = 3.0;           // TP = RR x SL
input int    InpHoldBars    = 48;            // Tutup paksa setelah N candle
input double InpCostUSD     = 0.25;          // Biaya per trade utk statistik (spread+komisi+slip, USD)
input bool   InpShowNonNews = false;         // Tampilkan sinyal di luar berita (abu-abu, pembanding)
input int    InpHistoryBars = 30000;         // Jumlah candle riwayat yang dihitung
input int    InpDrawLevels  = 15;            // Gambar garis SL/TP untuk N sinyal terakhir
input string InpCalendarCsv = "calendar_USD.csv"; // File kalender di MQL5/Files (boleh tidak ada)
input bool   InpAlert       = true;          // Alert popup saat sinyal baru
input bool   InpPush        = true;          // Notifikasi ke HP (MetaQuotes ID di Options > Notifications)

double BuyNews[], SellNews[], BuyOther[], SellOther[];
datetime newsT[];
string   newsName[];
datetime lastAlertBar = 0, lastCalRefresh = 0;
const string PFX = "NPA_";

//+------------------------------------------------------------------+
int OnInit()
  {
   SetIndexBuffer(0, BuyNews, INDICATOR_DATA);
   SetIndexBuffer(1, SellNews, INDICATOR_DATA);
   SetIndexBuffer(2, BuyOther, INDICATOR_DATA);
   SetIndexBuffer(3, SellOther, INDICATOR_DATA);
   PlotIndexSetInteger(0, PLOT_ARROW, 233);
   PlotIndexSetInteger(1, PLOT_ARROW, 234);
   PlotIndexSetInteger(2, PLOT_ARROW, 233);
   PlotIndexSetInteger(3, PLOT_ARROW, 234);
   for(int p = 0; p < 4; p++)
      PlotIndexSetDouble(p, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   if(_Period != PERIOD_M5)
      Print("NewsPullbackArrows dirancang untuk chart M5.");
   LoadNews();
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, PFX);
   Comment("");
  }

//+------------------------------------------------------------------+
//| Jadwal berita                                                    |
//+------------------------------------------------------------------+
void AddNews(const datetime t, const string name)
  {
   int n = ArraySize(newsT);
   for(int i = n - 1; i >= 0 && i >= n - 50; i--)
      if(newsT[i] == t)
         return;
   ArrayResize(newsT, n + 1);
   ArrayResize(newsName, n + 1);
   newsT[n] = t;
   newsName[n] = name;
  }

void SortNews()
  {
   int n = ArraySize(newsT);
   for(int i = 1; i < n; i++)
     {
      datetime t = newsT[i];
      string s = newsName[i];
      int j = i - 1;
      while(j >= 0 && newsT[j] > t)
        {
         newsT[j + 1] = newsT[j];
         newsName[j + 1] = newsName[j];
         j--;
        }
      newsT[j + 1] = t;
      newsName[j + 1] = s;
     }
  }

void LoadNews()
  {
   ArrayResize(newsT, 0);
   ArrayResize(newsName, 0);
   int fromCsv = 0, fromCal = 0;
   int h = FileOpen(InpCalendarCsv, FILE_READ | FILE_CSV | FILE_ANSI, ',');
   if(h != INVALID_HANDLE)
     {
      for(int k = 0; k < 7 && !FileIsEnding(h); k++)
         FileReadString(h);                      // header
      while(!FileIsEnding(h))
        {
         string ts = FileReadString(h);
         string cur = FileReadString(h);
         string imp = FileReadString(h);
         string ev = FileReadString(h);
         FileReadString(h);
         FileReadString(h);
         FileReadString(h);
         if(imp == "high" && ts != "")
           {
            AddNews(StringToTime(ts), ev);
            fromCsv++;
           }
        }
      FileClose(h);
     }
   // kalender MT5 langsung (tidak tersedia di Strategy Tester)
   if(!MQLInfoInteger(MQL_TESTER))
     {
      MqlCalendarValue v[];
      int n = CalendarValueHistory(v, TimeTradeServer() - 60 * 86400, TimeTradeServer() + 14 * 86400, "US", NULL);
      for(int i = 0; i < n; i++)
        {
         MqlCalendarEvent ev;
         if(CalendarEventById(v[i].event_id, ev) && ev.importance == CALENDAR_IMPORTANCE_HIGH)
           {
            AddNews(v[i].time, ev.name);
            fromCal++;
           }
        }
     }
   SortNews();
   lastCalRefresh = TimeCurrent();
   PrintFormat("NewsPullbackArrows: %d berita high dari CSV, %d dari kalender MT5, total %d jadwal",
               fromCsv, fromCal, ArraySize(newsT));
  }

//--- indeks berita pertama dengan waktu >= t (pencarian biner)
int NewsLowerBound(const datetime t)
  {
   int lo = 0, hi = ArraySize(newsT);
   while(lo < hi)
     {
      int mid = (lo + hi) / 2;
      if(newsT[mid] < t)
         lo = mid + 1;
      else
         hi = mid;
     }
   return lo;
  }

//--- t di dalam jendela berita? (sama dengan riset: next-t <= before, atau t-prev <= after)
bool InNewsWindow(const datetime t, string &name)
  {
   int k = NewsLowerBound(t);
   if(k < ArraySize(newsT) && newsT[k] - t <= InpBeforeMin * 60)
     {
      name = newsName[k];
      return true;
     }
   if(k > 0 && t - newsT[k - 1] <= InpAfterMin * 60)
     {
      name = newsName[k - 1];
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Tren H1 (bar H1 terakhir yang sudah tutup sebelum candle M5 ini) |
//+------------------------------------------------------------------+
MqlRates h1[];
double   h1ema[];

void BuildH1()
  {
   int n = CopyRates(_Symbol, PERIOD_H1, 0, 20000, h1);   // urutan lama -> baru
   ArrayResize(h1ema, MathMax(n, 0));
   double a = 2.0 / 51.0;
   for(int i = 0; i < n; i++)
      h1ema[i] = (i == 0) ? h1[i].close : a * h1[i].close + (1 - a) * h1ema[i - 1];
  }

int H1Bias(const datetime t)
  {
   // bar H1 yang sudah tutup: waktu buka + 1 jam <= t
   int lo = 0, hi = ArraySize(h1);
   while(lo < hi)
     {
      int mid = (lo + hi) / 2;
      if(h1[mid].time + 3600 <= t)
         lo = mid + 1;
      else
         hi = mid;
     }
   int k = lo - 1;
   if(k < 3)
      return 0;
   if(h1[k].close > h1ema[k] && h1ema[k] > h1ema[k - 3])
      return 1;
   if(h1[k].close < h1ema[k] && h1ema[k] < h1ema[k - 3])
      return -1;
   return 0;
  }

//+------------------------------------------------------------------+
void DrawLevels(const int idx, const datetime t0, const datetime t1, const double entry, const double sl, const double tp, const bool buy)
  {
   string base = PFX + IntegerToString(idx);
   ObjectCreate(0, base + "_sl", OBJ_TREND, 0, t0, sl, t1, sl);
   ObjectSetInteger(0, base + "_sl", OBJPROP_COLOR, clrTomato);
   ObjectSetInteger(0, base + "_sl", OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, base + "_sl", OBJPROP_RAY_RIGHT, false);
   ObjectCreate(0, base + "_tp", OBJ_TREND, 0, t0, tp, t1, tp);
   ObjectSetInteger(0, base + "_tp", OBJPROP_COLOR, clrDodgerBlue);
   ObjectSetInteger(0, base + "_tp", OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, base + "_tp", OBJPROP_RAY_RIGHT, false);
   ObjectCreate(0, base + "_en", OBJ_TREND, 0, t0, entry, t1, entry);
   ObjectSetInteger(0, base + "_en", OBJPROP_COLOR, buy ? clrLime : clrRed);
   ObjectSetInteger(0, base + "_en", OBJPROP_RAY_RIGHT, false);
  }

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[],
                const double &open[], const double &high[], const double &low[], const double &close[],
                const long &tick_volume[], const long &volume[], const int &spread[])
  {
   if(_Period != PERIOD_M5)
     {
      // sinyal dan statistik hanya bermakna di M5 (sesuai riset)
      for(int i = MathMax(0, prev_calculated - 1); i < rates_total; i++)
         BuyNews[i] = SellNews[i] = BuyOther[i] = SellOther[i] = EMPTY_VALUE;
      ObjectsDeleteAll(0, PFX);
      Comment("NewsPullbackArrows: GANTI CHART KE M5.\nIndikator ini hanya berlaku di timeframe M5; di timeframe lain tidak menggambar sinyal.");
      return rates_total;
     }
   if(rates_total < 200)
      return 0;
   bool newBar = prev_calculated == 0 || rates_total != prev_calculated;
   if(!newBar)
      return rates_total;                 // sinyal hanya dihitung dari candle yang sudah tutup

   if(TimeCurrent() - lastCalRefresh > 3600)
      LoadNews();
   BuildH1();

   int start = MathMax(1, rates_total - InpHistoryBars);
   for(int i = 0; i < rates_total; i++)
     {
      BuyNews[i] = SellNews[i] = BuyOther[i] = SellOther[i] = EMPTY_VALUE;
     }
   ObjectsDeleteAll(0, PFX);

   // EMA20/50 & ATR(14) Wilder dihitung manual (sama dengan riset)
   static double e20[], e50[], atr[];
   ArrayResize(e20, rates_total);
   ArrayResize(e50, rates_total);
   ArrayResize(atr, rates_total);
   double a20 = 2.0 / 21.0, a50 = 2.0 / 51.0;
   int s0 = MathMax(0, start - 500);
   for(int i = s0; i < rates_total; i++)
     {
      double tr = (i == s0) ? high[i] - low[i]
                  : MathMax(high[i] - low[i], MathMax(MathAbs(high[i] - close[i - 1]), MathAbs(low[i] - close[i - 1])));
      e20[i] = (i == s0) ? close[i] : a20 * close[i] + (1 - a20) * e20[i - 1];
      e50[i] = (i == s0) ? close[i] : a50 * close[i] + (1 - a50) * e50[i - 1];
      atr[i] = (i == s0) ? tr : tr / 14.0 + (1 - 1.0 / 14.0) * atr[i - 1];
     }

   int last = rates_total - 2;            // candle terakhir yang sudah tutup
   int nN = 0, wN = 0, nO = 0, wO = 0;
   double sumN = 0, sumO = 0;
   int busyN = -1, busyO = -1;
   int sigIdx[];
   ArrayResize(sigIdx, 0);
   string lastNews = "";
   int lastSigDir = 0;

   for(int i = start; i <= last; i++)
     {
      MqlDateTime dt;
      TimeToStruct(time[i], dt);
      if(dt.hour < InpFromHour || dt.hour >= InpToHour)
         continue;
      int d = 0;
      if(e20[i] > e50[i] && low[i] <= e20[i] && close[i] > e20[i] && close[i] > open[i])
         d = 1;
      else if(e20[i] < e50[i] && high[i] >= e20[i] && close[i] < e20[i] && close[i] < open[i])
         d = -1;
      if(d == 0 || H1Bias(time[i]) != d)
         continue;
      string nm = "";
      bool inNews = InNewsWindow(time[i], nm);
      if(!inNews && !InpShowNonNews)
         continue;

      double off = atr[i] * 0.5;
      if(inNews)
        {
         if(d > 0)
            BuyNews[i] = low[i] - off;
         else
            SellNews[i] = high[i] + off;
        }
      else
        {
         if(d > 0)
            BuyOther[i] = low[i] - off;
         else
            SellOther[i] = high[i] + off;
        }

      if(inNews)
        {
         int k = ArraySize(sigIdx);
         ArrayResize(sigIdx, k + 1);
         sigIdx[k] = i;
         if(i == last)
           {
            lastNews = nm;
            lastSigDir = d;
           }
        }

      // hasil historis (satu posisi pada satu waktu, SL dicek lebih dulu dari TP)
      if(i + 1 > last)
         continue;
      if(inNews ? i <= busyN : i <= busyO)
         continue;
      double e = open[i + 1], risk = InpSLATR * atr[i];
      double sl = e - d * risk, tp = e + d * InpRR * risk;
      int endj = MathMin(i + InpHoldBars, last);
      if(i + InpHoldBars > last)
         continue;                          // belum selesai, tidak dihitung
      double r = 0;
      int exitj = i + InpHoldBars;
      bool done = false;
      for(int j = i + 1; j <= endj; j++)
        {
         if(d > 0 ? low[j] <= sl : high[j] >= sl)
           {
            r = -1;
            exitj = j;
            done = true;
            break;
           }
         if(d > 0 ? high[j] >= tp : low[j] <= tp)
           {
            r = InpRR;
            exitj = j;
            done = true;
            break;
           }
        }
      if(!done)
         r = d * (close[i + InpHoldBars] - e) / risk;
      r -= InpCostUSD / risk;
      if(inNews)
        {
         nN++;
         sumN += r;
         if(r > 0)
            wN++;
         busyN = exitj;
        }
      else
        {
         nO++;
         sumO += r;
         if(r > 0)
            wO++;
         busyO = exitj;
        }
     }

   // garis entry/SL/TP untuk beberapa sinyal berita terakhir
   int ns = ArraySize(sigIdx);
   for(int k = MathMax(0, ns - InpDrawLevels); k < ns; k++)
     {
      int i = sigIdx[k];
      if(i + 1 >= rates_total)
        continue;
      int d = BuyNews[i] != EMPTY_VALUE ? 1 : -1;
      double e = open[i + 1], risk = InpSLATR * atr[i];
      datetime t1 = time[i] + InpHoldBars * PeriodSeconds();
      DrawLevels(k, time[i + 1], t1, e, e - d * risk, e + d * InpRR * risk, d > 0);
     }

   // status jendela berita sekarang / berikutnya
   string nowName = "";
   bool nowIn = InNewsWindow(TimeCurrent(), nowName);
   int nk = NewsLowerBound(TimeCurrent());
   string nextTxt = nk < ArraySize(newsT) ? TimeToString(newsT[nk], TIME_DATE | TIME_MINUTES) + " " + newsName[nk] : "tidak ada di jadwal";
   string txt = "NewsPullbackArrows (HIPOTESIS - uji di demo)\n";
   txt += nowIn ? "JENDELA BERITA AKTIF: " + nowName + "\n" : "Di luar jendela berita - saran: tidak trading\n";
   txt += "Berita high berikutnya: " + nextTxt + "\n";
   txt += StringFormat("Riwayat di chart, saat berita: %d sinyal, win %.0f%%, total %+.1fR, rata-rata %+.3fR\n",
                       nN, nN > 0 ? 100.0 * wN / nN : 0, sumN, nN > 0 ? sumN / nN : 0);
   if(InpShowNonNews)
      txt += StringFormat("Pembanding di luar berita: %d sinyal, win %.0f%%, total %+.1fR, rata-rata %+.3fR\n",
                          nO, nO > 0 ? 100.0 * wO / nO : 0, sumO, nO > 0 ? sumO / nO : 0);
   if(ArraySize(newsT) == 0)
      txt += "PERINGATAN: jadwal berita kosong. Salin calendar_USD.csv ke MQL5/Files atau aktifkan Calendar.\n";
   Comment(txt);

   // alert untuk candle yang baru tutup
   if(prev_calculated > 0 && lastSigDir != 0 && time[last] != lastAlertBar)
     {
      lastAlertBar = time[last];
      double e = close[last], risk = InpSLATR * atr[last];
      string msg = StringFormat("%s M5 %s (berita: %s) | entry ~%.2f SL %.2f TP %.2f", _Symbol,
                                lastSigDir > 0 ? "BUY" : "SELL", lastNews, e,
                                e - lastSigDir * risk, e + lastSigDir * InpRR * risk);
      if(InpAlert)
         Alert(msg);
      if(InpPush)
         SendNotification(msg);
     }
   return rates_total;
  }
//+------------------------------------------------------------------+
