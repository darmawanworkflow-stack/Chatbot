//+------------------------------------------------------------------+
//| TechnicalMap.mq5  (INDIKATOR, simpan di MQL5/Indicators)         |
//| Alat bantu baca chart M5:                                        |
//|  - Support & Resistance: swing H1/H4, high/low kemarin, pivot    |
//|    harian, high/low sesi Asia, angka bulat; level berdekatan     |
//|    digabung dan diberi kekuatan (bintang).                       |
//|  - Panel tren M5/M15/H1/H4 + RSI.                                |
//|  - Label pola candle M5 (engulfing, hammer, shooting star, doji, |
//|    inside bar, morning/evening star).                            |
//|  - Panah konfluensi: pola bullish di support & tren H1 tidak     |
//|    turun (atau kebalikannya di resistance).                      |
//|  - Kesimpulan arah dengan skor dan alasan.                       |
//| Panah historis hanya memakai level yang sudah ada pada waktu     |
//| candle itu (tanpa melihat masa depan).                           |
//| ALAT BANTU BACA, BUKAN SINYAL TERBUKTI: riset 2024-2026 tidak    |
//| menemukan keunggulan teknikal M5 setelah biaya.                  |
//+------------------------------------------------------------------+
#property copyright "Chatbot repo"
#property version   "1.00"
#property description "Peta teknikal M5: support/resistance, tren multi-TF, pola candle, panah konfluensi."
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   2
#property indicator_label1  "Konfluensi BUY"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrDeepSkyBlue
#property indicator_width1  3
#property indicator_label2  "Konfluensi SELL"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrOrange
#property indicator_width2  3

input int    InpSwingBarsH1  = 240;          // Swing H1: lihat N bar ke belakang (240 = 10 hari)
input int    InpSwingBarsH4  = 180;          // Swing H4: lihat N bar ke belakang (180 = 30 hari)
input double InpMergeATR     = 0.35;         // Gabungkan level yang berjarak <= x ATR H1
input double InpTouchATR     = 0.30;         // Candle dianggap "di level" bila <= x ATR H1
input int    InpMaxLevels    = 5;            // Maks level ditampilkan per sisi (support / resistance)
input int    InpPatternBars  = 150;          // Label pola & panah untuk N candle terakhir
input bool   InpLabelPatterns= true;         // Tampilkan nama pola candle
input bool   InpAlert        = false;        // Alert saat panah konfluensi baru
input bool   InpPush         = false;        // Notifikasi HP saat panah konfluensi baru
input color  InpSupColor     = clrMediumSeaGreen; // Warna support
input color  InpResColor     = clrIndianRed;      // Warna resistance

double BuyArr[], SellArr[];
const string PFX = "TMAP_";
int hEma20[4], hEma50[4], hRsi[4], hAtrH1;
ENUM_TIMEFRAMES TFS[4] = {PERIOD_M5, PERIOD_M15, PERIOD_H1, PERIOD_H4};
string TFN[4] = {"M5", "M15", "H1", "H4"};
datetime lastAlert = 0;

// daftar level mentah: harga, waktu mulai berlaku, bobot, kode sumber
double   lvP[];
datetime lvT[];
int      lvW[];
string   lvS[];

//+------------------------------------------------------------------+
int OnInit()
  {
   SetIndexBuffer(0, BuyArr, INDICATOR_DATA);
   SetIndexBuffer(1, SellArr, INDICATOR_DATA);
   PlotIndexSetInteger(0, PLOT_ARROW, 233);
   PlotIndexSetInteger(1, PLOT_ARROW, 234);
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   for(int k = 0; k < 4; k++)
     {
      hEma20[k] = iMA(_Symbol, TFS[k], 20, 0, MODE_EMA, PRICE_CLOSE);
      hEma50[k] = iMA(_Symbol, TFS[k], 50, 0, MODE_EMA, PRICE_CLOSE);
      hRsi[k]   = iRSI(_Symbol, TFS[k], 14, PRICE_CLOSE);
      if(hEma20[k] == INVALID_HANDLE || hEma50[k] == INVALID_HANDLE || hRsi[k] == INVALID_HANDLE)
         return INIT_FAILED;
     }
   hAtrH1 = iATR(_Symbol, PERIOD_H1, 14);
   if(hAtrH1 == INVALID_HANDLE)
      return INIT_FAILED;
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, PFX);
   Comment("");
  }

double Buf(const int h, const int shift)
  {
   double a[1];
   if(CopyBuffer(h, 0, shift, 1, a) != 1)
      return 0;
   return a[0];
  }

//+------------------------------------------------------------------+
//| Kumpulan level mentah (dengan waktu mulai diketahui)             |
//+------------------------------------------------------------------+
void AddLevel(const double p, const datetime t, const int w, const string s)
  {
   int n = ArraySize(lvP);
   ArrayResize(lvP, n + 1);
   ArrayResize(lvT, n + 1);
   ArrayResize(lvW, n + 1);
   ArrayResize(lvS, n + 1);
   lvP[n] = p;
   lvT[n] = t;
   lvW[n] = w;
   lvS[n] = s;
  }

//--- swing fraktal 2 kiri / 2 kanan; berlaku sejak bar kanan kedua tutup
void AddSwings(const ENUM_TIMEFRAMES tf, const int bars, const int w, const string code)
  {
   MqlRates r[];
   int n = CopyRates(_Symbol, tf, 1, bars, r);      // lama -> baru, hanya bar tutup
   int sec = PeriodSeconds(tf);
   for(int k = 2; k < n - 2; k++)
     {
      datetime known = r[k + 2].time + sec;
      if(r[k].high >= r[k - 1].high && r[k].high >= r[k - 2].high && r[k].high > r[k + 1].high && r[k].high > r[k + 2].high)
         AddLevel(r[k].high, known, w, code + "H");
      if(r[k].low <= r[k - 1].low && r[k].low <= r[k - 2].low && r[k].low < r[k + 1].low && r[k].low < r[k + 2].low)
         AddLevel(r[k].low, known, w, code + "L");
     }
  }

//--- high/low kemarin, pivot harian, sesi Asia: per hari, berlaku sejak awal hari / akhir sesi
void AddDailyLevels(const int days)
  {
   MqlRates d[];
   int n = CopyRates(_Symbol, PERIOD_D1, 0, days + 1, d);
   for(int k = 1; k < n; k++)
     {
      datetime t0 = d[k].time;
      double H = d[k - 1].high, L = d[k - 1].low, C = d[k - 1].close;
      double P = (H + L + C) / 3.0;
      AddLevel(H, t0, 2, "PDH");
      AddLevel(L, t0, 2, "PDL");
      AddLevel(P, t0, 1, "P");
      AddLevel(2 * P - L, t0, 1, "R1");
      AddLevel(2 * P - H, t0, 1, "S1");
      // range Asia 00:00-07:00 hari itu, berlaku setelah 07:00
      MqlRates a[];
      int na = CopyRates(_Symbol, PERIOD_M5, t0, t0 + 7 * 3600 - 1, a);
      if(na > 30)
        {
         double ah = a[0].high, al = a[0].low;
         for(int i = 1; i < na; i++)
           {
            ah = MathMax(ah, a[i].high);
            al = MathMin(al, a[i].low);
           }
         AddLevel(ah, t0 + 7 * 3600, 1, "AsiaH");
         AddLevel(al, t0 + 7 * 3600, 1, "AsiaL");
        }
     }
  }

void BuildLevels()
  {
   ArrayResize(lvP, 0);
   ArrayResize(lvT, 0);
   ArrayResize(lvW, 0);
   ArrayResize(lvS, 0);
   AddSwings(PERIOD_H1, InpSwingBarsH1 + 60, 1, "H1");
   AddSwings(PERIOD_H4, InpSwingBarsH4 + 30, 2, "H4");
   AddDailyLevels(12);
  }

//--- level yang berlaku pada waktu t (swing dalam jendela lookback, harian hanya hari itu)
bool LevelActive(const int i, const datetime t)
  {
   if(lvT[i] > t)
      return false;
   string s = lvS[i];
   if(StringSubstr(s, 0, 2) == "H1")
      return t - lvT[i] <= (long)InpSwingBarsH1 * 3600;
   if(StringSubstr(s, 0, 2) == "H4")
      return t - lvT[i] <= (long)InpSwingBarsH4 * 4 * 3600;
   return t - lvT[i] < 86400;             // level harian & Asia hanya untuk hari itu
  }

//--- kekuatan & sumber level di sekitar harga p pada waktu t (termasuk angka bulat $50)
int LevelStrengthAt(const double p, const datetime t, const double tol, string &src)
  {
   int s = 0;
   src = "";
   for(int i = 0; i < ArraySize(lvP); i++)
      if(LevelActive(i, t) && MathAbs(lvP[i] - p) <= tol)
        {
         s += lvW[i];
         if(StringFind(src, lvS[i]) < 0)
            src += (src == "" ? "" : ",") + lvS[i];
        }
   double rn = MathRound(p / 50.0) * 50.0;
   if(MathAbs(rn - p) <= tol)
     {
      s += 1;
      src += (src == "" ? "" : ",") + "$" + DoubleToString(rn, 0);
     }
   return s;
  }

//+------------------------------------------------------------------+
//| Gabungkan level aktif sekarang menjadi zona & gambar             |
//+------------------------------------------------------------------+
void DrawCurrentLevels(const double price, const double atrH1, string &supTxt, string &resTxt, double &nearSup, double &nearRes)
  {
   datetime now = TimeCurrent();
   double p[];
   int w[];
   string s[];
   int m = 0;
   for(int i = 0; i < ArraySize(lvP); i++)
      if(LevelActive(i, now))
        {
         ArrayResize(p, m + 1);
         ArrayResize(w, m + 1);
         ArrayResize(s, m + 1);
         p[m] = lvP[i];
         w[m] = lvW[i];
         s[m] = lvS[i];
         m++;
        }
   // angka bulat terdekat
   double base = MathFloor(price / 50.0) * 50.0;
   for(int k = -1; k <= 2; k++)
     {
      ArrayResize(p, m + 1);
      ArrayResize(w, m + 1);
      ArrayResize(s, m + 1);
      p[m] = base + k * 50.0;
      w[m] = 1;
      s[m] = "$" + DoubleToString(base + k * 50.0, 0);
      m++;
     }
   // urutkan harga
   for(int i = 1; i < m; i++)
     {
      double pp = p[i];
      int ww = w[i];
      string ss = s[i];
      int j = i - 1;
      while(j >= 0 && p[j] > pp)
        {
         p[j + 1] = p[j];
         w[j + 1] = w[j];
         s[j + 1] = s[j];
         j--;
        }
      p[j + 1] = pp;
      w[j + 1] = ww;
      s[j + 1] = ss;
     }
   // klaster
   double cp[];
   int cw[];
   string cs[];
   int nc = 0;
   double tol = InpMergeATR * atrH1;
   for(int i = 0; i < m; i++)
     {
      if(nc > 0 && p[i] - cp[nc - 1] <= tol)
        {
         cp[nc - 1] = (cp[nc - 1] * cw[nc - 1] + p[i] * w[i]) / (cw[nc - 1] + w[i]);
         cw[nc - 1] += w[i];
         if(StringFind(cs[nc - 1], s[i]) < 0)
            cs[nc - 1] += "," + s[i];
        }
      else
        {
         ArrayResize(cp, nc + 1);
         ArrayResize(cw, nc + 1);
         ArrayResize(cs, nc + 1);
         cp[nc] = p[i];
         cw[nc] = w[i];
         cs[nc] = s[i];
         nc++;
        }
     }
   // pilih N terdekat di bawah (support) dan di atas (resistance)
   supTxt = "";
   resTxt = "";
   nearSup = 0;
   nearRes = 0;
   int shown = 0;
   for(int i = nc - 1; i >= 0 && shown < InpMaxLevels; i--)
      if(cp[i] < price)
        {
         if(nearSup == 0)
            nearSup = cp[i];
         DrawLevel("S" + IntegerToString(shown), cp[i], cw[i], cs[i], InpSupColor);
         if(shown < 3)
            supTxt += StringFormat("  S%d %.2f %s (%s)\n", shown + 1, cp[i], Stars(cw[i]), cs[i]);
         shown++;
        }
   shown = 0;
   for(int i = 0; i < nc && shown < InpMaxLevels; i++)
      if(cp[i] > price)
        {
         if(nearRes == 0)
            nearRes = cp[i];
         DrawLevel("R" + IntegerToString(shown), cp[i], cw[i], cs[i], InpResColor);
         if(shown < 3)
            resTxt += StringFormat("  R%d %.2f %s (%s)\n", shown + 1, cp[i], Stars(cw[i]), cs[i]);
         shown++;
        }
  }

string Stars(const int w)
  {
   int n = MathMin(5, MathMax(1, w));
   string s = "";
   for(int i = 0; i < n; i++)
      s += "*";
   return s;
  }

void DrawLevel(const string id, const double p, const int w, const string src, const color col)
  {
   string ln = PFX + "L_" + id, tx = PFX + "T_" + id;
   ObjectCreate(0, ln, OBJ_HLINE, 0, 0, p);
   ObjectSetInteger(0, ln, OBJPROP_COLOR, col);
   ObjectSetInteger(0, ln, OBJPROP_WIDTH, w >= 4 ? 2 : 1);
   ObjectSetInteger(0, ln, OBJPROP_STYLE, w >= 3 ? STYLE_SOLID : STYLE_DASH);
   ObjectSetInteger(0, ln, OBJPROP_BACK, true);
   ObjectSetString(0, ln, OBJPROP_TOOLTIP, StringFormat("%.2f %s %s", p, Stars(w), src));
   datetime tt = TimeCurrent() + 6 * PeriodSeconds();
   ObjectCreate(0, tx, OBJ_TEXT, 0, tt, p);
   ObjectSetString(0, tx, OBJPROP_TEXT, StringFormat("%s %.2f %s %s", StringSubstr(id, 0, 1) == "S" ? "Support" : "Resist",
                   p, Stars(w), src));
   ObjectSetInteger(0, tx, OBJPROP_COLOR, col);
   ObjectSetInteger(0, tx, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, tx, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
  }

//+------------------------------------------------------------------+
//| Pola candle (i = candle tutup, data urutan lama -> baru)         |
//+------------------------------------------------------------------+
int Pattern(const int i, const double &o[], const double &h[], const double &l[], const double &c[], string &name)
  {
   double body = MathAbs(c[i] - o[i]), rng = MathMax(h[i] - l[i], _Point);
   double up = h[i] - MathMax(o[i], c[i]), lo = MathMin(o[i], c[i]) - l[i];
   double pb = MathAbs(c[i - 1] - o[i - 1]);
   name = "";
   if(c[i - 1] < o[i - 1] && c[i] > o[i] && c[i] >= o[i - 1] && o[i] <= c[i - 1] && body > pb)
     { name = "Engulf"; return 1; }
   if(c[i - 1] > o[i - 1] && c[i] < o[i] && c[i] <= o[i - 1] && o[i] >= c[i - 1] && body > pb)
     { name = "Engulf"; return -1; }
   // morning / evening star
   double b2 = MathAbs(c[i - 2] - o[i - 2]);
   if(c[i - 2] < o[i - 2] && b2 > 0.6 * (h[i - 2] - l[i - 2]) && MathAbs(c[i - 1] - o[i - 1]) < 0.3 * b2 &&
      c[i] > o[i] && c[i] > (o[i - 2] + c[i - 2]) / 2)
     { name = "MorningStar"; return 1; }
   if(c[i - 2] > o[i - 2] && b2 > 0.6 * (h[i - 2] - l[i - 2]) && MathAbs(c[i - 1] - o[i - 1]) < 0.3 * b2 &&
      c[i] < o[i] && c[i] < (o[i - 2] + c[i - 2]) / 2)
     { name = "EveningStar"; return -1; }
   if(lo >= 2 * body && up <= body && c[i] >= l[i] + 0.66 * rng)
     { name = "Hammer"; return 1; }
   if(up >= 2 * body && lo <= body && c[i] <= h[i] - 0.66 * rng)
     { name = "ShootStar"; return -1; }
   if(h[i] < h[i - 1] && l[i] > l[i - 1])
     { name = "Inside"; return 0; }
   if(body <= 0.1 * rng)
     { name = "Doji"; return 0; }
   return 0;
  }

//+------------------------------------------------------------------+
int Trend(const int k)
  {
   double e20 = Buf(hEma20[k], 1), e50 = Buf(hEma50[k], 1);
   double c = iClose(_Symbol, TFS[k], 1);
   if(e20 <= 0 || e50 <= 0)
      return 0;
   if(c > e50 && e20 > e50)
      return 1;
   if(c < e50 && e20 < e50)
      return -1;
   return 0;
  }

//--- tren H1 pada waktu t (bar H1 tutup sebelum t), untuk panah historis
int TrendH1At(const datetime t)
  {
   int sh = iBarShift(_Symbol, PERIOD_H1, t - 1);
   if(sh < 0)
      return 0;
   if(iTime(_Symbol, PERIOD_H1, sh) + 3600 > t)
      sh += 1;                              // bar itu belum tutup pada waktu t -> pakai bar sebelumnya
   double e20 = Buf(hEma20[2], sh), e50 = Buf(hEma50[2], sh);
   double c = iClose(_Symbol, PERIOD_H1, sh);
   if(c > e50 && e20 > e50)
      return 1;
   if(c < e50 && e20 < e50)
      return -1;
   return 0;
  }

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[],
                const double &open[], const double &high[], const double &low[], const double &close[],
                const long &tick_volume[], const long &volume[], const int &spread[])
  {
   if(_Period != PERIOD_M5)
     {
      ObjectsDeleteAll(0, PFX);
      Comment("TechnicalMap: GANTI CHART KE M5.");
      return rates_total;
     }
   if(rates_total < 300)
      return 0;
   if(prev_calculated > 0 && rates_total == prev_calculated)
      return rates_total;                   // hitung ulang hanya saat candle baru

   double atrH1 = Buf(hAtrH1, 1);
   if(atrH1 <= 0)
      return 0;
   ObjectsDeleteAll(0, PFX);
   BuildLevels();

   int last = rates_total - 2;
   int from = MathMax(3, last - InpPatternBars + 1);
   for(int i = MathMax(0, prev_calculated - 1); i < rates_total; i++)
      BuyArr[i] = SellArr[i] = EMPTY_VALUE;
   for(int i = 0; i < from; i++)
      BuyArr[i] = SellArr[i] = EMPTY_VALUE;

   double tol = InpTouchATR * atrH1;
   int lastPat = 0, lastArrow = 0;
   string lastPatName = "", lastArrowSrc = "";
   for(int i = from; i <= last; i++)
     {
      BuyArr[i] = SellArr[i] = EMPTY_VALUE;
      string nm;
      int d = Pattern(i, open, high, low, close, nm);
      if(nm == "")
         continue;
      datetime tclose = time[i] + PeriodSeconds();
      if(InpLabelPatterns)
        {
         string id = PFX + "P_" + IntegerToString((long)time[i]);
         double y = d >= 0 ? low[i] - 0.15 * atrH1 : high[i] + 0.15 * atrH1;
         ObjectCreate(0, id, OBJ_TEXT, 0, time[i], y);
         ObjectSetString(0, id, OBJPROP_TEXT, nm);
         ObjectSetInteger(0, id, OBJPROP_COLOR, d > 0 ? clrLightGreen : (d < 0 ? clrLightPink : clrSilver));
         ObjectSetInteger(0, id, OBJPROP_FONTSIZE, 7);
         ObjectSetInteger(0, id, OBJPROP_ANCHOR, d >= 0 ? ANCHOR_UPPER : ANCHOR_LOWER);
        }
      if(i == last)
        {
         lastPat = d;
         lastPatName = nm;
        }
      if(d == 0)
         continue;
      // konfluensi: pola di level (yang sudah ada pada waktu itu) & tren H1 tidak berlawanan
      string src;
      int str = LevelStrengthAt(d > 0 ? low[i] : high[i], tclose, tol, src);
      if(str < 2 || TrendH1At(tclose) == -d)
         continue;
      if(d > 0)
         BuyArr[i] = low[i] - 0.4 * atrH1;
      else
         SellArr[i] = high[i] + 0.4 * atrH1;
      if(i == last)
        {
         lastArrow = d;
         lastArrowSrc = nm + " @ " + src;
        }
     }

   // level sekarang
   string supTxt, resTxt;
   double nearSup, nearRes;
   double price = close[last];
   DrawCurrentLevels(price, atrH1, supTxt, resTxt, nearSup, nearRes);

   // skor arah
   int score = 0;
   string why = "";
   string trendTxt = "";
   for(int k = 0; k < 4; k++)
     {
      int tr = Trend(k);
      double rsi = Buf(hRsi[k], 1);
      trendTxt += StringFormat("%s %s RSI %.0f   ", TFN[k], tr > 0 ? "NAIK" : (tr < 0 ? "TURUN" : "datar"), rsi);
      if(k >= 1)                            // M15, H1, H4 ikut skor
        {
         score += tr;
         if(tr != 0)
            why += StringFormat("%s %s; ", TFN[k], tr > 0 ? "naik" : "turun");
        }
     }
   if(lastPat != 0)
     {
      score += lastPat;
      why += "pola " + lastPatName + "; ";
     }
   if(nearSup > 0 && price - nearSup <= tol)
     {
      score += 1;
      why += "di support; ";
     }
   if(nearRes > 0 && nearRes - price <= tol)
     {
      score -= 1;
      why += "di resistance; ";
     }
   double rsi5 = Buf(hRsi[0], 1);
   if(rsi5 < 30)
     {
      score += 1;
      why += "RSI M5 jenuh jual; ";
     }
   if(rsi5 > 70)
     {
      score -= 1;
      why += "RSI M5 jenuh beli; ";
     }
   string bias = score >= 2 ? "CONDONG NAIK" : (score <= -2 ? "CONDONG TURUN" : "NETRAL / tunggu");

   string txt = "TechnicalMap M5 - alat bantu baca chart (bukan sinyal terbukti)\n";
   txt += trendTxt + "\n";
   txt += StringFormat("Kesimpulan: %s (skor %+d)  alasan: %s\n", bias, score, why == "" ? "-" : why);
   txt += StringFormat("Candle terakhir: %s\n", lastPatName == "" ? "tanpa pola" : lastPatName);
   txt += "Resistance terdekat:\n" + (resTxt == "" ? "  -\n" : resTxt);
   txt += "Support terdekat:\n" + (supTxt == "" ? "  -\n" : supTxt);
   txt += "Riset 2024-2026: pola & level M5 tidak memberi keunggulan setelah biaya.";
   Comment(txt);

   if(lastArrow != 0 && time[last] != lastAlert && prev_calculated > 0)
     {
      lastAlert = time[last];
      string msg = StringFormat("%s M5 konfluensi %s: %s (kesimpulan %s)", _Symbol, lastArrow > 0 ? "BUY" : "SELL", lastArrowSrc, bias);
      if(InpAlert)
         Alert(msg);
      if(InpPush)
         SendNotification(msg);
     }
   return rates_total;
  }
//+------------------------------------------------------------------+
