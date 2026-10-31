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

---

# Session ORB (`SessionORB.mq5`)

EA kedua dengan satu hipotesis sederhana: **Opening Range Breakout** sesi London dan New York pada XAUUSD.

Hasil uji `AdaptiveScalperM1` (Jul–Okt 2026, Exness Zero): tidak ada strategi yang konsisten positif sebelum komisi, dan hasilnya berbalik saat SL/TP diubah. EA itu disimpan sebagai arsip.

## Cara kerja
1. Catat high/low M1 selama jendela range (London: 00:00–07:00, New York: 11:00–13:30).
2. Saat range selesai, pasang **Buy Stop** di atas high + buffer dan **Sell Stop** di bawah low − buffer. Satu terisi, yang lain dihapus (OCO).
3. SL = 0.5 × lebar range, TP = 2 × SL. SL digeser ke entry setelah profit 1R.
4. Pending dihapus di akhir jendela entry (London 11:00, NY 16:00). Semua posisi ditutup pukul 20:00.
5. Range terlalu sempit (< 0.1 ATR harian) atau terlalu lebar (> 0.7 ATR harian) dilewati.

Maksimal 2 trade per hari. Statistik per sesi (LO/NY) tercetak di Journal tester saat tes selesai.

## Waktu server
Semua jam memakai **waktu server broker**. Exness memakai GMT+0 (cek: bandingkan jam di Market Watch dengan jam GMT). London buka 07:00 GMT (musim panas Eropa) / 08:00 GMT (musim dingin). Kalau broker lain memakai GMT+2/+3, geser semua jam.

## Uji
| Tes | Periode | Gunanya |
|---|---|---|
| A | 2026.07.01 – 2026.08.31 | hasil pertama |
| B | 2026.09.01 – 2026.10.29 | konfirmasi, **setelan tidak boleh diubah** |

Layak dilanjutkan hanya bila A **dan** B positif setelah komisi. Satu backtest 2 bulan ≈ 80 trade, jadi sampelnya masih kecil. Kalau A dan B lolos, uji juga periode yang lebih panjang.

---

# VideoScalper (`VideoScalper.mq5`)

Scalping gaya video: **sesi singkat** (default 20 menit) dengan **modal kecil** (default $10), Buy Stop / Sell Stop berjarak dekat, lot naik mengikuti saldo sesi. **Risiko sangat tinggi.**

## Model
| Model | Cara kerja |
|---|---|
| Grid dua arah | N Buy Stop di atas + N Sell Stop di bawah harga pada level tetap kelipatan `InpStepUSD` (mis. x.50 seperti video). Order tidak digeser; level baru ditambah saat harga bergerak |
| Ladder searah tren | Hanya Buy Stop (atau Sell Stop) bila EMA20/50 M1 menunjukkan tren |
| Straddle | Buy Stop di high N bar + Sell Stop di low N bar, OCO |

Lot = `InpLotPer10` per $10 modal sesi (0.01 di $10, 0.10 di $100, dst., maks `InpMaxLot`).
Sesi berhenti bila modal sesi mencapai `InpTargetMult`×, turun ke `InpBustUSD`, atau waktu habis. Semua posisi ditutup saat sesi selesai.

## Live / demo
`InpStartNow = true`: sesi dimulai saat EA dipasang dan berhenti sendiri. Untuk sesi baru, lepas lalu pasang ulang EA.

## Menguji ratusan sesi di Strategy Tester
Di tester, EA menjalankan sesi pada jam di `InpSessionTimes` setiap hari. **Setiap sesi mulai dari modal virtual $10**, terlepas dari saldo tester. Pakai **deposit 10000** agar margin tidak membatasi. Di akhir tes, Journal mencetak:
```
===== Ringkasan VideoScalper: 170 sesi, modal 10.00 per sesi =====
Mencapai target 5x : ...
Habis (<= 1.00)    : ...
Rata-rata akhir ... (..x) | median ... | terbaik ...
```
**Rata-rata akhir > $10** berarti model itu menguntungkan bila diulang terus.

## Mencari model terbaik (optimizer MT5)
1. Settings: periode **2026.07.01 – 2026.08.31**, real ticks, deposit 10000, Optimization **"Slow complete algorithm"** (atau "Fast genetic" kalau terlalu lama), kriteria **"Custom max"**.
2. Tab Inputs, centang kolom optimasi untuk:

| Input | Start | Step | Stop |
|---|---|---|---|
| Model | 0 | 1 | 2 |
| Jarak antar order | 0.5 | 0.5 | 2.0 |
| Jumlah order per sisi | 1 | 2 | 3 |
| TP = x jarak | 1 | 1 | 3 |
| SL = x jarak | 1 | 1 | 2 |
| Trailing = x jarak | 0 | 1 | 1 |

3. Setelah selesai, urutkan tab **Optimization Results** berdasarkan **Custom**, lalu ekspor (klik kanan → Export to XML).
4. Ambil 3 setelan teratas, uji masing-masing di **2026.09.01 – 2026.10.29** tanpa diubah. Yang tetap > 1.0x di periode kedua adalah kandidat. Kalau tidak ada yang bertahan, artinya tidak ada model yang benar-benar unggul, hanya beruntung di periode pertama.

---

# M5SignalLab (`M5SignalLab.mq5`)

Tahap 1 rencana "$10 → $100 dengan sedikit trade di M5": mengukur apakah ada sinyal M5 yang punya edge **sebelum** dipakai dengan risiko besar.

Tiga sinyal berjalan bersamaan dalam satu backtest (masing-masing maks 1 posisi), SL = 1.5 × ATR M5, TP = 3R, risiko 0.5% per trade:

| Tag | Sinyal |
|---|---|
| LB | London breakout: candle M5 tutup di luar range Asia (00:00–07:00), dicek 07:00–11:00, maks 1×/hari |
| PB | Pullback: tren H1 (close vs EMA50 + arah EMA) dan EMA20 > EMA50 M5; harga menyentuh EMA20 lalu candle tutup searah tren |
| MO | Momentum: candle M5 tutup menembus high/low 48 bar (4 jam) searah tren H1 |

Journal mencetak hasil per sinyal dalam satuan R (biaya termasuk). Dengan target 3R, impas butuh win rate > 25%.

**Lolos bila rata-rata R > 0 dan win rate ≥ 28% di Jul–Agu dan Sep–Okt.** Uji dengan deposit 10000, real ticks, input default.

### Hasil M5SignalLab (input default, real ticks, Exness Zero)
| Sinyal | Jul–Agu | Sep–Okt |
|---|---|---|
| London breakout | 22 trade, 18.2%, −0.282R | 28 trade, 32.1%, +0.136R |
| **Pullback EMA** | **139 trade, 28.8%, +0.029R** | **134 trade, 31.3%, +0.049R** |
| Momentum 4 jam | 83 trade, 32.5%, −0.021R | 82 trade, 28.0%, −0.021R |

Hanya Pullback EMA yang lolos di kedua periode. Edge-nya tipis (~+0.04R/trade) dan secara statistik belum pasti lebih dari kebetulan.

---

# PullbackCampaign (`PullbackCampaign.mq5`)

Tahap 2: kampanye **$10 → $100** dengan sinyal Pullback EMA M5 (aturan entry & exit sama dengan M5SignalLab).

- Lot = `InpRiskFrac` × modal kampanye ÷ kerugian per lot di SL, minimal lot terkecil. Dengan $10, lot 0.01 sudah berarti risiko sekitar 30–60% per trade.
- Kampanye selesai saat modal ≥ target, atau modal turun ke `InpBustUSD` ($5). Bila SL dengan lot terkecil lebih besar dari modal, sinyal dilewati dan EA menunggu.
- **Tester:** kampanye virtual $10 diulang terus sepanjang periode; Journal mencetak berapa yang mencapai target dan berapa yang habis. Pakai deposit 10000 agar margin tester tidak membatasi.
- **Live:** modal = equity akun; EA berhenti sendiri saat target tercapai atau modal habis. Untuk $10, margin 0.01 lot gold di 1:500 sekitar $9, jadi butuh leverage lebih tinggi (mis. 1:1000 atau lebih).

---

# NewsPullbackArrows (`NewsPullbackArrows.mq5`, indikator)

Panah sinyal M5 untuk satu-satunya hipotesis yang tersisa dari riset (`ea/research`): **pullback searah tren H1 di jendela berita USD high-impact** (30 menit sebelum s/d 60 menit sesudah rilis, jam 07:00–18:00 server). Aturannya sama persis dengan riset: masuk di open candle berikutnya, SL 1.5 × ATR(14), TP 3R, tutup paksa setelah 48 candle.

- Panah hijau/merah = sinyal saat berita, dengan garis entry/SL/TP untuk sinyal-sinyal terakhir.
- `InpShowNonNews = true` menampilkan sinyal di luar berita sebagai panah abu-abu (pembanding; di riset hasilnya negatif).
- Pojok kiri atas: status jendela berita, berita berikutnya, dan hasil historis sinyal di chart dalam R (biaya `InpCostUSD` termasuk).
- Alert popup dan notifikasi HP saat sinyal baru.
- Jadwal berita: salin `calendar_USD.csv` (hasil `ExportCalendar.mq5`) ke `MQL5/Files`, ditambah kalender MT5 langsung untuk berita terbaru dan mendatang.

**Hipotesis, belum terbukti.** Catat setiap sinyal di demo 2–3 bulan sebelum memakai uang sungguhan.

---

# TechnicalMap (`TechnicalMap.mq5`, indikator)

Alat bantu baca chart M5 untuk hari biasa. **Bukan sinyal terbukti**: riset 2024–2026 tidak menemukan keunggulan teknikal M5 setelah biaya.

- **Support & Resistance**: swing H1 (10 hari) & H4 (30 hari), high/low kemarin, pivot harian (P, R1, S1), high/low sesi Asia, angka bulat $50. Level yang berjarak ≤ 0.35 ATR H1 digabung; bintang = kekuatan (jumlah bobot sumber).
- **Panel**: tren M5/M15/H1/H4 (close vs EMA50 & EMA20 vs EMA50) + RSI, kesimpulan arah (skor dari tren M15/H1/H4, pola candle terakhir, posisi di support/resistance, RSI M5), 3 support & 3 resistance terdekat.
- **Sinkronisasi antar timeframe**: fase pasar dari hubungan H4/H1 (tren besar), M15 (koreksi) dan M5 (pemicu): selaras penuh, pullback M15, pullback melemah, konflik H4 vs H1; langkah berikutnya; candle H1/H4 yang sedang berjalan (warna, % waktu, posisi harga di range candle); posisi harga di range harian (premium/discount).
- **Pola candle M5**: Engulf, Hammer, ShootStar, MorningStar, EveningStar, Inside, Doji.
- **Panah konfluensi**: pola bullish di support (kekuatan ≥ 2) dan tren H1 tidak turun → biru; kebalikannya → oranye. Panah historis hanya memakai level yang sudah ada pada waktu candle itu.
- **Tanda emas**: awal fase selaras penuh (H4, H1, M15, M5 searah).
- Backtest kasar 2024–2026 (`research/tmap_*.py`): panah konfluensi ≈ acak, skor kesimpulan tepat arah ~51%; fase selaras penuh satu-satunya yang positif tiap tahun (+$0.55/jam searah tren, t 3.6). Teks "Langkah" di panel memakai hasil ini.
