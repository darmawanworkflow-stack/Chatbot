"""Putaran 4: metode populer dari forum/komunitas.

Aturan sama dengan putaran 3 (ditetapkan sebelum melihat hasil):
- Penemuan: sebelum 2026-08-01. Periode terkunci Agu-Okt 2026 hanya dibuka untuk varian yang lolos.
- Lolos: t >= 3 dan rata-rata R > 0 di 2024, 2025, 2026 (Jan-Jul).
Jam New York dihitung dengan DST AS (server = GMT+0).
"""
import sys
import numpy as np
import pandas as pd
import lab, round3

t, o, h, l, c, atr, N, COST = lab.t, lab.o, lab.h, lab.l, lab.c, lab.atr, lab.N, lab.COST
idx = pd.DatetimeIndex(t)
year = idx.year.to_numpy()
LOCK = pd.Timestamp('2026-08-01')
disc = (idx < LOCK)

# ---------- jam New York (DST AS: Minggu ke-2 Maret s/d Minggu ke-1 November) ----------
def us_dst(ts):
    y = ts.year
    mar = pd.Timestamp(y, 3, 8) + pd.Timedelta(days=(6 - pd.Timestamp(y, 3, 8).dayofweek) % 7)
    nov = pd.Timestamp(y, 11, 1) + pd.Timedelta(days=(6 - pd.Timestamp(y, 11, 1).dayofweek) % 7)
    return mar + pd.Timedelta(hours=7) <= ts < nov + pd.Timedelta(hours=6)
days = pd.Series(idx.normalize()).unique()
dst_day = {d: us_dst(d + pd.Timedelta(hours=12)) for d in days}
off = np.array([4 if dst_day[d] else 5 for d in idx.normalize()])
ny = idx - pd.to_timedelta(off, unit='h')
nyh = ny.hour.to_numpy() + ny.minute.to_numpy() / 60.0

def stats(ix, r):
    m = disc[ix]
    rd, yr = r[m], year[ix][m]
    out = dict(n=len(rd), R=rd.mean() if len(rd) else np.nan,
               t=rd.mean() / rd.std(ddof=1) * np.sqrt(len(rd)) if len(rd) > 2 else np.nan,
               win=(rd > 0).mean() if len(rd) else np.nan)
    for y in (2024, 2025, 2026):
        out[f'R{y}'] = rd[yr == y].mean() if (yr == y).any() else np.nan
    return out

rows = []
def add(name, ix, r):
    rows.append(dict(metode=name, **stats(ix, r)))

# ---------- 1. ICT Silver Bullet ----------
# FVG terbentuk di jendela NY; syarat sweep likuiditas: dalam 12 bar terakhir harga menembus low/high 48 bar sebelumnya.
# Entry saat harga kembali ke FVG (candle tutup searah), SL di luar swing 12 bar, TP 2R.
ll48p = pd.Series(l).shift(12).rolling(48).min().to_numpy()
hh48p = pd.Series(h).shift(12).rolling(48).max().to_numpy()
lo12 = pd.Series(l).rolling(12).min().to_numpy()
hi12 = pd.Series(h).rolling(12).max().to_numpy()
swept_low = lo12 < ll48p
swept_high = hi12 > hh48p

def silver_bullet(win_start, win_end, need_sweep):
    sig = np.zeros(N, int); risk = np.zeros(N)
    bt = bb = st = sb = np.nan; bage = sage = 10 ** 9
    for i in range(3, N):
        bage += 1; sage += 1
        inwin_prev = win_start <= nyh[i - 1] < win_end
        if inwin_prev and l[i - 1] > h[i - 3]:
            bt, bb, bage = l[i - 1], h[i - 3], 1
        if inwin_prev and h[i - 1] < l[i - 3]:
            sb, st, sage = h[i - 1], l[i - 3], 1
        if not (win_start <= nyh[i] < win_end + 0.5):
            continue
        if bage <= 12 and l[i] <= bt and c[i] >= bb and c[i] > o[i] and (swept_low[i] or not need_sweep):
            sig[i] = 1; risk[i] = max(o[i + 1] - (lo12[i] - 0.1 * atr[i]), 0.5 * atr[i]) if i + 1 < N else atr[i]; bage = 10 ** 9
        elif sage <= 12 and h[i] >= sb and c[i] <= st and c[i] < o[i] and (swept_high[i] or not need_sweep):
            sig[i] = -1; risk[i] = max((hi12[i] + 0.1 * atr[i]) - o[i + 1], 0.5 * atr[i]) if i + 1 < N else atr[i]; sage = 10 ** 9
    return sig, risk

def sim_risk(sig, risk, rr, hold=48):
    idxs, res, busy = [], [], -1
    for i in np.nonzero(sig)[0]:
        if i <= busy or i >= N - hold - 2:
            continue
        d, e, R = sig[i], o[i + 1], min(risk[i], 4 * atr[i])
        out, ex = None, i + hold
        for j in range(i + 1, i + hold + 1):
            if (l[j] <= e - R) if d > 0 else (h[j] >= e + R):
                out, ex = -1.0, j; break
            if (h[j] >= e + rr * R) if d > 0 else (l[j] <= e - rr * R):
                out, ex = rr, j; break
        if out is None:
            out = d * (c[i + hold] - e) / R
        idxs.append(i); res.append(out - COST[i + 1] / R); busy = ex
    return np.array(idxs, int), np.array(res)

for nm, (a, b) in (('London 03-04 ET', (3, 4)), ('NY AM 10-11 ET', (10, 11)), ('NY PM 14-15 ET', (14, 15))):
    for sw in (True, False):
        s, rk = silver_bullet(a, b, sw)
        ix, r = sim_risk(s, rk, 2.0)
        add(f"SilverBullet {nm}{' + sweep' if sw else ''}", ix, r)

# ---------- 2. Turtle Soup (Raschke): low 20 bar baru, low 20 bar sebelumnya >= 4 bar lalu, close kembali di atas ----------
ll20 = pd.Series(l).shift(1).rolling(20).min().to_numpy()
hh20 = pd.Series(h).shift(1).rolling(20).max().to_numpy()
age_lo = pd.Series(l).shift(1).rolling(20).apply(lambda x: 19 - np.argmin(x), raw=True).to_numpy()
age_hi = pd.Series(h).shift(1).rolling(20).apply(lambda x: 19 - np.argmax(x), raw=True).to_numpy()
ts_sig = np.where((l < ll20) & (age_lo >= 3) & (c > ll20), 1, np.where((h > hh20) & (age_hi >= 3) & (c < hh20), -1, 0))
ts_sig = np.where(round3.SESSION, ts_sig, 0)
for k, rr in ((1.0, 1.0), (1.5, 2.0)):
    ix, r = lab.simulate(ts_sig, k, rr)
    add(f"TurtleSoup M5 SL{k} TP{rr:.0f}R", ix, r)

# ---------- 3. Connors RSI(2) di H1 (close > EMA200 & RSI2 < 5 -> buy; keluar close > EMA5, maks 24 bar) ----------
H1 = round3.mtf.base.resample('1h').agg({'open': 'first', 'high': 'max', 'low': 'min', 'close': 'last'}).dropna()
def rsi_n(x, n):
    d = x.diff(); u = d.clip(lower=0).ewm(alpha=1 / n, adjust=False).mean(); v = (-d).clip(lower=0).ewm(alpha=1 / n, adjust=False).mean()
    return 100 - 100 / (1 + u / v.replace(0, np.nan))
def connors(B, label, maxbars, cost):
    cl, op = B.close.to_numpy(), B.open.to_numpy()
    r2 = rsi_n(B.close, 2).to_numpy(); e200 = B.close.ewm(span=200, adjust=False).mean().to_numpy()
    e5 = B.close.ewm(span=5, adjust=False).mean().to_numpy()
    tr_ = (B.high - B.low).ewm(alpha=1 / 14, adjust=False).mean().to_numpy()
    yrs = B.index.year.to_numpy(); dmask = B.index < LOCK
    res, yy, busy = [], [], -1
    for i in range(201, len(B) - maxbars - 2):
        if i <= busy:
            continue
        d = 1 if (cl[i] > e200[i] and r2[i] < 5) else (-1 if (cl[i] < e200[i] and r2[i] > 95) else 0)
        if d == 0 or not dmask[i]:
            continue
        e = op[i + 1]; R = 1.5 * tr_[i]
        ex = i + maxbars
        for j in range(i + 1, i + maxbars + 1):
            if (d > 0 and cl[j] > e5[j]) or (d < 0 and cl[j] < e5[j]):
                ex = j; break
        res.append((d * (cl[ex] - e) - cost) / R); yy.append(yrs[i]); busy = ex
    res, yy = np.array(res), np.array(yy)
    rows.append(dict(metode=label, n=len(res), R=res.mean(), t=res.mean() / res.std(ddof=1) * np.sqrt(len(res)),
                     win=(res > 0).mean(), **{f'R{y}': res[yy == y].mean() for y in (2024, 2025, 2026)}))
connors(H1, 'Connors RSI2 H1 (R = 1.5 ATR H1)', 24, 0.25)
H4 = round3.mtf.base.resample('4h').agg({'open': 'first', 'high': 'max', 'low': 'min', 'close': 'last'}).dropna()
connors(H4, 'Connors RSI2 H4 (R = 1.5 ATR H4)', 12, 0.25)

# ---------- 4. NR7 / inside day: hari ini range terkecil 7 hari -> besok buy stop di high / sell stop di low, tutup akhir hari ----------
D = round3.mtf.base.resample('1D').agg({'open': 'first', 'high': 'max', 'low': 'min', 'close': 'last'}).dropna()
rngD = (D.high - D.low)
nr7 = (rngD == rngD.rolling(7).min()).to_numpy()
inside = ((D.high < D.high.shift()) & (D.low > D.low.shift())).to_numpy()
def daily_break(mask, label):
    res, yy = [], []
    dl = D.index
    for k in range(7, len(D) - 1):
        if not mask[k] or dl[k + 1] >= LOCK:
            continue
        H_, L_ = D.high.iloc[k], D.low.iloc[k]; R = H_ - L_
        day_bars = base_slice = round3.mtf.base.loc[str(dl[k + 1].date())]
        hit = None
        for _, b in day_bars.iterrows():
            up, dn = b.high > H_, b.low < L_
            if up and dn:
                hit = 0; break                       # dua sisi di bar yang sama: anggap batal
            if up:
                hit = (day_bars.close.iloc[-1] - H_ - 0.25) / R; break
            if dn:
                hit = (L_ - day_bars.close.iloc[-1] - 0.25) / R; break
        if hit is not None:
            res.append(hit); yy.append(dl[k].year)
    res, yy = np.array(res), np.array(yy)
    rows.append(dict(metode=label, n=len(res), R=res.mean(), t=res.mean() / res.std(ddof=1) * np.sqrt(len(res)),
                     win=(res > 0).mean(), **{f'R{y}': res[yy == y].mean() if (yy == y).any() else np.nan for y in (2024, 2025, 2026)}))
daily_break(nr7, 'NR7 breakout harian (R = range hari NR7)')
daily_break(inside, 'Inside day breakout (R = range inside day)')

# ---------- 5. Momentum harian (time-series momentum): arah return 20 hari -> pegang 1 hari ----------
ret20 = D.close - D.close.shift(20)
res, yy = [], []
atrD = (D.high - D.low).rolling(14).mean()
for k in range(21, len(D) - 1):
    if D.index[k + 1] >= LOCK or np.isnan(ret20.iloc[k]):
        continue
    d = np.sign(ret20.iloc[k])
    res.append((d * (D.close.iloc[k + 1] - D.close.iloc[k]) - 0.25) / atrD.iloc[k]); yy.append(D.index[k].year)
res, yy = np.array(res), np.array(yy)
rows.append(dict(metode='Momentum harian 20 hari (R = ATR harian)', n=len(res), R=res.mean(),
                 t=res.mean() / res.std(ddof=1) * np.sqrt(len(res)), win=(res > 0).mean(),
                 **{f'R{y}': res[yy == y].mean() for y in (2024, 2025, 2026)}))

# ---------- 6. London close reversal: lawan arah gerak 08:00-11:00 ET, masuk 11:00 ET, tahan 2 jam ----------
def time_trade(entry_h, ref_h, hold_bars, fade, label):
    res, yy = [], []
    ii = np.nonzero((nyh == entry_h) & disc)[0]
    for i in ii:
        j0 = i - int((entry_h - ref_h) * 12)
        if j0 < 0 or i + hold_bars >= N or idx[i].normalize() != idx[j0].normalize():
            continue
        mv = c[i - 1] - o[j0]
        if abs(mv) < 0.5 * atr[i] * 12 ** 0.5:
            continue
        d = -np.sign(mv) if fade else np.sign(mv)
        R = 1.5 * atr[i] * 12 ** 0.5
        res.append((d * (c[i + hold_bars] - o[i]) - COST[i]) / R); yy.append(year[i])
    res, yy = np.array(res), np.array(yy)
    rows.append(dict(metode=label, n=len(res), R=res.mean(), t=res.mean() / res.std(ddof=1) * np.sqrt(len(res)),
                     win=(res > 0).mean(), **{f'R{y}': res[yy == y].mean() for y in (2024, 2025, 2026)}))
time_trade(11.0, 8.0, 24, True, 'London close reversal (fade 08-11 ET, tahan 2 jam)')
time_trade(11.0, 8.0, 24, False, 'London close lanjut (ikut 08-11 ET, tahan 2 jam)')

# ---------- 7. NY opening range 15 menit (09:30-09:45 ET), breakout candle tutup, SL sisi lain, TP 2R ----------
sig = np.zeros(N, int); risk = np.zeros(N)
day_key = idx.normalize()
for d0 in pd.unique(day_key):
    m = np.nonzero(day_key == d0)[0]
    orb = m[(nyh[m] >= 9.5) & (nyh[m] < 9.75)]
    if len(orb) < 3:
        continue
    H_, L_ = h[orb].max(), l[orb].min()
    for i in m[(nyh[m] >= 9.75) & (nyh[m] < 12)]:
        if c[i] > H_:
            sig[i] = 1; risk[i] = max(o[i + 1] - L_, 0.5 * atr[i]) if i + 1 < N else atr[i]; break
        if c[i] < L_:
            sig[i] = -1; risk[i] = max(H_ - o[i + 1], 0.5 * atr[i]) if i + 1 < N else atr[i]; break
for rr in (1.0, 2.0):
    ix, r = sim_risk(sig, risk, rr, hold=60)
    add(f'NY opening range 15 mnt, TP {rr:.0f}R', ix, r)

res = pd.DataFrame(rows)
res['lolos'] = (res.t >= 3) & (res.R2024 > 0) & (res.R2025 > 0) & (res.R2026 > 0)
res.to_csv('results_round4.csv', index=False)
pd.set_option('display.width', 220)
print(res.sort_values('t', ascending=False).round(3).to_string(index=False))
print('\nLolos:', int(res.lolos.sum()))
