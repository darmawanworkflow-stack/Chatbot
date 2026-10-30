# Adaptive Scalper M1 v2 (MT5 EA)

EA scalping untuk MetaTrader 5, dirancang untuk XAUUSD timeframe M1. Setiap candle baru EA membaca kondisi pasar, lalu memilih jenis order yang cocok.

| Kondisi | Tag | Deteksi | Order |
|---|---|---|---|
| Trend naik | TU | ADX ≥ 25, EMA21 > EMA55, EMA21 menanjak | **Buy Limit** saat pullback 0.5 ATR (atau ladder Buy Stop) |
| Trend turun | TD | ADX ≥ 25, EMA21 < EMA55, EMA21 menurun | **Sell Limit** saat pullback (atau ladder Sell Stop) |
| Sideways | SW | ADX ≤ 20, lebar BB normal | **Buy Limit** di BB bawah, **Sell Limit** di BB atas, TP ke tengah BB |
| Breakout | BU/BD | candle ≥ 1.5 ATR menembus high/low 20 bar | **Buy Stop** / **Sell Stop** searah breakout, hanya di bar itu |
| Squeeze | SQ | lebar BB < 0.65 × rata-rata 100 bar | **Buy Stop + Sell Stop** (OCO) |
| Tidak jelas | – | lainnya | tidak membuka order baru |

## Yang baru di v2
- **Konfirmasi regime:** kondisi baru dipakai setelah bertahan `InpConfirmBars` bar (default 3). Breakout dipakai langsung karena sifatnya kejadian satu bar.
- **Pending order tidak lagi dihapus setiap kali regime berganti.** Order hanya dihapus kalau kadaluarsa (`InpExpiryBars`) atau berlawanan arah dengan regime sekarang. Contoh: Sell Stop dihapus saat masuk trend naik.
- **Perbaikan bug squeeze:** begitu satu sisi terisi, sisi lain langsung dihapus (lewat `OnTradeTransaction`), dan EA tidak memasang straddle baru selama posisi SQ masih terbuka.
- **Maks posisi per strategi** (`InpMaxPerStrategy`) supaya satu strategi tidak menumpuk posisi.
- **Spread-aware:** spread ditambahkan ke jarak SL dan TP, dan lot dihitung dari SL yang sudah ditambah itu. Komisi per lot (`InpCommissionLot`) ikut dihitung dalam risiko.
- **Filter berita:** memakai kalender ekonomi bawaan MT5. EA berhenti 30 menit sebelum sampai 30 menit sesudah berita high-impact USD dan menghapus semua pending order. Opsional: tutup posisi (`InpNewsClosePos`).
- **Jeda setelah loss beruntun:** setelah 3 loss beruntun, EA berhenti 30 menit.
- **Statistik per strategi:** dicetak di tab Journal saat backtest selesai atau EA dilepas dari chart.
  ```
  Tag  Trades  Win%    Net        PF
  TU       42  52.4     31.20    1.35
  SW       60  41.7    -18.50    0.82   <- kandidat dimatikan
  ```

## Keterbatasan yang perlu diketahui
- **Kalender ekonomi tidak tersedia di Strategy Tester.** Hasil backtest tetap memuat lonjakan harga saat berita, jadi filter berita baru bekerja di demo atau live.
- Semua parameter masih nilai awal dan **belum dioptimasi**.
- Tidak ada jaminan profit. Hasil di video ($10 → $5.692 dalam 20 menit) adalah demo dengan lot yang terus dibesarkan, dan histori deal di akhir video penuh loss -100 USD.

## Pasang
1. MT5 → File → Open Data Folder → `MQL5/Experts/`, salin `AdaptiveScalperM1.mq5`.
2. Buka di MetaEditor, tekan **F7** (Compile).
3. Untuk filter berita di akun live/demo: pastikan kalender di MT5 aktif (Tools → Options → Server).
4. Pasang di chart XAUUSD M1, aktifkan Algo Trading.

## Alur pengujian yang disarankan
1. Backtest 6–12 bulan, model **Every tick based on real ticks**, spread asli.
2. Lihat statistik per strategi di tab Journal. Matikan strategi dengan PF < 1 lewat `InpUseTrend` / `InpUseRange` / `InpUseBreakout` / `InpUseSqueeze`.
3. Optimasi beberapa parameter saja (mis. `InpSLATR`, `InpTPATR`, `InpAdxTrend`) di periode A, lalu uji tanpa diubah di periode B (walk-forward).
4. Demo 2–4 minggu, lalu akun real kecil.
