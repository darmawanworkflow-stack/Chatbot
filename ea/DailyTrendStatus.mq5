//+------------------------------------------------------------------+
//| DailyTrendStatus.mq5  (INDIKATOR, simpan di MQL5/Indicators)     |
//| Status tren harian gold untuk investasi jangka panjang: PEGANG / |
//| KELUAR, dari tiga aturan yang bertahan di uji 2005-2025          |
//| (ea/research/daily_long.py, data Kaggle + Stooq):                |
//|  1. Harga > SMA 10 bulan (210 hari)      [Faber]                 |
//|  2. EMA20 > EMA50 dan harga > EMA50      [paling kecil drawdown] |
//|  3. Harga > harga 12 bulan lalu          [momentum 12 bulan]     |
//| Semua dihitung dari candle HARIAN yang sudah tutup, jadi status  |
//| tidak berubah-ubah di tengah hari. Cukup dicek seminggu sekali.  |
//| Porsi saran = target volatilitas 15%/tahun dibagi volatilitas 20 |
//| hari, maksimal 100% (tanpa leverage).                            |
//| Hanya posisi BELI: sisi jual merugi di gold 2005-2025.           |
//+------------------------------------------------------------------+
#property copyright "Chatbot repo"
#property version   "1.00"
#property description "Status tren harian gold (PEGANG/KELUAR) dari SMA 10 bulan, EMA 20/50 harian, momentum 12 bulan."
#property indicator_chart_window
#property indicator_buffers 3
#property indicator_plots   3
#property indicator_label1  "SMA 210 hari"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrGold
#property indicator_width1  2
#property indicator_label2  "EMA 20 harian"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrDeepSkyBlue
#property indicator_label3  "EMA 50 harian"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrOrange

input double InpTargetVol = 15.0;            // Target volatilitas tahunan (%) untuk porsi saran
input bool   InpAlert     = true;            // Alert saat status berubah
input bool   InpPush      = true;            // Notifikasi HP saat status berubah

double SmaBuf[], E20Buf[], E50Buf[];
const string PFX = "DTS_";
int lastAgree = -1;
datetime lastBarD1 = 0;

int OnInit()
  {
   SetIndexBuffer(0, SmaBuf, INDICATOR_DATA);
   SetIndexBuffer(1, E20Buf, INDICATOR_DATA);
   SetIndexBuffer(2, E50Buf, INDICATOR_DATA);
   for(int p = 0; p < 3; p++)
      PlotIndexSetDouble(p, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, PFX);
  }

//--- panel di pojok kanan bawah (sudut lain dipakai indikator/EA lain)
void Panel(string &lines[], const int n, const color head)
  {
   ObjectsDeleteAll(0, PFX + "L");
   for(int i = 0; i < n; i++)
     {
      string id = PFX + "L" + IntegerToString(i);
      ObjectCreate(0, id, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, id, OBJPROP_CORNER, CORNER_RIGHT_LOWER);
      ObjectSetInteger(0, id, OBJPROP_ANCHOR, ANCHOR_RIGHT_LOWER);
      ObjectSetInteger(0, id, OBJPROP_XDISTANCE, 8);
      ObjectSetInteger(0, id, OBJPROP_YDISTANCE, 10 + (n - 1 - i) * 14);
      ObjectSetString(0, id, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, id, OBJPROP_FONTSIZE, i == 1 ? 11 : 8);
      ObjectSetInteger(0, id, OBJPROP_COLOR, i <= 1 ? head : clrWhiteSmoke);
      ObjectSetInteger(0, id, OBJPROP_SELECTABLE, false);
      ObjectSetString(0, id, OBJPROP_TEXT, StringSubstr(lines[i], 0, 62));
     }
  }

//--- tanggal terakhir status berubah (indeks bar lama->baru), atau 0
datetime LastChange(const int &st[], const MqlRates &r[], const int n)
  {
   for(int i = n - 1; i > 0; i--)
      if(st[i] != st[i - 1])
         return r[i].time;
   return 0;
  }

int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[],
                const double &open[], const double &high[], const double &low[], const double &close[],
                const long &tick_volume[], const long &volume[], const int &spread[])
  {
   datetime d1 = iTime(_Symbol, PERIOD_D1, 0);
   if(prev_calculated > 0 && d1 == lastBarD1)
      return rates_total;                     // hitung ulang hanya saat candle harian baru

   MqlRates r[];
   int n = CopyRates(_Symbol, PERIOD_D1, 1, 1500, r);   // hanya candle harian yang sudah tutup, lama -> baru
   if(n < 300)
     {
      string w[2] = {"DailyTrendStatus", "Data harian kurang (butuh >= 300 hari)"};
      Panel(w, 2, clrSilver);
      return 0;
     }
   lastBarD1 = d1;

   double sma[], e20[], e50[];
   int st1[], st2[], st3[];
   ArrayResize(sma, n); ArrayResize(e20, n); ArrayResize(e50, n);
   ArrayResize(st1, n); ArrayResize(st2, n); ArrayResize(st3, n);
   double a20 = 2.0 / 21.0, a50 = 2.0 / 51.0, sum = 0;
   for(int i = 0; i < n; i++)
     {
      double c = r[i].close;
      e20[i] = i == 0 ? c : a20 * c + (1 - a20) * e20[i - 1];
      e50[i] = i == 0 ? c : a50 * c + (1 - a50) * e50[i - 1];
      sum += c;
      if(i >= 210)
         sum -= r[i - 210].close;
      sma[i] = i >= 209 ? sum / 210.0 : EMPTY_VALUE;
      st1[i] = (sma[i] != EMPTY_VALUE && c > sma[i]) ? 1 : 0;
      st2[i] = (c > e50[i] && e20[i] > e50[i]) ? 1 : 0;
      st3[i] = (i >= 252 && c > r[i - 252].close) ? 1 : 0;
     }
   int k = n - 1;
   double c = r[k].close;
   int agree = st1[k] + st2[k] + st3[k];

   // volatilitas 20 hari & porsi saran
   double mean = 0, var = 0, rets[20];
   for(int j = 0; j < 20; j++)
     {
      rets[j] = r[k - j].close / r[k - j - 1].close - 1;
      mean += rets[j] / 20.0;
     }
   for(int j = 0; j < 20; j++)
      var += (rets[j] - mean) * (rets[j] - mean) / 19.0;
   double vol = MathSqrt(var) * MathSqrt(252.0) * 100;
   double weight = vol > 0 ? MathMin(1.0, InpTargetVol / vol) : 0;

   // garis di chart D1 saja (di timeframe lain hanya panel)
   ArrayInitialize(SmaBuf, EMPTY_VALUE);
   ArrayInitialize(E20Buf, EMPTY_VALUE);
   ArrayInitialize(E50Buf, EMPTY_VALUE);
   if(_Period == PERIOD_D1)
     {
      for(int i = 0; i < n; i++)
        {
         int b = iBarShift(_Symbol, PERIOD_D1, r[i].time, true);
         if(b < 0)
            continue;
         int idx = rates_total - 1 - b;
         if(idx < 0 || idx >= rates_total)
            continue;
         SmaBuf[idx] = sma[i];
         E20Buf[idx] = e20[i];
         E50Buf[idx] = e50[i];
        }
     }

   string status = agree >= 2 ? "PEGANG" : (agree == 1 ? "HATI-HATI (1 dari 3)" : "KELUAR");
   color col = agree >= 2 ? clrLimeGreen : (agree == 1 ? clrGold : clrTomato);
   string L[12];
   L[0]  = StringFormat("Status tren harian %s (close %s)", _Symbol, TimeToString(r[k].time, TIME_DATE));
   L[1]  = StringFormat("%s  - %d/3 aturan setuju", status, agree);
   L[2]  = StringFormat("1 SMA 10 bln  %s  close %.2f vs %.2f (%+.1f%%)", st1[k] ? "PEGANG" : "KELUAR",
                        c, sma[k], 100 * (c / sma[k] - 1));
   L[3]  = StringFormat("  berubah terakhir: %s", TimeToString(LastChange(st1, r, n), TIME_DATE));
   L[4]  = StringFormat("2 EMA 20/50   %s  EMA20 %.2f EMA50 %.2f", st2[k] ? "PEGANG" : "KELUAR", e20[k], e50[k]);
   L[5]  = StringFormat("  berubah terakhir: %s", TimeToString(LastChange(st2, r, n), TIME_DATE));
   L[6]  = StringFormat("3 Mom 12 bln  %s  close %.2f vs %.2f", st3[k] ? "PEGANG" : "KELUAR", c, r[k - 252].close);
   L[7]  = StringFormat("  berubah terakhir: %s", TimeToString(LastChange(st3, r, n), TIME_DATE));
   L[8]  = StringFormat("Volatilitas 20 hari %.0f%%/thn -> porsi saran %.0f%%", vol, 100 * weight * (agree >= 2 ? 1 : 0));
   L[9]  = "Uji 2005-25 tanpa leverage: beli&tahan 11.5%/thn DD -45%";
   L[10] = "Aturan ini (>=2/3 + porsi saran): 8.7%/thn, DD -27%";
   L[11] = "Hanya BELI. Cocok utk emas fisik/ETF; CFD kena swap.";
   Panel(L, 12, col);

   if(lastAgree >= 0 && ((lastAgree >= 2) != (agree >= 2)))
     {
      string msg = StringFormat("%s status tren harian berubah: %s (%d/3 aturan)", _Symbol, status, agree);
      if(InpAlert)
         Alert(msg);
      if(InpPush)
         SendNotification(msg);
     }
   lastAgree = agree;
   return rates_total;
  }
//+------------------------------------------------------------------+
