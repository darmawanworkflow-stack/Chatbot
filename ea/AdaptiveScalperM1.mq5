//+------------------------------------------------------------------+
//| AdaptiveScalperM1.mq5                                            |
//| EA scalping M1 yang memilih strategi sesuai kondisi pasar:       |
//|   TREND UP/DOWN -> Buy/Sell Limit saat pullback (atau ladder)    |
//|   SIDEWAYS      -> Buy Limit di batas bawah / Sell Limit di atas |
//|   BREAKOUT      -> Buy/Sell Stop searah candle breakout          |
//|   SQUEEZE       -> Buy Stop + Sell Stop (straddle, OCO)          |
//| v2: konfirmasi regime, filter berita, spread-aware SL/TP,        |
//|     jeda setelah loss beruntun, statistik per strategi.          |
//+------------------------------------------------------------------+
#property copyright "Chatbot repo"
#property version   "2.00"
#property description "Adaptive regime scalper (M1). Uji di demo/Strategy Tester dulu."

#include <Trade\Trade.mqh>

enum ENUM_REGIME
  {
   REG_NONE = 0,
   REG_TREND_UP,
   REG_TREND_DOWN,
   REG_SIDEWAYS,
   REG_BREAKOUT_UP,
   REG_BREAKOUT_DOWN,
   REG_SQUEEZE
  };

//--- inputs
input group "=== Umum ==="
input long   InpMagic          = 20260303;   // Magic number
input string InpComment        = "ASM1";     // Prefix komentar order
input double InpRiskPct        = 1.0;        // Risiko per trade (% equity)
input double InpFixedLot       = 0.0;        // Lot tetap (0 = pakai risiko %)
input bool   InpForceMinLot    = false;      // Paksa lot minimum walau risiko > target
input double InpCommissionLot  = 0.0;        // Komisi round-turn per 1 lot (uang akun), ikut dihitung di risiko
input int    InpMaxPositions   = 2;          // Maks posisi terbuka bersamaan (total)
input int    InpMaxPerStrategy = 1;          // Maks posisi terbuka per strategi
input int    InpSlippage       = 20;         // Slippage (points)

input group "=== Deteksi kondisi pasar ==="
input int    InpEmaFast        = 21;         // EMA cepat
input int    InpEmaSlow        = 55;         // EMA lambat
input int    InpSlopeBars      = 3;          // Bar untuk slope EMA cepat
input int    InpAdxPeriod      = 14;         // ADX period
input double InpAdxTrend       = 25.0;       // ADX >= ini = trending
input double InpAdxRange       = 20.0;       // ADX <= ini = sideways
input int    InpBbPeriod       = 20;         // Bollinger period
input double InpBbDev          = 2.0;        // Bollinger deviasi
input int    InpSqueezeLookback= 100;        // Bar rata-rata lebar BB
input double InpSqueezeRatio   = 0.65;       // Lebar BB / rata-rata < ini = squeeze
input int    InpDonchian       = 20;         // Bar Donchian (high/low breakout)
input double InpBreakoutBarATR = 1.5;        // Range candle >= x ATR = breakout bar
input int    InpAtrPeriod      = 14;         // ATR period
input int    InpRsiPeriod      = 14;         // RSI period
input int    InpConfirmBars    = 3;          // Regime baru harus bertahan N bar sebelum dipakai

input group "=== Aktifkan strategi ==="
input bool   InpUseTrend       = true;       // Trend pullback (limit)
input bool   InpUseRange       = true;       // Sideways mean-reversion (limit)
input bool   InpUseBreakout    = true;       // Breakout momentum (stop)
input bool   InpUseSqueeze     = true;       // Squeeze straddle (buy stop + sell stop)

input group "=== Order, SL, TP (kelipatan ATR) ==="
input double InpSLATR          = 1.0;        // Stop loss (x ATR)
input double InpTPATR          = 1.5;        // Take profit (x ATR)
input bool   InpPadSpread      = true;       // Tambah spread ke jarak SL & TP
input double InpPullbackATR    = 0.5;        // Jarak limit dari harga saat trend (x ATR)
input double InpBreakBufferATR = 0.1;        // Buffer di atas/bawah level breakout (x ATR)
input double InpMinRangeATR    = 2.0;        // Lebar range BB minimum utk sideways (x ATR)
input int    InpExpiryBars     = 5;          // Pending order dihapus setelah N bar

input group "=== Ladder stop order (mode ala video, searah tren) ==="
input bool   InpUseLadder      = false;      // Saat trend: sebar Buy/Sell Stop bertingkat, bukan 1 limit
input int    InpLadderLevels   = 3;          // Jumlah tingkat (maks 5)
input double InpLadderStepATR  = 0.5;        // Jarak antar tingkat (x ATR)
// Total risiko ladder = InpRiskPct (dibagi rata). Set InpMaxPositions & InpMaxPerStrategy >= jumlah tingkat.

input group "=== Filter timeframe lebih tinggi ==="
input bool             InpUseHtf    = true;        // Trend/breakout hanya searah bias HTF
input ENUM_TIMEFRAMES  InpHtf       = PERIOD_M15;  // Timeframe filter
input int              InpHtfEma    = 50;          // EMA filter (close di atas EMA = bias naik)

input group "=== Filter berita (kalender ekonomi MT5) ==="
input bool   InpUseNews        = true;       // Aktifkan filter berita (tidak jalan di Strategy Tester)
input string InpNewsCurrencies = "USD";      // Mata uang, pisahkan koma (mis. USD,EUR)
input ENUM_CALENDAR_EVENT_IMPORTANCE InpNewsImportance = CALENDAR_IMPORTANCE_HIGH; // Dampak minimum
input int    InpNewsBeforeMin  = 30;         // Berhenti N menit sebelum berita
input int    InpNewsAfterMin   = 30;         // Lanjut N menit setelah berita
input bool   InpNewsClosePos   = false;      // Tutup posisi terbuka menjelang berita

input group "=== Manajemen posisi ==="
input double InpBEATR          = 0.7;        // Break-even setelah profit x ATR (0 = off)
input int    InpBELockPts      = 5;          // Kunci profit saat break-even (points)
input double InpTrailStartATR  = 1.0;        // Mulai trailing setelah profit x ATR (0 = off)
input double InpTrailATR       = 0.6;        // Jarak trailing (x ATR)
input int    InpMaxHoldBars    = 15;         // Tutup paksa posisi setelah N bar (0 = off)

input group "=== Filter & proteksi ==="
input int    InpMaxSpreadPts   = 40;         // Spread maks (points)
input double InpMaxSpreadPctTP = 30.0;       // Spread maks (% dari jarak TP)
input bool   InpUseSession     = false;      // Batasi jam trading (waktu server)
input int    InpStartHour      = 8;          // Jam mulai
input int    InpEndHour        = 22;         // Jam selesai
input double InpDailyLossPct   = 5.0;        // Stop trading hari ini bila rugi >= % (0 = off)
input int    InpMaxConsecLoss  = 3;          // Loss beruntun sebelum jeda (0 = off)
input int    InpPauseMinutes   = 30;         // Lama jeda (menit)

//--- globals
CTrade      trade;
int         hEmaF = INVALID_HANDLE, hEmaS = INVALID_HANDLE, hAdx = INVALID_HANDLE;
int         hAtr  = INVALID_HANDLE, hBb   = INVALID_HANDLE, hRsi = INVALID_HANDLE;
int         hHtf  = INVALID_HANDLE;
datetime    lastBar = 0;
ENUM_REGIME regime  = REG_NONE;   // regime terkonfirmasi (dipakai untuk order)
ENUM_REGIME gRaw    = REG_NONE;   // regime mentah bar terakhir
ENUM_REGIME candReg = REG_NONE;   // kandidat regime yang sedang dihitung
int         candCount = 0;

double gEmaF, gEmaS, gEmaFPrev, gAdx, gAtr, gRsi;
double gBbU, gBbL, gBbM, gBwRatio, gDonH, gDonL;
double gH1, gL1, gC1;
int    gHtfBias = 0;      // +1 naik, -1 turun, 0 netral/tidak dipakai
double gRiskDiv = 1.0;    // pembagi risiko (ladder)

int      consecLoss = 0;
datetime pauseUntil = 0;
string   newsName   = "";

string STRAT_TAGS[] = {"TU", "TD", "SW", "BU", "BD", "SQ"};

//+------------------------------------------------------------------+
string TagOf(const ENUM_REGIME r)
  {
   switch(r)
     {
      case REG_TREND_UP:      return "TU";
      case REG_TREND_DOWN:    return "TD";
      case REG_SIDEWAYS:      return "SW";
      case REG_BREAKOUT_UP:   return "BU";
      case REG_BREAKOUT_DOWN: return "BD";
      case REG_SQUEEZE:       return "SQ";
     }
   return "XX";
  }

string RegimeName(const ENUM_REGIME r)
  {
   switch(r)
     {
      case REG_TREND_UP:      return "TREND NAIK";
      case REG_TREND_DOWN:    return "TREND TURUN";
      case REG_SIDEWAYS:      return "SIDEWAYS";
      case REG_BREAKOUT_UP:   return "BREAKOUT NAIK";
      case REG_BREAKOUT_DOWN: return "BREAKOUT TURUN";
      case REG_SQUEEZE:       return "SQUEEZE (siap breakout)";
     }
   return "TIDAK JELAS (diam)";
  }

//--- arah regime: +1 naik, -1 turun, 0 netral
int RegimeDir(const ENUM_REGIME r)
  {
   if(r == REG_TREND_UP || r == REG_BREAKOUT_UP)
      return 1;
   if(r == REG_TREND_DOWN || r == REG_BREAKOUT_DOWN)
      return -1;
   return 0;
  }

bool IsBreakout(const ENUM_REGIME r)
  {
   return r == REG_BREAKOUT_UP || r == REG_BREAKOUT_DOWN;
  }

bool IsBuyType(const long type)
  {
   return type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_BUY_STOP || type == ORDER_TYPE_BUY;
  }

string TagFromComment(const string c)
  {
   int p = StringFind(c, "|");
   if(p < 0 || StringLen(c) < p + 3)
      return "";
   return StringSubstr(c, p + 1, 2);
  }

int TagIndex(const string tag)
  {
   for(int i = 0; i < ArraySize(STRAT_TAGS); i++)
      if(STRAT_TAGS[i] == tag)
         return i;
   return -1;
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   hEmaF = iMA(_Symbol, _Period, InpEmaFast, 0, MODE_EMA, PRICE_CLOSE);
   hEmaS = iMA(_Symbol, _Period, InpEmaSlow, 0, MODE_EMA, PRICE_CLOSE);
   hAdx  = iADX(_Symbol, _Period, InpAdxPeriod);
   hAtr  = iATR(_Symbol, _Period, InpAtrPeriod);
   hBb   = iBands(_Symbol, _Period, InpBbPeriod, 0, InpBbDev, PRICE_CLOSE);
   hRsi  = iRSI(_Symbol, _Period, InpRsiPeriod, PRICE_CLOSE);
   if(InpUseHtf)
      hHtf = iMA(_Symbol, InpHtf, InpHtfEma, 0, MODE_EMA, PRICE_CLOSE);
   if(InpUseHtf && hHtf == INVALID_HANDLE)
     {
      Print("Gagal membuat indikator HTF");
      return INIT_FAILED;
     }
   if(hEmaF == INVALID_HANDLE || hEmaS == INVALID_HANDLE || hAdx == INVALID_HANDLE ||
      hAtr == INVALID_HANDLE || hBb == INVALID_HANDLE || hRsi == INVALID_HANDLE)
     {
      Print("Gagal membuat indikator");
      return INIT_FAILED;
     }
   if(InpUseNews && MQLInfoInteger(MQL_TESTER))
      Print("Catatan: kalender ekonomi tidak tersedia di Strategy Tester, filter berita tidak aktif saat backtest.");

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippage);
   trade.SetTypeFillingBySymbol(_Symbol);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   PrintStrategyStats();
   int hs[] = {hEmaF, hEmaS, hAdx, hAtr, hBb, hRsi, hHtf};
   for(int i = 0; i < ArraySize(hs); i++)
      if(hs[i] != INVALID_HANDLE)
         IndicatorRelease(hs[i]);
   Comment("");
  }

//+------------------------------------------------------------------+
bool One(const int h, const int buf, const int shift, double &v)
  {
   double a[1];
   if(CopyBuffer(h, buf, shift, 1, a) != 1)
      return false;
   v = a[0];
   return true;
  }

//--- ambil semua nilai indikator dari bar yang sudah close (shift 1)
bool Refresh()
  {
   if(Bars(_Symbol, _Period) < InpSqueezeLookback + InpDonchian + 10)
      return false;
   if(!One(hEmaF, 0, 1, gEmaF) || !One(hEmaF, 0, 1 + InpSlopeBars, gEmaFPrev) ||
      !One(hEmaS, 0, 1, gEmaS) || !One(hAdx, 0, 1, gAdx) ||
      !One(hAtr, 0, 1, gAtr) || !One(hRsi, 0, 1, gRsi))
      return false;
   if(gAtr <= 0)
      return false;

   int n = InpSqueezeLookback;
   double u[], l[], m[];
   ArraySetAsSeries(u, true);
   ArraySetAsSeries(l, true);
   ArraySetAsSeries(m, true);
   if(CopyBuffer(hBb, 1, 1, n, u) != n || CopyBuffer(hBb, 2, 1, n, l) != n ||
      CopyBuffer(hBb, 0, 1, n, m) != n)
      return false;
   gBbU = u[0];
   gBbL = l[0];
   gBbM = m[0];
   double sum = 0;
   for(int i = 0; i < n; i++)
      if(m[i] > 0)
         sum += (u[i] - l[i]) / m[i];
   double avg = sum / n;
   gBwRatio = (avg > 0 && gBbM > 0) ? ((gBbU - gBbL) / gBbM) / avg : 1.0;

   double hi[], lo[];
   ArraySetAsSeries(hi, true);
   ArraySetAsSeries(lo, true);
   if(CopyHigh(_Symbol, _Period, 2, InpDonchian, hi) != InpDonchian ||
      CopyLow(_Symbol, _Period, 2, InpDonchian, lo) != InpDonchian)
      return false;
   gDonH = hi[ArrayMaximum(hi)];
   gDonL = lo[ArrayMinimum(lo)];

   gH1 = iHigh(_Symbol, _Period, 1);
   gL1 = iLow(_Symbol, _Period, 1);
   gC1 = iClose(_Symbol, _Period, 1);

   gHtfBias = 0;
   if(InpUseHtf)
     {
      double e;
      double c = iClose(_Symbol, InpHtf, 1);
      if(!One(hHtf, 0, 1, e) || c <= 0)
         return false;
      gHtfBias = (c > e) ? 1 : -1;
     }
   return true;
  }

ENUM_REGIME DetectRegime()
  {
   bool bigBar = (gH1 - gL1) >= InpBreakoutBarATR * gAtr;
   if(bigBar && gC1 > gDonH)
      return REG_BREAKOUT_UP;
   if(bigBar && gC1 < gDonL)
      return REG_BREAKOUT_DOWN;
   if(gAdx >= InpAdxTrend)
     {
      if(gEmaF > gEmaS && gEmaF > gEmaFPrev)
         return REG_TREND_UP;
      if(gEmaF < gEmaS && gEmaF < gEmaFPrev)
         return REG_TREND_DOWN;
      return REG_NONE;
     }
   if(gBwRatio < InpSqueezeRatio)
      return REG_SQUEEZE;
   if(gAdx <= InpAdxRange)
      return REG_SIDEWAYS;
   return REG_NONE;
  }

//--- breakout dipakai langsung (kejadian 1 bar); regime lain harus bertahan InpConfirmBars bar
void UpdateRegime()
  {
   gRaw = DetectRegime();
   if(IsBreakout(gRaw))
     {
      regime = gRaw;
      candReg = gRaw;
      candCount = 0;
      return;
     }
   if(gRaw == candReg)
      candCount++;
   else
     {
      candReg = gRaw;
      candCount = 1;
     }
   if(candCount >= MathMax(1, InpConfirmBars))
      regime = gRaw;
   else if(IsBreakout(regime))
      regime = REG_NONE;   // breakout tidak diperpanjang tanpa konfirmasi
  }

//+------------------------------------------------------------------+
//| Hitung order/posisi milik EA                                     |
//+------------------------------------------------------------------+
int CountPositions(const string tag = "")
  {
   int c = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      if(tag != "" && TagFromComment(PositionGetString(POSITION_COMMENT)) != tag)
         continue;
      c++;
     }
   return c;
  }

int CountPending(const string tag, const int type = -1)
  {
   int c = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong tk = OrderGetTicket(i);
      if(tk == 0)
         continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol || OrderGetInteger(ORDER_MAGIC) != InpMagic)
         continue;
      if(tag != "" && TagFromComment(OrderGetString(ORDER_COMMENT)) != tag)
         continue;
      if(type >= 0 && OrderGetInteger(ORDER_TYPE) != type)
         continue;
      c++;
     }
   return c;
  }

void CancelPending(const string tag)
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong tk = OrderGetTicket(i);
      if(tk == 0)
         continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol || OrderGetInteger(ORDER_MAGIC) != InpMagic)
         continue;
      if(tag != "" && TagFromComment(OrderGetString(ORDER_COMMENT)) != tag)
         continue;
      trade.OrderDelete(tk);
     }
  }

void CloseAllPositions()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0 || PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      trade.PositionClose(tk);
     }
  }

//--- hapus pending yang kadaluarsa atau berlawanan arah dengan regime sekarang
void CleanupPending()
  {
   int dir = RegimeDir(regime);
   long maxAge = (long)InpExpiryBars * PeriodSeconds(_Period);
   datetime now = TimeCurrent();
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong tk = OrderGetTicket(i);
      if(tk == 0)
         continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol || OrderGetInteger(ORDER_MAGIC) != InpMagic)
         continue;
      long age = (long)(now - (datetime)OrderGetInteger(ORDER_TIME_SETUP));
      bool buy = IsBuyType(OrderGetInteger(ORDER_TYPE));
      bool against = (dir > 0 && !buy) || (dir < 0 && buy);
      if(age >= maxAge || against)
         trade.OrderDelete(tk);
     }
  }

//+------------------------------------------------------------------+
//| Ukuran lot & penempatan order                                    |
//+------------------------------------------------------------------+
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
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(InpFixedLot > 0)
      return NormalizeLots(MathMax(InpFixedLot, vmin));

   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tv <= 0)
      tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tv <= 0 || ts <= 0 || slDist <= 0)
      return 0;
   double lossPerLot = slDist / ts * tv + MathMax(InpCommissionLot, 0.0);
   double riskMoney  = AccountInfoDouble(ACCOUNT_EQUITY) * InpRiskPct / 100.0 / gRiskDiv;
   double lots = NormalizeLots(riskMoney / lossPerLot);
   if(lots < vmin)
     {
      if(!InpForceMinLot)
        {
         PrintFormat("Lot minimum %.2f melebihi risiko %.2f%% (SL=%.2f). Order dilewati.", vmin, InpRiskPct / gRiskDiv, slDist);
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

bool Place(const ENUM_ORDER_TYPE type, double price, double slDist, double tpDist, const string tag)
  {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double md  = MinDist();
   bool buy = IsBuyType(type);

   switch(type)
     {
      case ORDER_TYPE_BUY_LIMIT:  if(price > ask - md) return false; break;
      case ORDER_TYPE_BUY_STOP:   if(price < ask + md) return false; break;
      case ORDER_TYPE_SELL_LIMIT: if(price < bid + md) return false; break;
      case ORDER_TYPE_SELL_STOP:  if(price > bid - md) return false; break;
      default: return false;
     }

   double spread = ask - bid;
   if(InpMaxSpreadPctTP > 0 && spread > tpDist * InpMaxSpreadPctTP / 100.0)
      return false;

   // SL buy kena oleh Bid (Sell oleh Ask): beri ruang selebar spread agar tidak
   // terkena hanya karena spread melebar; TP juga ditambah agar target bersih tetap.
   if(InpPadSpread)
     {
      slDist += spread;
      tpDist += spread;
     }
   slDist = MathMax(slDist, md);
   tpDist = MathMax(tpDist, md);
   price  = NormalizeDouble(price, _Digits);
   double sl = NormalizeDouble(buy ? price - slDist : price + slDist, _Digits);
   double tp = NormalizeDouble(buy ? price + tpDist : price - tpDist, _Digits);

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

   string cmt = InpComment + "|" + tag;
   bool ok = false;
   switch(type)
     {
      case ORDER_TYPE_BUY_LIMIT:  ok = trade.BuyLimit(lots, price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, cmt);  break;
      case ORDER_TYPE_BUY_STOP:   ok = trade.BuyStop(lots, price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, cmt);   break;
      case ORDER_TYPE_SELL_LIMIT: ok = trade.SellLimit(lots, price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, cmt); break;
      case ORDER_TYPE_SELL_STOP:  ok = trade.SellStop(lots, price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, cmt);  break;
      default: break;
     }
   if(!ok)
      PrintFormat("Order %s gagal: %d %s", EnumToString(type), trade.ResultRetcode(), trade.ResultRetcodeDescription());
   return ok;
  }

//+------------------------------------------------------------------+
//| Strategi per kondisi pasar                                       |
//+------------------------------------------------------------------+
//--- ladder Buy/Sell Stop searah tren; risiko total dibagi rata
void PlaceLadder(const bool buy, const double ref, const double sl, const double tp, const string tag)
  {
   int n = MathMax(1, MathMin(InpLadderLevels, 5));
   n = MathMin(n, InpMaxPositions - CountPositions());
   n = MathMin(n, InpMaxPerStrategy - CountPositions(tag));
   if(n <= 0)
      return;
   gRiskDiv = n;
   for(int k = 1; k <= n; k++)
     {
      double off = k * InpLadderStepATR * gAtr;
      if(buy)
         Place(ORDER_TYPE_BUY_STOP, ref + off, sl, tp, tag);
      else
         Place(ORDER_TYPE_SELL_STOP, ref - off, sl, tp, tag);
     }
   gRiskDiv = 1.0;
  }

void PlaceForRegime()
  {
   if(CountPositions() >= InpMaxPositions)
      return;
   string tag = TagOf(regime);
   if(CountPositions(tag) >= InpMaxPerStrategy)
      return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl  = InpSLATR * gAtr;
   double tp  = InpTPATR * gAtr;
   double buf = InpBreakBufferATR * gAtr;

   switch(regime)
     {
      case REG_TREND_UP:
        {
         if(!InpUseTrend || CountPending(tag) > 0 || (gHtfBias < 0 && InpUseHtf))
            return;
         if(InpUseLadder)
           {
            PlaceLadder(true, ask, sl, tp, tag);
            break;
           }
         double p = ask - InpPullbackATR * gAtr;
         if(p < gEmaS)
            return;
         Place(ORDER_TYPE_BUY_LIMIT, p, sl, tp, tag);
         break;
        }
      case REG_TREND_DOWN:
        {
         if(!InpUseTrend || CountPending(tag) > 0 || (gHtfBias > 0 && InpUseHtf))
            return;
         if(InpUseLadder)
           {
            PlaceLadder(false, bid, sl, tp, tag);
            break;
           }
         double p = bid + InpPullbackATR * gAtr;
         if(p > gEmaS)
            return;
         Place(ORDER_TYPE_SELL_LIMIT, p, sl, tp, tag);
         break;
        }
      case REG_SIDEWAYS:
        {
         if(!InpUseRange || (gBbU - gBbL) < InpMinRangeATR * gAtr)
            return;
         double tpBuy  = MathMax(gBbM - gBbL, 0.5 * gAtr);
         double tpSell = MathMax(gBbU - gBbM, 0.5 * gAtr);
         if(CountPending(tag, ORDER_TYPE_BUY_LIMIT) == 0)
            Place(ORDER_TYPE_BUY_LIMIT, gBbL, sl, tpBuy, tag);
         if(CountPending(tag, ORDER_TYPE_SELL_LIMIT) == 0)
            Place(ORDER_TYPE_SELL_LIMIT, gBbU, sl, tpSell, tag);
         break;
        }
      case REG_BREAKOUT_UP:
        {
         // hanya pada bar breakout itu sendiri, supaya tidak mengejar harga
         if(!InpUseBreakout || gRaw != regime || CountPending(tag) > 0 || (gHtfBias < 0 && InpUseHtf))
            return;
         Place(ORDER_TYPE_BUY_STOP, gH1 + buf, sl, tp, tag);
         break;
        }
      case REG_BREAKOUT_DOWN:
        {
         if(!InpUseBreakout || gRaw != regime || CountPending(tag) > 0 || (gHtfBias > 0 && InpUseHtf))
            return;
         Place(ORDER_TYPE_SELL_STOP, gL1 - buf, sl, tp, tag);
         break;
        }
      case REG_SQUEEZE:
        {
         if(!InpUseSqueeze)
            return;
         if(CountPending(tag, ORDER_TYPE_BUY_STOP) == 0)
            Place(ORDER_TYPE_BUY_STOP, gDonH + buf, sl, tp, tag);
         if(CountPending(tag, ORDER_TYPE_SELL_STOP) == 0)
            Place(ORDER_TYPE_SELL_STOP, gDonL - buf, sl, tp, tag);
         break;
        }
      default:
         break;
     }
  }

//+------------------------------------------------------------------+
//| Filter & proteksi                                                |
//+------------------------------------------------------------------+
double TodayRealized()
  {
   double s = 0;
   if(!HistorySelect(iTime(_Symbol, PERIOD_D1, 0), TimeCurrent() + 60))
      return 0;
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
     {
      ulong tk = HistoryDealGetTicket(i);
      if(tk == 0 || HistoryDealGetInteger(tk, DEAL_MAGIC) != InpMagic ||
         HistoryDealGetString(tk, DEAL_SYMBOL) != _Symbol)
         continue;
      long t = HistoryDealGetInteger(tk, DEAL_TYPE);
      if(t != DEAL_TYPE_BUY && t != DEAL_TYPE_SELL)
         continue;
      s += HistoryDealGetDouble(tk, DEAL_PROFIT) + HistoryDealGetDouble(tk, DEAL_COMMISSION) +
           HistoryDealGetDouble(tk, DEAL_SWAP) + HistoryDealGetDouble(tk, DEAL_FEE);
     }
   return s;
  }

double FloatingPnL()
  {
   double s = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0 || PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      s += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
     }
   return s;
  }

bool DailyLossHit()
  {
   if(InpDailyLossPct <= 0)
      return false;
   double realized = TodayRealized();
   double startBal = AccountInfoDouble(ACCOUNT_BALANCE) - realized;
   if(startBal <= 0)
      return false;
   return (realized + FloatingPnL()) <= -startBal * InpDailyLossPct / 100.0;
  }

//--- true bila ada berita penting dalam jendela [-after, +before] menit dari sekarang
bool NewsBlocked()
  {
   newsName = "";
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
         if(!CalendarEventById(v[i].event_id, ev))
            continue;
         if(ev.importance >= InpNewsImportance)
           {
            newsName = StringFormat("%s %s (%s)", cur[c], ev.name, TimeToString(v[i].time, TIME_MINUTES));
            return true;
           }
        }
     }
   return false;
  }

//--- cancelAll = true bila pending order juga harus dibersihkan
bool CanTrade(string &why, bool &cancelAll)
  {
   cancelAll = false;
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
     { why = "trading tidak diizinkan"; return false; }
   if(TimeCurrent() < pauseUntil)
     {
      why = "jeda setelah loss beruntun s/d " + TimeToString(pauseUntil, TIME_MINUTES);
      cancelAll = true;
      return false;
     }
   if(NewsBlocked())
     {
      why = "berita: " + newsName;
      cancelAll = true;
      if(InpNewsClosePos)
         CloseAllPositions();
      return false;
     }
   if(InpUseSession)
     {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      bool inside = (InpStartHour <= InpEndHour)
                    ? (dt.hour >= InpStartHour && dt.hour < InpEndHour)
                    : (dt.hour >= InpStartHour || dt.hour < InpEndHour);
      if(!inside)
        { why = "di luar jam trading"; cancelAll = true; return false; }
     }
   double spreadPts = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point;
   if(spreadPts > InpMaxSpreadPts)
     { why = StringFormat("spread %.0f > %d", spreadPts, InpMaxSpreadPts); return false; }
   if(DailyLossHit())
     { why = "batas rugi harian tercapai"; cancelAll = true; return false; }
   why = "OK";
   return true;
  }

//+------------------------------------------------------------------+
//| Manajemen posisi: break-even, trailing, batas waktu              |
//+------------------------------------------------------------------+
void ManagePositions()
  {
   if(gAtr <= 0)
      return;
   double md = MinDist();
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0 || PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;

      if(InpMaxHoldBars > 0 &&
         TimeCurrent() - (datetime)PositionGetInteger(POSITION_TIME) >= (long)InpMaxHoldBars * PeriodSeconds(_Period))
        {
         trade.PositionClose(tk);
         continue;
        }

      bool   buy  = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl   = PositionGetDouble(POSITION_SL);
      double tp   = PositionGetDouble(POSITION_TP);
      double px   = SymbolInfoDouble(_Symbol, buy ? SYMBOL_BID : SYMBOL_ASK);
      double prof = buy ? px - open : open - px;

      double cand = sl;
      bool   set  = false;
      if(InpBEATR > 0 && prof >= InpBEATR * gAtr)
        {
         cand = buy ? open + InpBELockPts * _Point : open - InpBELockPts * _Point;
         set = true;
        }
      if(InpTrailStartATR > 0 && InpTrailATR > 0 && prof >= InpTrailStartATR * gAtr)
        {
         double tr = buy ? px - InpTrailATR * gAtr : px + InpTrailATR * gAtr;
         if(!set || (buy ? tr > cand : tr < cand))
            cand = tr;
         set = true;
        }
      if(!set)
         continue;

      cand = NormalizeDouble(cand, _Digits);
      bool better = (sl == 0) || (buy ? cand > sl + _Point : cand < sl - _Point);
      bool valid  = buy ? (px - cand >= md) : (cand - px >= md);
      if(better && valid)
         trade.PositionModify(tk, cand, tp);
     }
  }

//+------------------------------------------------------------------+
//| Event transaksi: OCO squeeze & hitung loss beruntun              |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD || !HistoryDealSelect(trans.deal))
      return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagic ||
      HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol)
      return;

   long entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entry == DEAL_ENTRY_IN)
     {
      // salah satu sisi straddle terisi -> hapus sisi lainnya
      string c = "";
      ulong ord = (ulong)HistoryDealGetInteger(trans.deal, DEAL_ORDER);
      if(ord > 0 && HistoryOrderSelect(ord))
         c = HistoryOrderGetString(ord, ORDER_COMMENT);
      if(c == "")
         c = HistoryDealGetString(trans.deal, DEAL_COMMENT);
      if(TagFromComment(c) == "SQ")
         CancelPending("SQ");
      return;
     }

   if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY || entry == DEAL_ENTRY_INOUT)
     {
      double net = HistoryDealGetDouble(trans.deal, DEAL_PROFIT) + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION) +
                   HistoryDealGetDouble(trans.deal, DEAL_SWAP) + HistoryDealGetDouble(trans.deal, DEAL_FEE);
      if(net < 0)
         consecLoss++;
      else
         consecLoss = 0;
      if(InpMaxConsecLoss > 0 && consecLoss >= InpMaxConsecLoss)
        {
         pauseUntil = TimeCurrent() + InpPauseMinutes * 60;
         consecLoss = 0;
         CancelPending("");
         PrintFormat("%d loss beruntun, jeda sampai %s", InpMaxConsecLoss, TimeToString(pauseUntil, TIME_DATE | TIME_MINUTES));
        }
     }
  }

//+------------------------------------------------------------------+
//| Statistik per strategi (dicetak saat EA dilepas / backtest usai) |
//+------------------------------------------------------------------+
void PrintStrategyStats()
  {
   if(!HistorySelect(0, TimeCurrent() + 86400))
      return;
   int nTags = ArraySize(STRAT_TAGS);
   long   pid[];
   int    ptag[];
   double pnet[];
   bool   pclosed[];
   int    np = 0;

   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong tk = HistoryDealGetTicket(i);
      if(tk == 0 || HistoryDealGetInteger(tk, DEAL_MAGIC) != InpMagic ||
         HistoryDealGetString(tk, DEAL_SYMBOL) != _Symbol)
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
      long entry = HistoryDealGetInteger(tk, DEAL_ENTRY);
      if(entry == DEAL_ENTRY_IN)
        {
         ulong ord = (ulong)HistoryDealGetInteger(tk, DEAL_ORDER);
         string c = (ord > 0) ? HistoryOrderGetString(ord, ORDER_COMMENT) : "";
         if(c == "")
            c = HistoryDealGetString(tk, DEAL_COMMENT);
         ptag[idx] = TagIndex(TagFromComment(c));
        }
      else
         pclosed[idx] = true;
     }

   int    cnt[], wins[];
   double gp[], gl[];
   ArrayResize(cnt, nTags);
   ArrayResize(wins, nTags);
   ArrayResize(gp, nTags);
   ArrayResize(gl, nTags);
   ArrayInitialize(cnt, 0);
   ArrayInitialize(wins, 0);
   ArrayInitialize(gp, 0.0);
   ArrayInitialize(gl, 0.0);

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

   Print("===== Statistik per strategi (", _Symbol, ", magic ", InpMagic, ") =====");
   Print("Tag  Trades  Win%    Net        PF");
   for(int k = 0; k < nTags; k++)
     {
      double wr = cnt[k] > 0 ? 100.0 * wins[k] / cnt[k] : 0;
      string pf = gl[k] > 0 ? DoubleToString(gp[k] / gl[k], 2) : (gp[k] > 0 ? "inf" : "-");
      PrintFormat("%-4s %6d  %5.1f  %9.2f  %6s", STRAT_TAGS[k], cnt[k], wr, gp[k] - gl[k], pf);
     }
   Print("TU/TD=trend pullback, SW=sideways, BU/BD=breakout, SQ=squeeze straddle");
  }

//+------------------------------------------------------------------+
void Dashboard(const string why)
  {
   string s = "Adaptive Scalper M1 v2\n";
   s += "Kondisi : " + RegimeName(regime);
   if(gRaw != regime)
      s += StringFormat("  (kandidat: %s %d/%d)", RegimeName(candReg), candCount, InpConfirmBars);
   s += "\n";
   s += StringFormat("ADX %.1f | RSI %.1f | ATR %.2f | BB-ratio %.2f | HTF %s\n", gAdx, gRsi, gAtr, gBwRatio,
                     !InpUseHtf ? "off" : (gHtfBias > 0 ? "naik" : "turun"));
   s += StringFormat("Posisi %d | Pending %d | Loss beruntun %d\n", CountPositions(), CountPending(""), consecLoss);
   s += "Status  : " + why;
   Comment(s);
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   ManagePositions();

   // cadangan OCO bila komentar order tidak terbaca saat transaksi
   if(CountPositions("SQ") > 0 && CountPending("SQ") > 0)
      CancelPending("SQ");

   datetime t = iTime(_Symbol, _Period, 0);
   if(t == lastBar)
      return;
   if(!Refresh())
      return;
   lastBar = t;

   UpdateRegime();
   CleanupPending();

   string why;
   bool cancelAll;
   bool ok = CanTrade(why, cancelAll);
   Dashboard(why);
   if(!ok)
     {
      if(cancelAll)
         CancelPending("");
      return;
     }
   PlaceForRegime();
  }
//+------------------------------------------------------------------+
