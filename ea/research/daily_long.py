"""Trend following harian XAUUSD 2016-2026 (data Stooq dari pengguna).

Posisi ditentukan dari close hari t, dipegang dari close t sampai close t+1 (tanpa mengintip).
Biaya 0.03% setiap kali posisi berubah 1 unit (spread+komisi+slip). Swap tidak dihitung.
Varian 'vol target' menskalakan posisi agar volatilitas tahunan ~15% (Hurst, Ooi & Pedersen),
memakai volatilitas 20 hari yang diketahui pada hari t, maksimum 2x.
"""
import sys
import numpy as np
import pandas as pd

D = pd.read_csv(sys.argv[1], parse_dates=['Date']).set_index('Date').sort_index()
c, h, l = D.Close, D.High, D.Low
ret = c.pct_change().fillna(0)
COST = 0.0003
CAP = float(sys.argv[2]) if len(sys.argv) > 2 else 2.0

def ema(x, n):
    return x.ewm(span=n, adjust=False).mean()

def turtle(n_in, n_out, long_only=False):
    hi, lo = h.shift(1).rolling(n_in).max(), l.shift(1).rolling(n_in).min()
    xhi, xlo = h.shift(1).rolling(n_out).max(), l.shift(1).rolling(n_out).min()
    pos, out = 0, []
    for i in range(len(D)):
        ci = c.iloc[i]
        if pos == 1 and ci < xlo.iloc[i] or pos == -1 and ci > xhi.iloc[i]:
            pos = 0
        if pos == 0:
            if ci > hi.iloc[i]:
                pos = 1
            elif ci < lo.iloc[i] and not long_only:
                pos = -1
        out.append(pos)
    return pd.Series(out, index=D.index, dtype=float)

e20, e50 = ema(c, 20), ema(c, 50)
sma50, sma200, sma210 = c.rolling(50).mean(), c.rolling(200).mean(), c.rolling(210).mean()
S = {
    'Beli & tahan': pd.Series(1.0, index=D.index),
    'EMA 20/50 harian (long/short)': pd.Series(np.where((c > e50) & (e20 > e50), 1, np.where((c < e50) & (e20 < e50), -1, 0)), index=D.index, dtype=float),
    'EMA 20/50 harian (long saja)': pd.Series(np.where((c > e50) & (e20 > e50), 1, 0), index=D.index, dtype=float),
    'SMA 50/200 golden cross (long saja)': pd.Series(np.where(sma50 > sma200, 1, 0), index=D.index, dtype=float),
    'Faber: close > SMA 10 bulan (long saja)': pd.Series(np.where(c > sma210, 1, 0), index=D.index, dtype=float),
    'Momentum 3 bulan (long/short)': np.sign(c / c.shift(63) - 1).fillna(0),
    'Momentum 12 bulan (long/short)': np.sign(c / c.shift(252) - 1).fillna(0),
    'Momentum 12 bulan (long saja)': (c / c.shift(252) - 1 > 0).astype(float),
    'Turtle 20/10 (long/short)': turtle(20, 10),
    'Turtle 55/20 (long/short)': turtle(55, 20),
    'Turtle 55/20 (long saja)': turtle(55, 20, True),
}
vol20 = ret.rolling(20).std() * np.sqrt(252)
scale = (0.15 / vol20).clip(upper=CAP).fillna(0)

def perf(pos, vt=False):
    p = pos * (scale if vt else 1.0)
    p = p.where(c.rolling(252).count() >= 252, 0)            # mulai setelah 1 tahun data (pemanasan)
    r = p.shift(1).fillna(0) * ret - p.diff().abs().fillna(0) * COST
    r = r[r.index >= r.index[252]]
    eq = (1 + r).cumprod()
    yrs = (r.index[-1] - r.index[0]).days / 365.25
    cagr = eq.iloc[-1] ** (1 / yrs) - 1
    vol = r.std() * np.sqrt(252)
    dd = (eq / eq.cummax() - 1).min()
    yearly = r.groupby(r.index.year).apply(lambda x: (1 + x).prod() - 1)
    t_in = (p.shift(1)[r.index] != 0).mean()
    return dict(CAGR=cagr, vol=vol, sharpe=r.mean() / r.std() * np.sqrt(252), maxDD=dd, waktu_di_pasar=t_in), yearly

pd.set_option('display.width', 250)
rows, yrows = [], {}
for name, pos in S.items():
    for vt in (False, True):
        if vt and name.startswith('Beli'):
            continue
        m, y = perf(pos, vt)
        key = name + (' + vol target' if vt else '')
        rows.append(dict(strategi=key, **m))
        yrows[key] = y
res = pd.DataFrame(rows)
fmt = res.copy()
for col in ('CAGR', 'vol', 'maxDD', 'waktu_di_pasar'):
    fmt[col] = (fmt[col] * 100).round(1).astype(str) + '%'
fmt['sharpe'] = res.sharpe.round(2)
print(f"Periode uji: {D.index[252].date()} s/d {D.index[-1].date()} (tahun pertama untuk pemanasan indikator)\n")
print(fmt.to_string(index=False))
print("\nReturn per tahun (%):")
yt = pd.DataFrame(yrows).T * 100
print(yt.round(0).astype(int).to_string())
res.to_csv('results_daily_long.csv', index=False)
yt.to_csv('results_daily_long_yearly.csv')
