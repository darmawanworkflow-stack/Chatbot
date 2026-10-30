# Adaptive Scalper M1 (MT5 EA)

EA scalping untuk MetaTrader 5, dirancang untuk XAUUSD timeframe M1. EA membaca kondisi pasar tiap candle baru, lalu memilih jenis order yang cocok.

| Kondisi | Deteksi | Order |
|---|---|---|
| Trend naik | ADX ≥ 25, EMA21 > EMA55, EMA21 menanjak | **Buy Limit** saat pullback (0.5 ATR di bawah harga) |
| Trend turun | ADX ≥ 25, EMA21 < EMA55, EMA21 menurun | **Sell Limit** saat pullback |
| Sideways | ADX ≤ 20, lebar BB normal | **Buy Limit** di BB bawah, **Sell Limit** di BB atas, TP ke tengah BB |
| Breakout | candle ≥ 1.5 ATR menembus high/low 20 bar | **Buy Stop** / **Sell Stop** searah breakout |
| Squeeze | lebar BB < 0.65 × rata-rata 100 bar | **Buy Stop + Sell Stop** (OCO: salah satu terisi, sisanya dihapus) |
| Tidak jelas | di luar semua kondisi di atas | tidak trading |

Pending order milik kondisi lama otomatis dihapus saat kondisi berubah, dan dihapus juga setelah `InpExpiryBars` bar.

## Manajemen risiko
- Lot dihitung dari **risiko % equity ÷ jarak SL**, bukan digandakan seperti di video.
- SL/TP berbasis ATR, break-even, trailing, dan tutup paksa setelah N bar.
- Filter spread (points dan % dari TP), filter jam, batas rugi harian.
- Akun kecil: kalau lot minimum melebihi risiko yang diizinkan, order dilewati. Aktifkan `InpForceMinLot` untuk memaksa.

## Pasang
1. MT5 → File → Open Data Folder → `MQL5/Experts/`, salin `AdaptiveScalperM1.mq5`.
2. Buka di MetaEditor, tekan **F7** (Compile).
3. Pasang di chart XAUUSD M1, aktifkan Algo Trading.

## Uji dulu
- Strategy Tester: model **Every tick based on real ticks**, M1, spread asli broker.
- Setelah itu jalankan di akun **demo** minimal 2 minggu.
- Sesuaikan `InpMaxSpreadPts`, `InpStartHour`/`InpEndHour`, dan nama simbol (mis. `XAUUSD.vx`).

## Catatan
- Kode **belum dikompilasi atau dijalankan** (tidak ada MetaEditor di lingkungan pengembangan). Kalau ada error compile, kirim pesan error-nya.
- Tidak ada jaminan profit. Hasil di video ($10 → $5.692 dalam 20 menit) adalah demo dengan lot yang terus dibesarkan, dan histori deal di akhir video penuh loss -100 USD.
