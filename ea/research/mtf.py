"""Riset multi-timeframe: konteks M15/H1/H4 + pemicu pola candle M5.

Konteks timeframe besar hanya memakai bar yang SUDAH tutup (tidak mengintip masa depan).
Varian = pemicu M5 x filter konteks x exit. Entry hanya bila arah pemicu == arah filter.
Mesin simulasi, biaya, dan pembagian train/test sama dengan lab.py.
"""
import sys, itertools
import numpy as np
import pandas as pd
import lab  # memuat data & fungsi simulate dari lab.py (argumen CSV sama)

t, o, h, l, c, atr, N = lab.t, lab.o, lab.h, lab.l, lab.c, lab.atr, lab.N
hour = lab.hour
idx = pd.DatetimeIndex(t)
base = pd.DataFrame({'open': o, 'high': h, 'low': l, 'close': c}, index=idx)

def htf(rule, minutes):
    """Fitur timeframe besar, diselaraskan ke bar M5 setelah bar TF itu tutup."""
    b = base.resample(rule).agg({'open': 'first', 'high': 'max', 'low': 'min', 'close': 'last'}).dropna()
    e20 = b.close.ewm(span=20, adjust=False).mean()
    e50 = b.close.ewm(span=50, adjust=False).mean()
    trend = np.where((b.close > e50) & (e20 > e50), 1, np.where((b.close < e50) & (e20 < e50), -1, 0))
    d = b.close.diff()
    up = d.clip(lower=0).ewm(alpha=1 / 14, adjust=False).mean()
    dn = (-d).clip(lower=0).ewm(alpha=1 / 14, adjust=False).mean()
    rsi = 100 - 100 / (1 + up / dn.replace(0, np.nan))
    hi20, lo20 = b.high.rolling(20).max(), b.low.rolling(20).min()
    pos = (b.close - lo20) / (hi20 - lo20)
    # .to_numpy(): jangan biarkan pandas menyelaraskan ulang Series ke indeks baru (itu membocorkan bar berikutnya)
    f = pd.DataFrame({'trend': trend, 'rsi': rsi.to_numpy(), 'pos': pos.to_numpy()},
                     index=b.index + pd.Timedelta(minutes=minutes))
    # bar M5 yang tutup pada waktu T punya label T-5m; fitur TF tersedia bila labelnya >= waktu tutup TF
    f = f.reindex(idx + pd.Timedelta(minutes=5), method='ffill')
    return f.trend.fillna(0).to_numpy().astype(int), f.rsi.fillna(50).to_numpy(), f.pos.fillna(0.5).to_numpy()

tr15, rsi15, pos15 = htf('15min', 15)
tr60, rsi60, pos60 = htf('1h', 60)
tr240, rsi240, pos240 = htf('4h', 240)

# ---------------- pemicu M5 (arah dari pola) ----------------
po, pc = np.roll(o, 1), np.roll(c, 1)
body = abs(c - o)
rng = np.maximum(h - l, 1e-9)
lw = np.minimum(o, c) - l
uw = h - np.maximum(o, c)
TRIG = {
    'engulfing': np.where((pc < po) & (c > o) & (c > po) & (o < pc), 1, np.where((pc > po) & (c < o) & (c < po) & (o > pc), -1, 0)),
    'pinbar': np.where((lw >= 2 * body) & (c > l + 0.66 * rng), 1, np.where((uw >= 2 * body) & (c < h - 0.66 * rng), -1, 0)),
    'inside_break': np.where(
        (np.roll(h, 1) < np.roll(h, 2)) & (np.roll(l, 1) > np.roll(l, 2)) & (c > np.roll(h, 1)), 1,
        np.where((np.roll(h, 1) < np.roll(h, 2)) & (np.roll(l, 1) > np.roll(l, 2)) & (c < np.roll(l, 1)), -1, 0)),
    'break12': np.where(c > pd.Series(h).shift(1).rolling(12).max().to_numpy(), 1,
                        np.where(c < pd.Series(l).shift(1).rolling(12).min().to_numpy(), -1, 0)),
    'ema_bounce': np.where((lab.e20 > lab.e50) & (l <= lab.e20) & (c > lab.e20) & (c > o), 1,
                           np.where((lab.e20 < lab.e50) & (h >= lab.e20) & (c < lab.e20) & (c < o), -1, 0)),
    'rsi_cross': np.where((np.roll(lab.rsi, 1) < 30) & (lab.rsi >= 30), 1,
                          np.where((np.roll(lab.rsi, 1) > 70) & (lab.rsi <= 70), -1, 0)),
}

# ---------------- filter konteks: arah yang diizinkan (+1/-1/0) ----------------
FILT = {
    'tanpa_filter': None,
    'H4_tren': tr240,
    'H1+H4_tren': np.where(tr60 == tr240, tr240, 0),
    'M15+H1+H4_tren': np.where((tr15 == tr60) & (tr60 == tr240), tr240, 0),
    'H4_tren+H1_pullback': np.where((tr240 > 0) & (rsi60 < 45), 1, np.where((tr240 < 0) & (rsi60 > 55), -1, 0)),
    'H4_tren+M15_lawan': np.where((tr240 != 0) & (tr15 == -tr240), tr240, 0),
    'H4_support_resist': np.where(pos240 < 0.15, 1, np.where(pos240 > 0.85, -1, 0)),
    'H1_RSI_ekstrem': np.where(rsi60 < 30, 1, np.where(rsi60 > 70, -1, 0)),
}
EXITS = [(1.5, 2.0), (1.5, 3.0)]
SESSION = (hour >= 7) & (hour < 18)

if __name__ == '__main__':
    cut = int(N * 0.7)
    rows = []
    for (tn, tg), (fn, fd) in itertools.product(TRIG.items(), FILT.items()):
        sig = tg if fd is None else np.where(tg == fd, tg, 0)
        sig = np.where(SESSION, sig, 0)
        for k, rr in EXITS:
            ix, r = lab.simulate(sig, k, rr)
            def st(x):
                n = len(x)
                return (n, x.mean(), x.mean() / x.std(ddof=1) * np.sqrt(n), (x > 0).mean()) if n > 1 else (n, np.nan, np.nan, np.nan)
            a, b = st(r[ix < cut]), st(r[ix >= cut])
            rows.append(dict(pemicu=tn, filter=fn, sl=k, rr=rr, n_tr=a[0], R_tr=a[1], t_tr=a[2], win_tr=a[3],
                             n_te=b[0], R_te=b[1], t_te=b[2], win_te=b[3]))
    res = pd.DataFrame(rows)
    res.to_csv('results_mtf.csv', index=False)
    pd.set_option('display.width', 220)
    print(f"{len(res)} varian; R_tr>0: {(res.R_tr > 0).sum()}, R_te>0: {(res.R_te > 0).sum()}, keduanya: {((res.R_tr > 0) & (res.R_te > 0)).sum()}")
    print(res.sort_values('t_tr', ascending=False).head(20).round(3).to_string())
    print('\nRata-rata R per filter (semua pemicu & exit):')
    print(res.groupby('filter')[['R_tr', 'R_te', 'n_tr']].mean().sort_values('R_tr', ascending=False).round(3).to_string())
    print('\nRata-rata R per pemicu:')
    print(res.groupby('pemicu')[['R_tr', 'R_te', 'n_tr']].mean().sort_values('R_tr', ascending=False).round(3).to_string())
