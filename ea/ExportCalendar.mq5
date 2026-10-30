//+------------------------------------------------------------------+
//| ExportCalendar.mq5  (SCRIPT, simpan di MQL5/Scripts)             |
//| Mengekspor kalender ekonomi MT5 ke CSV di folder MQL5/Files.     |
//| Jalankan di terminal (bukan Strategy Tester); kalender harus     |
//| aktif di Tools > Options > Server.                               |
//| Kolom: time,currency,importance,event,actual,forecast,previous   |
//| Waktu = waktu server broker (sama dengan data harga).            |
//+------------------------------------------------------------------+
#property copyright "Chatbot repo"
#property version   "1.00"
#property script_show_inputs

input datetime InpFrom       = D'2024.01.01';  // Dari tanggal
input string   InpCurrencies = "USD";          // Mata uang, pisahkan koma
input bool     InpHighOnly   = false;          // Hanya dampak tinggi (false = sedang & tinggi)

string Num(const long v)
  {
   // nilai kalender disimpan x10^6; LONG_MIN berarti kosong
   return v == LONG_MIN ? "" : DoubleToString(v / 1000000.0, 4);
  }

void OnStart()
  {
   string cur[];
   int nc = StringSplit(InpCurrencies, ',', cur);
   string name = "calendar_" + InpCurrencies + ".csv";
   StringReplace(name, ",", "_");
   int h = FileOpen(name, FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
   if(h == INVALID_HANDLE)
     {
      PrintFormat("Gagal membuat file (err %d)", GetLastError());
      return;
     }
   FileWrite(h, "time", "currency", "importance", "event", "actual", "forecast", "previous");
   int total = 0;
   for(int k = 0; k < nc; k++)
     {
      StringTrimLeft(cur[k]);
      StringTrimRight(cur[k]);
      MqlCalendarValue v[];
      int n = CalendarValueHistory(v, InpFrom, TimeTradeServer() + 86400, NULL, cur[k]);
      if(n <= 0)
        {
         PrintFormat("%s: tidak ada data kalender (err %d). Pastikan kalender aktif dan terminal online.", cur[k], GetLastError());
         continue;
        }
      for(int i = 0; i < n; i++)
        {
         MqlCalendarEvent ev;
         if(!CalendarEventById(v[i].event_id, ev))
            continue;
         if(ev.importance == CALENDAR_IMPORTANCE_NONE || ev.importance == CALENDAR_IMPORTANCE_LOW)
            continue;
         if(InpHighOnly && ev.importance != CALENDAR_IMPORTANCE_HIGH)
            continue;
         string evname = ev.name;
         StringReplace(evname, ",", " ");
         FileWrite(h, TimeToString(v[i].time, TIME_DATE | TIME_MINUTES), cur[k],
                   ev.importance == CALENDAR_IMPORTANCE_HIGH ? "high" : "medium", evname,
                   Num(v[i].actual_value), Num(v[i].forecast_value), Num(v[i].prev_value));
         total++;
        }
     }
   FileClose(h);
   PrintFormat("Selesai: %d berita -> MQL5\\Files\\%s", total, name);
   MessageBox(StringFormat("Selesai: %d berita disimpan ke\nMQL5\\Files\\%s", total, name), "ExportCalendar");
  }
