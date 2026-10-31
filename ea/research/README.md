# Riset sinyal M5 XAUUSD (Jan 2024 – Okt 2026)

Data: 200.903 bar M5 Exness (diekspor dengan `ExportHistory.mq5`). Data tidak disimpan di repo.

```bash
python3 lab.py XAUUSD_M5_20240101_20261030.csv     # 15 sinyal x 9 exit x 2 filter jam -> results.csv
python3 season.py XAUUSD_M5_20240101_20261030.csv  # kecenderungan per jam & hari
```

Aturan: train = 70% data pertama (s/d Des 2025), test = 30% terakhir. Entry di open bar berikutnya, SL dicek lebih dulu dari TP di bar yang sama, biaya per trade = spread bar (min $0.04) + komisi $0.11 + slippage $0.05, satu posisi per varian, tutup paksa setelah 48 bar.

## Hasil
- 270 varian. Statistik-t terbaik di train hanya 1.36; tidak ada yang signifikan.
- 13 varian positif di train dan test, sesuai yang diharapkan dari kebetulan (~12).
- Pullback EMA (yang lolos uji Jul–Okt 2026 di Strategy Tester) negatif di semua 9 setelan exit di train maupun test, setara entry acak.
- Pola per jam: tidak ada yang konsisten; satu-satunya angka besar (jam 22) berasal dari celah harga saat pasar buka kembali, tidak bisa ditradingkan.
- Gold naik +2.429 USD di periode train dan turun −598 USD di periode test.

## Multi-timeframe (`mtf.py`)
```bash
python3 mtf.py XAUUSD_M5_20240101_20261030.csv   # 6 pemicu candle M5 x 8 filter M15/H1/H4 x 2 exit -> results_mtf.csv
```
Konteks timeframe besar hanya dari bar yang sudah tutup. Jalur sesi 07:00–18:00.

- 96 varian; 5 positif di train dan test (≈ yang diharapkan dari kebetulan).
- Statistik-t terbaik di train 1.21 (inside bar + tren H4 + pullback H1), negatif di test.
- Filter keselarasan tren (M15+H1+H4 atau H1+H4) mengurangi kerugian dibanding tanpa filter, tetapi rata-ratanya tetap tidak positif setelah biaya.

Catatan: versi pertama `mtf.py` membocorkan bar H1/H4 berikutnya (Series pandas diselaraskan ulang ke indeks yang sudah digeser), sehingga filter RSI/posisi range tampak sangat untung. Sudah diperbaiki dengan `.to_numpy()`; hasil di atas dari versi yang benar.

## Berita USD (`news.py`, `newsfilter.py`)
Kalender diekspor dengan `ExportCalendar.mq5` (5.069 berita USD, 1.402 high-impact, Jan 2024 – Okt 2026).
```bash
python3 news.py XAUUSD_M5_20240101_20261030.csv calendar_USD.csv
python3 newsfilter.py XAUUSD_M5_20240101_20261030.csv calendar_USD.csv
```
- Gerak 5 menit setelah berita high rata-rata $4.63 vs $2.98 di jam yang sama tanpa berita; setelah 60 menit selisihnya kecil ($9.95 vs $8.31).
- Bar 5 menit pertama sudah bergerak searah surprise (gold berlawanan USD) pada 67% rilis. Masuk setelah bar pertama searah surprise: negatif di train dan test (pasar sudah menyerapnya).
- Mengikuti arah bar pertama: negatif. Melawannya: tidak konsisten (−0.34 train, +0.91 test USD/oz).
- Menghindari jendela berita (−30/+60 menit) tidak memperbaiki sinyal mana pun.
- Pullback EMA **hanya** di jendela berita: +0.063R train / +0.238R test (~500 trade). Belum signifikan secara statistik, dan biaya saat berita kemungkinan diremehkan (spread & slippage melebar). Hipotesis untuk diuji maju, bukan bukti.

## Putaran 3: SMC/ICT, level, indikator lain, pola chart, aturan keluar (`round3.py`)
```bash
python3 round3.py XAUUSD_M5_20240101_20261030.csv   # 17 sinyal x 6 aturan keluar -> results_round3.csv
```
Aturan ditetapkan sebelum melihat hasil: penemuan Jan 2024 – Jul 2026; Agu–Okt 2026 dikunci dan hanya dibuka untuk varian yang lolos (t ≥ 3 dan rata-rata R > 0 di 2024, 2025, 2026).

Sinyal: sweep likuiditas range Asia & high/low kemarin, retrace FVG, BOS, CHoCH, pantulan pivot S1/R1, pantulan angka bulat $50, breakout high/low kemarin, Fibonacci 50–61.8%, MACD cross, MACD divergence, Supertrend flip, pantulan VWAP, ADX + breakout, Stochastic, double bottom/top, acak.
Aturan keluar: ATR 2R, ATR 3R, SL swing 2R, break-even lalu 3R, trailing 2 ATR, partial 50% di 1R + sisanya 3R.

- 102 varian, **0 lolos**. Statistik-t terbaik 0.59 (breakout high/low kemarin, ATR 2R).
- Entry acak (BE→3R) masuk 3 besar; sebagian besar sinyal lebih buruk dari acak.
- Tidak ada aturan keluar yang membuat rata-rata positif; trailing paling tidak buruk (−0.034R).
- Periode terkunci tidak dibuka karena tidak ada varian yang lolos.

## Backtest kasar TechnicalMap (`tmap_bt.py`, `tmap_phase.py`, `tmap_align.py`)
```bash
python3 tmap_bt.py    XAUUSD_M5_20240101_20261030.csv   # panah konfluensi, skor kesimpulan, fase
python3 tmap_phase.py XAUUSD_M5_20240101_20261030.csv   # fase per tahun (sampel per jam, tanpa tumpang tindih)
python3 tmap_align.py XAUUSD_M5_20240101_20261030.csv   # aturan sederhana dari fase selaras penuh
```
- Panah konfluensi (pola di level kekuatan ≥ 2, tren H1 tidak berlawanan): −0.068R (2R) vs acak −0.057R.
- Skor kesimpulan "condong naik/turun": tepat arah 50.7% (5 mnt), 50.4% (1 jam); gerak searah $0.18/jam < biaya.
- Fase sinkronisasi, gerak 1 jam searah tren besar (H4 = H1):

| Fase | 2024 | 2025 | 2026 | Gabungan (t) |
|---|---|---|---|---|
| Selaras penuh (H4, H1, M15, M5 searah) | +$0.20 | +$0.45 | +$1.09 | +$0.55 (3.60) |
| M15 searah, M5 koreksi | −$0.40 | +$0.65 | −$0.34 | $0.00 (0.00) |
| Pullback M15 | −$0.16 | −$0.74 | +$0.44 | −$0.19 (−0.74) |
| Pullback melemah (M15 datar) | +$0.07 | −$0.03 | −$2.15 | −$0.63 (−2.23) |

- Aturan "masuk saat baru selaras penuh, keluar saat M15 berbalik, SL 2 ATR": +0.154R/trade, t 2.33 (2024 −0.005R, 2025 +0.386R, 2026 +0.065R). Jam 07–18 saja: +0.193R, t 2.32. Menahan tetap 1 jam: ≈ 0R.
- Catatan: temuan fase ini muncul setelah banyak pengujian; konsisten dengan literatur time-series momentum, tetapi sebagian besar hasil aturan berasal dari 2025. Perlu uji maju.

## Putaran 4: metode dari forum/komunitas (`round4.py`)
```bash
python3 round4.py XAUUSD_M5_20240101_20261030.csv   # -> results_round4.csv
```
Aturan sama dengan putaran 3 (Agu–Okt 2026 tetap terkunci). Jam New York memakai DST AS.

| Metode | n | R | t | 2024 | 2025 | 2026 |
|---|---|---|---|---|---|---|
| Momentum harian 20 hari | 784 | +0.043 | 1.60 | +0.008 | +0.067 | +0.059 |
| ICT Silver Bullet NY PM 14–15 ET | 558 | +0.041 | 0.82 | +0.001 | +0.080 | +0.045 |
| Connors RSI(2) H4 | 78 | +0.045 | 0.49 | −0.086 | +0.156 | +0.039 |
| London close reversal | 443 | +0.010 | 0.48 | +0.024 | −0.047 | +0.092 |
| Inside day breakout | 158 | +0.113 | 0.44 | −0.223 | +0.476 | +0.103 |
| Connors RSI(2) H1 | 324 | +0.018 | 0.32 | −0.024 | +0.095 | −0.053 |
| NR7 breakout | 69 | +0.092 | 0.18 | −0.531 | +0.552 | +0.294 |
| Silver Bullet NY AM 10–11 ET (+ sweep) | 211 | +0.002 | 0.03 | −0.121 | +0.179 | −0.073 |
| NY opening range 15 menit (1R / 2R) | 656 | ≈ −0.01 | ≈ −0.2 | | | |
| Silver Bullet London 03–04 ET (+ sweep) | 171 | −0.164 | −1.83 | | | |
| Turtle Soup M5 | 2.171–2.922 | −0.09…−0.11 | −3.9…−4.8 | | | |

0 dari 17 lolos. Momentum harian dan Silver Bullet NY PM positif tiap tahun tetapi jauh dari t ≥ 3. Turtle Soup (fade false breakout) negatif signifikan: di gold M5 breakout lebih sering berlanjut daripada gagal.

## Insight riset EMA (`ema_research.py`)
Fase selaras penuh (H4, H1, M15, M5 searah), gerak 1 jam ke depan searah tren besar, sampel per jam:

| EMA | n | USD/jam | t | 2024 | 2025 | 2026 |
|---|---|---|---|---|---|---|
| 9/21 | 4474 | +0.44 | 2.51 | +0.14 | +0.15 | +1.18 |
| 10/30 | 4842 | +0.49 | 3.05 | +0.12 | +0.30 | +1.19 |
| **20/50** | 4797 | **+0.55** | **3.60** | +0.20 | +0.45 | +1.09 |
| 20/100 | 5659 | +0.48 | 3.54 | +0.06 | +0.50 | +0.95 |
| 50/100 | 4804 | +0.58 | 3.89 | +0.04 | +0.64 | +1.16 |
| 50/200 | 5624 | +0.50 | 3.76 | +0.05 | +0.57 | +0.95 |

Efeknya bertahan di semua pasangan EMA (tidak bergantung pada pilihan 20/50). Per rezim volatilitas (ATR H1 vs median 30 hari): rendah +$0.73 (t 2.39), normal +$0.33 (t 1.71, 2025 −0.02), tinggi +$0.86 (t 2.40). Tidak cukup jelas untuk dijadikan filter.

## Trend following harian ala Turtle (`daily_trend.py`)
Masuk saat close menembus high/low N hari, keluar saat menembus low/high M hari lawan, R = 2 × ATR(20) harian, biaya $0.40/trade.

| Breakout | Trade | Win | Total | 2024 | 2025 | 2026 |
|---|---|---|---|---|---|---|
| 20/10 buy+sell | 21 | 43% | +12.1R | −0.8 | +11.7 | +1.2 |
| 20/10 buy saja | 13 | 46% | +15.6R | +3.8 | +12.6 | −0.9 |
| 55/20 buy+sell | 7 | 71% | +28.0R | +4.3 | +26.4 | −2.6 |
| 55/20 buy saja | 5 | 80% | +28.2R | +4.3 | +26.4 | −2.4 |

Sampel terlalu kecil (5–21 trade) dan hasilnya didominasi reli gold 2025; beli-dan-tahan sepanjang periode ≈ +40.5R. Tidak bisa disimpulkan dari data 3 tahun.

## Trend following harian 2016–2026 (`daily_long.py`)
Data harian XAUUSD Maret 2016 – Oktober 2026 (Stooq, diunduh pengguna; data tidak disimpan di repo). Uji mulai Februari 2017 (setahun pertama pemanasan). Posisi dari close hari t dipegang sampai close t+1, biaya 0.03% per perubahan posisi, **swap tidak dihitung**.
```bash
python3 daily_long.py xauusd_d.csv   # -> results_daily_long.csv, results_daily_long_yearly.csv
```

| Strategi | CAGR | Sharpe | Max DD | Waktu di pasar |
|---|---|---|---|---|
| Beli & tahan | 12.5% | 0.79 | −28.4% | 100% |
| Faber: close > SMA 10 bulan (long saja) + vol target 15% | 12.5% | 0.88 | −31.9% | 73% |
| SMA 50/200 golden cross (long saja) + vol target | 12.2% | 0.86 | −29.3% | 73% |
| Momentum 12 bulan (long saja) + vol target | 10.8% | 0.77 | −34.4% | 74% |
| EMA 20/50 harian (long saja) + vol target | 9.6% | 0.75 | −27.7% | 56% |
| Turtle 55/20 (long saja) + vol target | 8.5% | 0.74 | −18.4% | 44% |
| EMA 20/50 harian (long/short) | 5.1% | 0.39 | −34.6% | 85% |
| Momentum 12 bulan (long/short) | 4.5% | 0.34 | −44.9% | 100% |
| Turtle 20/10 (long/short) | −0.5% | 0.04 | −45.7% | 77% |

- Tidak ada aturan tren yang mengalahkan beli & tahan dalam CAGR; versi long saja + vol target menyamai CAGR dengan Sharpe sedikit lebih tinggi.
- Sisi jual (short) merugikan di gold 2016–2026 karena kecenderungan naik jangka panjang.
- Turtle 55/20 long saja: CAGR lebih rendah tetapi drawdown terkecil (−18%) dan hanya 44% waktu di pasar.
- Di 2026 (beli & tahan −10%), filter tren mengurangi kerugian (EMA 20/50 long/short +12%).
- Untuk CFD, swap menginap bisa memakan beberapa persen per tahun; angka di atas lebih mewakili emas fisik/ETF.
