"""Reaksi XAUUSD terhadap berita USD (kalender MT5, waktu server sama dengan data harga).

1. Besar gerakan setelah berita high-impact vs jam yang sama di hari tanpa berita.
2. Surprise (aktual - perkiraan) -> arah gold. Entry di close bar M5 pertama setelah rilis
   (tidak mengejar detik pertama), exit +30 / +60 menit. Biaya $0.60 (spread melebar + slippage).
3. Momentum bar pertama: arah 5 menit pertama dilanjutkan atau dibalik?
Train/test: tanggal potong sama dengan lab.py (70% bar harga).
"""
import sys
import numpy as np
import pandas as pd

px = pd.read_csv(sys.argv[1], parse_dates=['time']).drop_duplicates('time').set_index('time').sort_index()
cal = pd.read_csv(sys.argv[2], parse_dates=['time'])
CUT = px.index[int(len(px) * 0.7)]
COST = 0.60
close = px.close

def price_at(ts):
    """close bar M5 yang tutup tepat pada/ sebelum ts (bar berlabel ts-5m)."""
    s = close.loc[:ts - pd.Timedelta(minutes=5)]
    return s.iloc[-1] if len(s) else np.nan

# USD menguat bila angka > perkiraan, kecuali indikator "buruk" (pengangguran, klaim)
INVERSE = ('Unemployment Rate', 'Initial Jobless Claims', 'Continuing Jobless Claims')
KEY = ['Nonfarm Payrolls', 'CPI m/m', 'Core CPI m/m', 'CPI y/y', 'Core PCE Price Index m/m', 'PPI m/m',
       'Retail Sales m/m', 'Core Retail Sales m/m', 'ISM Manufacturing PMI', 'ISM Non-Manufacturing PMI',
       'Unemployment Rate', 'Initial Jobless Claims', 'Average Hourly Earnings m/m', 'ADP Nonfarm Employment Change',
       'JOLTS Job Openings', 'Fed Interest Rate Decision']

high = cal[cal.importance == 'high'].copy()
times = sorted(set(high.time))
idx_set = set(px.index)

# ---------- 1. volatilitas ----------
rows = []
for ts in times:
    p0 = price_at(ts)
    for m in (5, 15, 30, 60):
        p1 = price_at(ts + pd.Timedelta(minutes=m))
        rows.append((ts, m, abs(p1 - p0)))
v = pd.DataFrame(rows, columns=['ts', 'menit', 'gerak']).dropna()
news_days = {t.normalize() for t in times}
base = []
for ts in times:
    for back in (7, 14):  # jam yang sama 1-2 minggu sebelumnya, bila hari itu tanpa berita high
        t2 = ts - pd.Timedelta(days=back)
        if t2.normalize() in news_days:
            continue
        p0 = price_at(t2)
        for m in (5, 15, 30, 60):
            base.append((m, abs(price_at(t2 + pd.Timedelta(minutes=m)) - p0)))
b = pd.DataFrame(base, columns=['menit', 'gerak']).dropna()
print("1) Rata-rata besar gerakan gold (USD) setelah jam rilis:")
print(pd.DataFrame({'berita high': v.groupby('menit').gerak.mean(), 'tanpa berita (jam sama)': b.groupby('menit').gerak.mean()}).round(2).to_string())

# ---------- 2. surprise -> arah ----------
key = high[high.event.isin(KEY) & high.actual.notna() & high.forecast.notna()].copy()
key['surprise'] = np.sign(key.actual - key.forecast) * np.where(key.event.isin(INVERSE), -1, 1)
# satu sinyal per waktu rilis: jumlah arah surprise (USD kuat = +); gold diharapkan berlawanan
g = key.groupby('time').surprise.sum()
g = g[g != 0]
res = []
for ts, s in g.items():
    gold_dir = -np.sign(s)                     # USD kuat -> jual gold
    e = price_at(ts + pd.Timedelta(minutes=5))  # masuk setelah bar pertama tutup
    for m in (30, 60):
        x = price_at(ts + pd.Timedelta(minutes=5 + m))
        res.append((ts, m, gold_dir * (x - e) - COST))
r = pd.DataFrame(res, columns=['ts', 'menit', 'pnl']).dropna()
r['set'] = np.where(r.ts < CUT, 'train', 'test')
print(f"\n2) Trading arah surprise (gold berlawanan USD), masuk 5 menit setelah rilis, biaya ${COST}:")
print(r.groupby(['menit', 'set']).pnl.agg(['count', 'mean', lambda x: (x > 0).mean()]).rename(
    columns={'mean': 'rata2 USD/oz', '<lambda_0>': 'win%'}).round(2).to_string())

# apakah bar pertama sudah searah surprise? (reaksi instan)
first = []
for ts, s in g.items():
    p0, p1 = price_at(ts), price_at(ts + pd.Timedelta(minutes=5))
    first.append(np.sign(p1 - p0) == -np.sign(s))
print(f"   Bar 5 menit pertama sudah bergerak sesuai teori (gold berlawanan USD): {np.mean(first):.0%} dari {len(first)} rilis")

# ---------- 3. momentum bar pertama ----------
res = []
for ts in times:
    p0, p1 = price_at(ts), price_at(ts + pd.Timedelta(minutes=5))
    d = np.sign(p1 - p0)
    if d == 0 or np.isnan(d):
        continue
    for m in (30, 60):
        x = price_at(ts + pd.Timedelta(minutes=5 + m))
        res.append((ts, m, 'lanjut', d * (x - p1) - COST))
        res.append((ts, m, 'balik', -d * (x - p1) - COST))
r3 = pd.DataFrame(res, columns=['ts', 'menit', 'arah', 'pnl']).dropna()
r3['set'] = np.where(r3.ts < CUT, 'train', 'test')
print("\n3) Ikuti / lawan arah bar 5 menit pertama setelah berita high:")
print(r3.groupby(['arah', 'menit', 'set']).pnl.agg(['count', 'mean', lambda x: (x > 0).mean()]).rename(
    columns={'mean': 'rata2 USD/oz', '<lambda_0>': 'win%'}).round(2).to_string())
print(f"\nPotong train/test: {CUT}")
