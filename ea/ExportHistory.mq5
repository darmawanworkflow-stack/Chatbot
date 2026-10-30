//+------------------------------------------------------------------+
//| ExportHistory.mq5  (SCRIPT, simpan di MQL5/Scripts)              |
//| Mengekspor bar historis simbol chart ke CSV di folder MQL5/Files |
//| untuk dianalisis di luar MT5.                                    |
//| Kolom: time,open,high,low,close,tick_volume,spread               |
//+------------------------------------------------------------------+
#property copyright "Chatbot repo"
#property version   "1.00"
#property script_show_inputs

input ENUM_TIMEFRAMES InpTF   = PERIOD_M5;          // Timeframe
input datetime        InpFrom = D'2024.01.01';      // Dari tanggal
input datetime        InpTo   = D'2030.01.01';      // Sampai tanggal (otomatis dibatasi data yang ada)

void OnStart()
  {
   MqlRates r[];
   ArraySetAsSeries(r, false);
   int n = CopyRates(_Symbol, InpTF, InpFrom, InpTo, r);
   if(n <= 0)
     {
      PrintFormat("Gagal mengambil data (err %d). Scroll chart ke kiri / buka chart %s dulu agar MT5 mengunduh history.",
                  GetLastError(), EnumToString(InpTF));
      return;
     }
   string d1 = TimeToString(r[0].time, TIME_DATE), d2 = TimeToString(r[n - 1].time, TIME_DATE);
   StringReplace(d1, ".", "");
   StringReplace(d2, ".", "");
   string name = StringFormat("%s_%s_%s_%s.csv", _Symbol, StringSubstr(EnumToString(InpTF), 7), d1, d2);
   int h = FileOpen(name, FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
   if(h == INVALID_HANDLE)
     {
      PrintFormat("Gagal membuat file %s (err %d)", name, GetLastError());
      return;
     }
   FileWrite(h, "time", "open", "high", "low", "close", "tick_volume", "spread");
   for(int i = 0; i < n; i++)
      FileWrite(h, TimeToString(r[i].time, TIME_DATE | TIME_MINUTES),
                DoubleToString(r[i].open, _Digits), DoubleToString(r[i].high, _Digits),
                DoubleToString(r[i].low, _Digits), DoubleToString(r[i].close, _Digits),
                (string)r[i].tick_volume, (string)r[i].spread);
   FileClose(h);
   PrintFormat("Selesai: %d bar %s dari %s sampai %s -> MQL5\\Files\\%s", n, _Symbol,
               TimeToString(r[0].time, TIME_DATE), TimeToString(r[n - 1].time, TIME_DATE), name);
   MessageBox(StringFormat("Selesai: %d bar disimpan ke\nMQL5\\Files\\%s", n, name), "ExportHistory");
  }
