"""Riset sinyal M5 XAUUSD: train 70% pertama, test 30% terakhir (kronologis).

Biaya per trade (satuan harga): spread bar entry (min 0.04) + komisi 0.11 + slippage 0.05.
Entry di open bar berikutnya setelah sinyal. SL dicek sebelum TP di bar yang sama (konservatif).
Satu posisi per varian (sinyal baru diabaikan selama posisi terbuka).
"""
import sys, itertools, pickle
import numpy as np
import pandas as pd

CSV = sys.argv[1]
df = pd.read_csv(CSV, parse_dates=['time'])
df = df.drop_duplicates('time').sort_values('time').reset_index(drop=True)
t = df.time
o, h, l, c = (df[k].to_numpy() for k in ('open', 'high', 'low', 'close'))
sp = np.maximum(df.spread.to_numpy() * 0.001, 0.04)
N = len(df)
hour = t.dt.hour.to_numpy()
minute = t.dt.minute.to_numpy()
dow = t.dt.dayofweek.to_numpy()
day = t.dt.normalize().to_numpy()
COST = sp + 0.11 + 0.05

def ema(x, n):
    return pd.Series(x).ewm(span=n, adjust=False).mean().to_numpy()

tr = np.maximum(h - l, np.maximum(abs(h - np.roll(c, 1)), abs(l - np.roll(c, 1))))
atr = pd.Series(tr).ewm(alpha=1 / 14, adjust=False).mean().to_numpy()
e20, e50 = ema(c, 20), ema(c, 50)
ma20 = pd.Series(c).rolling(20).mean().to_numpy()
sd20 = pd.Series(c).rolling(20).std().to_numpy()
d = np.diff(c, prepend=c[0])
up = pd.Series(np.maximum(d, 0)).ewm(alpha=1 / 14, adjust=False).mean()
dn = pd.Series(np.maximum(-d, 0)).ewm(alpha=1 / 14, adjust=False).mean()
rsi = (100 - 100 / (1 + up / dn.replace(0, np.nan))).fillna(50).to_numpy()

# H1 bias (close H1 terakhir yang sudah tutup vs EMA50 H1 dan arahnya)
h1 = df.set_index('time').close.resample('1h').last().dropna()
h1e = h1.ewm(span=50, adjust=False).mean()
bias_h1 = np.where((h1 > h1e) & (h1e > h1e.shift(3)), 1, np.where((h1 < h1e) & (h1e < h1e.shift(3)), -1, 0))
bias_h1 = pd.Series(bias_h1, index=h1.index + pd.Timedelta(hours=1))  # baru diketahui setelah jam tutup
bias = bias_h1.reindex(t, method='ffill').fillna(0).to_numpy().astype(int)

hh48 = pd.Series(h).shift(1).rolling(48).max().to_numpy()
ll48 = pd.Series(l).shift(1).rolling(48).min().to_numpy()
hh20 = pd.Series(h).shift(1).rolling(20).max().to_numpy()
ll20 = pd.Series(l).shift(1).rolling(20).min().to_numpy()
mv12 = c - np.roll(c, 12)

# range sesi (Asia 00:00-07:00, NY pra-buka 12:00-13:30) per hari, diketahui setelah sesi selesai
def session_range(h0, m0, h1_, m1):
    mins = hour * 60 + minute
    m = (mins >= h0 * 60 + m0) & (mins < h1_ * 60 + m1)
    g = pd.DataFrame({'day': day, 'h': np.where(m, h, np.nan), 'l': np.where(m, l, np.nan)})
    agg = g.groupby('day').agg(H=('h', 'max'), L=('l', 'min'))
    return agg.H.reindex(day).to_numpy(), agg.L.reindex(day).to_numpy()

asiaH, asiaL = session_range(0, 0, 7, 0)
nyH, nyL = session_range(12, 0, 13, 30)

def first_per_day(sig, mask):
    """Hanya sinyal pertama per hari di dalam mask."""
    s = np.where(mask, sig, 0)
    out = np.zeros_like(s)
    seen = {}
    for i in np.nonzero(s)[0]:
        if day[i] not in seen:
            seen[day[i]] = 1
            out[i] = s[i]
    return out

# ---------------- katalog sinyal (nilai pada bar i, diketahui saat bar i tutup) ----------------
SIG = {}
SIG['PB_pullback'] = np.where((bias > 0) & (e20 > e50) & (l <= e20) & (c > e20) & (c > o), 1,
                     np.where((bias < 0) & (e20 < e50) & (h >= e20) & (c < e20) & (c < o), -1, 0))
SIG['MO_break48_h1'] = np.where((bias > 0) & (c > hh48), 1, np.where((bias < 0) & (c < ll48), -1, 0))
SIG['MO_break48'] = np.where(c > hh48, 1, np.where(c < ll48, -1, 0))
SIG['MR_bb_rsi'] = np.where((c < ma20 - 2 * sd20) & (rsi < 30), 1, np.where((c > ma20 + 2 * sd20) & (rsi > 70), -1, 0))
SIG['MR_ext12'] = np.where(mv12 < -3 * atr, 1, np.where(mv12 > 3 * atr, -1, 0))
rng = h - l
SIG['CO_bigbar'] = np.where((rng > 2 * atr) & (c > l + 0.8 * rng), 1, np.where((rng > 2 * atr) & (c < h - 0.8 * rng), -1, 0))
SIG['RV_bigbar'] = -SIG['CO_bigbar']
po, pc = np.roll(o, 1), np.roll(c, 1)
bull_eng = (pc < po) & (c > o) & (c > po) & (o < pc)
bear_eng = (pc > po) & (c < o) & (c < po) & (o > pc)
SIG['RV_engulf_ext'] = np.where(bull_eng & (l <= ll20), 1, np.where(bear_eng & (h >= hh20), -1, 0))
ph, pl = np.roll(h, 1), np.roll(l, 1)
inside_prev = (np.roll(h, 1) < np.roll(h, 2)) & (np.roll(l, 1) > np.roll(l, 2))
SIG['IB_break_h1'] = np.where(inside_prev & (bias > 0) & (c > ph), 1, np.where(inside_prev & (bias < 0) & (c < pl), -1, 0))
three_up = (c > o) & (pc > po) & (np.roll(c, 2) > np.roll(o, 2))
three_dn = (c < o) & (pc < po) & (np.roll(c, 2) < np.roll(o, 2))
SIG['CO_three_h1'] = np.where(three_up & (bias > 0), 1, np.where(three_dn & (bias < 0), -1, 0))
lon = (hour >= 7) & (hour < 11)
SIG['ORB_london'] = first_per_day(np.where(c > asiaH, 1, np.where(c < asiaL, -1, 0)), lon)
nyw = ((hour == 13) & (minute >= 30)) | ((hour >= 14) & (hour < 16))
SIG['ORB_ny'] = first_per_day(np.where(c > nyH, 1, np.where(c < nyL, -1, 0)), nyw)
SIG['ORB_london_fade'] = -SIG['ORB_london']
SIG['ORB_ny_fade'] = -SIG['ORB_ny']
rng_rand = np.random.default_rng(0)
SIG['RANDOM'] = np.where(rng_rand.random(N) < 0.02, np.where(rng_rand.random(N) < 0.5, 1, -1), 0)

HOURS = {'all': np.ones(N, bool), 'eu_us': (hour >= 7) & (hour < 18)}
EXITS = list(itertools.product([1.0, 1.5, 2.0], [1.0, 2.0, 3.0]))   # (SL x ATR, RR)
HOLD = 48

def simulate(sig, k, rr):
    """Return arrays: entry index, R bersih."""
    idx, res = [], []
    i, last = 50, N - HOLD - 2
    nz = np.nonzero(sig)[0]
    nz = nz[(nz >= 50) & (nz < last)]
    busy_until = -1
    for i in nz:
        if i <= busy_until or atr[i] <= 0:
            continue
        dirn = sig[i]
        e = o[i + 1]
        sl = k * atr[i]
        tp = rr * sl
        out_r, exit_j = None, i + HOLD
        for j in range(i + 1, i + HOLD + 1):
            if dirn > 0:
                if l[j] <= e - sl:
                    out_r, exit_j = -1.0, j
                    break
                if h[j] >= e + tp:
                    out_r, exit_j = rr, j
                    break
            else:
                if h[j] >= e + sl:
                    out_r, exit_j = -1.0, j
                    break
                if l[j] <= e - tp:
                    out_r, exit_j = rr, j
                    break
        if out_r is None:
            out_r = dirn * (c[i + HOLD] - e) / sl
        out_r -= COST[i + 1] / sl
        idx.append(i)
        res.append(out_r)
        busy_until = exit_j
    return np.array(idx, dtype=int), np.array(res)

if __name__ == '__main__':
    cut = int(N * 0.7)
    print(f"bar: {N}, train s/d {t[cut - 1]} ({cut} bar), test {t[cut]} s/d {t[N - 1]}")
    rows = []
    for name, s in SIG.items():
        for hk, hm in HOURS.items():
            sig = np.where(hm, s, 0)
            for k, rr in EXITS:
                ix, r = simulate(sig, k, rr)
                tr_m, te_m = ix < cut, ix >= cut
                def st(x):
                    n = len(x)
                    if n < 2:
                        return n, np.nan, np.nan, np.nan
                    return n, x.mean(), x.mean() / x.std(ddof=1) * np.sqrt(n), (x > 0).mean()
                a, b = st(r[tr_m]), st(r[te_m])
                rows.append(dict(sig=name, hours=hk, k=k, rr=rr,
                                 n_tr=a[0], R_tr=a[1], t_tr=a[2], win_tr=a[3],
                                 n_te=b[0], R_te=b[1], t_te=b[2], win_te=b[3]))
        print('selesai', name, flush=True)
    res = pd.DataFrame(rows)
    res.to_csv('results.csv', index=False)
    pd.set_option('display.width', 200)
    print(res.sort_values('t_tr', ascending=False).head(25).round(3).to_string())
