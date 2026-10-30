//+------------------------------------------------------------------+
//| ExportCalendar.mq5  (SCRIPT, simpan di MQL5/Scripts)             |
//| Mengekspor kalender ekonomi MT5 ke CSV di folder MQL5/Files.     |
//| Jalankan di terminal (bukan Strategy Tester); terminal online    |
//| dan Calendar aktif di Tools > Options > Community.               |
//| Kolom: time,currency,importance,event,actual,forecast,previous   |
//| Waktu = waktu server broker (sama dengan data harga).            |
//+------------------------------------------------------------------+
#property copyright "Chatbot repo"
#property version   "1.10"
#property script_show_inputs

input datetime InpFrom       = D'2024.01.01';  // Dari tanggal
input string   InpCurrencies = "USD";          // Mata uang, pisahkan koma
input bool     InpHighOnly   = false;          // Hanya dampak tinggi (false = sedang & tinggi)

string Num(const long v)
  {
   // nilai kalender disimpan x10^6; LONG_MIN berarti kosong
   return v == LONG_MIN ? "" : DoubleToString(v / 1000000.0, 4);
  }

//--- kode negara (mis. "US") yang memakai mata uang ini, dari daftar negara kalender
int CountriesFor(const string currency, string &codes[])
  {
   MqlCalendarCountry cs[];
   int n = CalendarCountries(cs);
   PrintFormat("CalendarCountries: %d negara (err %d)", n, GetLastError());
   ArrayResize(codes, 0);
   for(int i = 0; i < n; i++)
      if(cs[i].currency == currency)
        {
         int k = ArraySize(codes);
         ArrayResize(codes, k + 1);
         codes[k] = cs[i].code;
        }
   return ArraySize(codes);
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
   int total = 0, fetched = 0;
   datetime end = TimeTradeServer() + 86400;

   for(int k = 0; k < nc; k++)
     {
      StringTrimLeft(cur[k]);
      StringTrimRight(cur[k]);
      string codes[];
      CountriesFor(cur[k], codes);
      // coba per negara (paling andal), lalu fallback per mata uang
      int tries = ArraySize(codes) + 1;
      for(int q = 0; q < tries; q++)
        {
         string country = NULL, currency = NULL;
         if(q < ArraySize(codes))
            country = codes[q];
         else
            currency = cur[k];
         int gotThis = 0;
         for(datetime from = InpFrom; from < end; from += 30 * 86400)
           {
            datetime to = MathMin(from + 30 * 86400, end);
            MqlCalendarValue v[];
            ResetLastError();
            int n = CalendarValueHistory(v, from, to, country, currency);
            if(n < 0)
              {
               PrintFormat("CalendarValueHistory negara=%s mata_uang=%s %s: gagal (err %d)", country,
                           currency, TimeToString(from, TIME_DATE), GetLastError());
               continue;
              }
            gotThis += n;
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
         string via = "mata uang";
         if(country != NULL)
            via = "negara " + country;
         PrintFormat("%s via %s: %d nilai kalender diterima", cur[k], via, gotThis);
         fetched += gotThis;
         if(gotThis > 0)
            break;   // sudah dapat data, tidak perlu cara lain
        }
     }
   FileClose(h);
   PrintFormat("Selesai: %d berita (dari %d nilai) -> MQL5\\Files\\%s", total, fetched, name);
   MessageBox(StringFormat("Selesai: %d berita disimpan ke\nMQL5\\Files\\%s\n\nBila 0: buka tab Experts dan kirim screenshot pesannya.",
                           total, name), "ExportCalendar");
  }
