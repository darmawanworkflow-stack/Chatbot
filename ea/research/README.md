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
