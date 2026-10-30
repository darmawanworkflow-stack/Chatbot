"""Riset putaran 3: SMC/ICT, level harga, indikator lain, pola chart, dan variasi aturan keluar.

Aturan (ditetapkan sebelum melihat hasil):
- Penemuan: bar sebelum 2026-08-01. Periode terkunci: 2026-08-01 dst., HANYA dibuka untuk varian yang lolos.
- Lolos penemuan: t >= 3 dan rata-rata R > 0 di 2024, 2025, dan 2026 (Jan-Jul) masing-masing.
- Semua fitur hanya memakai data yang sudah tersedia saat bar sinyal tutup. Entry di open bar berikutnya.
- Biaya sama dengan lab.py. Stop dicek lebih dulu dari target di bar yang sama.
"""
import sys, itertools
import numpy as np
import pandas as pd
import lab, mtf

t, o, h, l, c, atr, N, COST = lab.t, lab.o, lab.h, lab.l, lab.c, lab.atr, lab.N, lab.COST
hour, minute, day = lab.hour, lab.minute, lab.day
vol = pd.read_csv(sys.argv[1]).drop_duplicates('time').tick_volume.to_numpy().astype(float)
assert len(vol) == N
tr60 = mtf.tr60
SESSION = (hour >= 7) & (hour < 18)
LOCK = np.datetime64('2026-08-01')
tt = t.to_numpy().astype('datetime64[ns]')
year = t.dt.year.to_numpy()

def first_per_day(sig):
    out = np.zeros_like(sig)
    seen = set()
    for i in np.nonzero(sig)[0]:
        key = (day[i], sig[i])
        if key not in seen:
            seen.add(key)
            out[i] = sig[i]
    return out

# ---------------- level harian (hari sebelumnya) ----------------
dser = pd.Series(day)
dd = pd.DataFrame({'day': day, 'h': h, 'l': l, 'c': c}).groupby('day').agg(H=('h', 'max'), L=('l', 'min'), C=('c', 'last'))
prev = dd.shift(1)
pdh = prev.H.reindex(day).to_numpy()
pdl = prev.L.reindex(day).to_numpy()
pdc = prev.C.reindex(day).to_numpy()
pivot = (pdh + pdl + pdc) / 3
r1, s1 = 2 * pivot - pdl, 2 * pivot - pdh

# ---------------- swing (fraktal 2 kiri/2 kanan, terkonfirmasi 2 bar kemudian) ----------------
isSH = np.zeros(N, bool)
isSL = np.zeros(N, bool)
for k in range(2, N - 2):
    if h[k] == h[k - 2:k + 3].max():
        isSH[k] = True
    if l[k] == l[k - 2:k + 3].min():
        isSL[k] = True
lastSH = np.full(N, np.nan); prevSH = np.full(N, np.nan); lastSHi = np.full(N, -1)
lastSL = np.full(N, np.nan); prevSL = np.full(N, np.nan); lastSLi = np.full(N, -1)
sh = [np.nan, np.nan, -1]; slw = [np.nan, np.nan, -1]
for i in range(N):
    k = i - 2                      # swing di k baru diketahui saat bar i tutup
    if k >= 2:
        if isSH[k]:
            sh = [h[k], sh[0], k]
        if isSL[k]:
            slw = [l[k], slw[0], k]
    lastSH[i], prevSH[i], lastSHi[i] = sh
    lastSL[i], prevSL[i], lastSLi[i] = slw
struct_up = (lastSH > prevSH) & (lastSL > prevSL)
struct_dn = (lastSH < prevSH) & (lastSL < prevSL)
pc = np.roll(c, 1)

# ---------------- indikator ----------------
ema = lambda x, n: pd.Series(x).ewm(span=n, adjust=False).mean().to_numpy()
macd = ema(c, 12) - ema(c, 26)
macds = pd.Series(macd).ewm(span=9, adjust=False).mean().to_numpy()
# Supertrend(10,3)
atr10 = pd.Series(np.maximum(h - l, np.maximum(abs(h - pc), abs(l - pc)))).ewm(alpha=1 / 10, adjust=False).mean().to_numpy()
mid = (h + l) / 2
ub, lb = mid + 3 * atr10, mid - 3 * atr10
st_dir = np.ones(N, int)
fub, flb = ub.copy(), lb.copy()
for i in range(1, N):
    fub[i] = ub[i] if (ub[i] < fub[i - 1] or c[i - 1] > fub[i - 1]) else fub[i - 1]
    flb[i] = lb[i] if (lb[i] > flb[i - 1] or c[i - 1] < flb[i - 1]) else flb[i - 1]
    st_dir[i] = 1 if c[i] > fub[i - 1] else (-1 if c[i] < flb[i - 1] else st_dir[i - 1])
# VWAP harian
tp = (h + l + c) / 3
g = pd.DataFrame({'day': day, 'pv': tp * vol, 'v': vol})
vwap = (g.groupby('day').pv.cumsum() / g.groupby('day').v.cumsum()).to_numpy()
# ADX(14)
upm, dnm = h - np.roll(h, 1), np.roll(l, 1) - l
pdm = np.where((upm > dnm) & (upm > 0), upm, 0.0)
ndm = np.where((dnm > upm) & (dnm > 0), dnm, 0.0)
sm = lambda x: pd.Series(x).ewm(alpha=1 / 14, adjust=False).mean().to_numpy()
pdi, ndi = 100 * sm(pdm) / atr, 100 * sm(ndm) / atr
adx = sm(100 * abs(pdi - ndi) / np.maximum(pdi + ndi, 1e-9))
# Stochastic(14,3,3)
ll14 = pd.Series(l).rolling(14).min().to_numpy()
hh14 = pd.Series(h).rolling(14).max().to_numpy()
k_ = pd.Series(100 * (c - ll14) / np.maximum(hh14 - ll14, 1e-9)).rolling(3).mean().to_numpy()
d_ = pd.Series(k_).rolling(3).mean().to_numpy()

# ---------------- katalog sinyal ----------------
S = {}
asiaH, asiaL = lab.asiaH, lab.asiaL
w = (hour >= 7) & (hour < 12)
S['SMC_sweep_asia'] = first_per_day(np.where(w & (h > asiaH) & (c < asiaH), -1, np.where(w & (l < asiaL) & (c > asiaL), 1, 0)))
S['SMC_sweep_pdhl'] = first_per_day(np.where(SESSION & (h > pdh) & (c < pdh), -1, np.where(SESSION & (l < pdl) & (c > pdl), 1, 0)))
# FVG: gap bullish di bar k bila l[k] > h[k-2]; entry saat harga kembali ke gap & candle bullish, searah tren H1, umur <= 24 bar
fvg_sig = np.zeros(N, int)
bt = bb = st_ = sb = np.nan; bage = sage = 10 ** 9
for i in range(2, N):
    bage += 1; sage += 1
    if l[i - 1] > h[i - 3] if i >= 3 else False:
        bt, bb, bage = l[i - 1], h[i - 3], 1
    if h[i - 1] < l[i - 3] if i >= 3 else False:
        sb, st_, sage = h[i - 1], l[i - 3], 1
    if bage <= 24 and tr60[i] > 0 and l[i] <= bt and c[i] >= bb and c[i] > o[i]:
        fvg_sig[i] = 1; bage = 10 ** 9
    elif sage <= 24 and tr60[i] < 0 and h[i] >= sb and c[i] <= st_ and c[i] < o[i]:
        fvg_sig[i] = -1; sage = 10 ** 9
S['SMC_fvg_retrace'] = fvg_sig
cross_up_sh = (c > lastSH) & (pc <= lastSH)
cross_dn_sl = (c < lastSL) & (pc >= lastSL)
S['SMC_BOS_lanjut'] = np.where(struct_up & cross_up_sh, 1, np.where(struct_dn & cross_dn_sl, -1, 0))
S['SMC_CHoCH_balik'] = np.where(struct_dn & cross_up_sh, 1, np.where(struct_up & cross_dn_sl, -1, 0))
S['LVL_pivot_pantul'] = np.where((l <= s1) & (c > s1) & (c > o), 1, np.where((h >= r1) & (c < r1) & (c < o), -1, 0))
L50 = np.round(c / 50) * 50
S['LVL_angka_bulat50'] = np.where((l <= L50) & (c > L50) & (o > L50), 1, np.where((h >= L50) & (c < L50) & (o < L50), -1, 0))
S['LVL_break_pdhl'] = first_per_day(np.where(SESSION & (c > pdh) & (pc <= pdh), 1, np.where(SESSION & (c < pdl) & (pc >= pdl), -1, 0)))
hh48 = pd.Series(h).rolling(48).max().to_numpy(); ll48 = pd.Series(l).rolling(48).min().to_numpy()
ihh = pd.Series(h).rolling(48).apply(np.argmax, raw=True).to_numpy()
ill = pd.Series(l).rolling(48).apply(np.argmin, raw=True).to_numpy()
retr_up = (hh48 - c) / np.maximum(hh48 - ll48, 1e-9)
S['LVL_fib_50_618'] = np.where((tr60 > 0) & (ihh > ill) & (retr_up >= 0.5) & (retr_up <= 0.618) & (c > o), 1,
                      np.where((tr60 < 0) & (ill > ihh) & (1 - retr_up >= 0.5) & (1 - retr_up <= 0.618) & (c < o), -1, 0))
S['IND_macd_cross_h1'] = np.where((tr60 > 0) & (macd > macds) & (np.roll(macd, 1) <= np.roll(macds, 1)), 1,
                         np.where((tr60 < 0) & (macd < macds) & (np.roll(macd, 1) >= np.roll(macds, 1)), -1, 0))
# divergence: low baru 24 bar tapi MACD lebih tinggi dari saat low 24-48 bar lalu
lo24 = pd.Series(l).rolling(24).min().to_numpy(); hi24 = pd.Series(h).rolling(24).max().to_numpy()
prevlo = pd.Series(l).shift(24).rolling(24).min().to_numpy(); prevhi = pd.Series(h).shift(24).rolling(24).max().to_numpy()
macd_prevlo = pd.Series(macd).shift(24).rolling(24).min().to_numpy(); macd_prevhi = pd.Series(macd).shift(24).rolling(24).max().to_numpy()
S['IND_macd_divergence'] = np.where((l <= lo24) & (l < prevlo) & (macd > macd_prevlo) & (c > o), 1,
                           np.where((h >= hi24) & (h > prevhi) & (macd < macd_prevhi) & (c < o), -1, 0))
S['IND_supertrend_flip'] = np.where((st_dir == 1) & (np.roll(st_dir, 1) == -1), 1, np.where((st_dir == -1) & (np.roll(st_dir, 1) == 1), -1, 0))
S['IND_vwap_pantul_h1'] = np.where((tr60 > 0) & (l <= vwap) & (c > vwap) & (c > o), 1, np.where((tr60 < 0) & (h >= vwap) & (c < vwap) & (c < o), -1, 0))
brk12 = mtf.TRIG['break12']
S['IND_adx_break'] = np.where((adx > 25) & (pdi > ndi) & (brk12 > 0), 1, np.where((adx > 25) & (ndi > pdi) & (brk12 < 0), -1, 0))
S['IND_stoch_h1'] = np.where((tr60 > 0) & (k_ > d_) & (np.roll(k_, 1) <= np.roll(d_, 1)) & (k_ < 25), 1,
                    np.where((tr60 < 0) & (k_ < d_) & (np.roll(k_, 1) >= np.roll(d_, 1)) & (k_ > 75), -1, 0))
# double bottom/top: dua swing low setara (<= 0.3 ATR) lalu close menembus swing high di antaranya
S['PAT_double_btm_top'] = np.where((abs(lastSL - prevSL) <= 0.3 * atr) & cross_up_sh & (lastSHi > lastSLi - 48), 1,
                          np.where((abs(lastSH - prevSH) <= 0.3 * atr) & cross_dn_sl & (lastSLi > lastSHi - 48), -1, 0))
S['RANDOM'] = lab.SIG['RANDOM']
for k_name in list(S):
    if not k_name.startswith('SMC_sweep_asia'):
        S[k_name] = np.where(SESSION, S[k_name], 0)
    S[k_name][:300] = 0

# ---------------- simulasi dengan berbagai aturan keluar ----------------
HOLD = 48
swing_lo = pd.Series(l).rolling(10).min().to_numpy()
swing_hi = pd.Series(h).rolling(10).max().to_numpy()
EXITS = ['ATR_2R', 'ATR_3R', 'SWING_2R', 'ATR_BE_3R', 'ATR_trail', 'ATR_partial']

def simulate(sig, mode):
    idx, res = [], []
    busy = -1
    for i in np.nonzero(sig)[0]:
        if i <= busy or i >= N - HOLD - 2 or atr[i] <= 0:
            continue
        d = sig[i]; e = o[i + 1]; a = atr[i]
        if mode == 'SWING_2R':
            risk = (e - (swing_lo[i] - 0.1 * a)) if d > 0 else ((swing_hi[i] + 0.1 * a) - e)
            risk = min(max(risk, 0.5 * a), 4 * a)
        else:
            risk = 1.5 * a
        rr = {'ATR_2R': 2, 'ATR_3R': 3, 'SWING_2R': 2, 'ATR_BE_3R': 3, 'ATR_trail': None, 'ATR_partial': 3}[mode]
        stop = e - d * risk
        best = e
        part = 0.0          # R yang sudah diamankan (partial)
        frac = 1.0          # porsi posisi tersisa
        out, ex = None, i + HOLD
        for j in range(i + 1, i + HOLD + 1):
            adv = l[j] if d > 0 else h[j]
            fav = h[j] if d > 0 else l[j]
            if (adv <= stop) if d > 0 else (adv >= stop):
                out = part + frac * d * (stop - e) / risk; ex = j; break
            if mode == 'ATR_partial' and frac == 1.0 and ((fav >= e + risk) if d > 0 else (fav <= e - risk)):
                part, frac, stop = 0.5, 0.5, e
            if rr is not None and ((fav >= e + rr * risk) if d > 0 else (fav <= e - rr * risk)):
                out = part + frac * rr; ex = j; break
            if mode == 'ATR_BE_3R' and ((fav >= e + risk) if d > 0 else (fav <= e - risk)):
                stop = max(stop, e) if d > 0 else min(stop, e)
            if mode == 'ATR_trail':
                best = max(best, h[j]) if d > 0 else min(best, l[j])
                stop = max(stop, best - 2 * a) if d > 0 else min(stop, best + 2 * a)
        if out is None:
            out = part + frac * d * (c[i + HOLD] - e) / risk
        idx.append(i); res.append(out - COST[i + 1] / risk)
        busy = ex
    return np.array(idx, int), np.array(res)

def tstat(x):
    return x.mean() / x.std(ddof=1) * np.sqrt(len(x)) if len(x) > 2 else np.nan

if __name__ == '__main__':
    disc = tt < LOCK
    rows = []
    for name, sig in S.items():
        for mode in EXITS:
            ix, r = simulate(sig, mode)
            m = disc[ix]
            rd, yrs = r[m], year[ix][m]
            row = dict(sinyal=name, exit=mode, n=len(rd), R=rd.mean() if len(rd) else np.nan, t=tstat(rd),
                       win=(rd > 0).mean() if len(rd) else np.nan)
            for y in (2024, 2025, 2026):
                ry = rd[yrs == y]
                row[f'R{y}'] = ry.mean() if len(ry) else np.nan
            rows.append(row)
        print('selesai', name, flush=True)
    res = pd.DataFrame(rows)
    res['lolos'] = (res.t >= 3) & (res.R2024 > 0) & (res.R2025 > 0) & (res.R2026 > 0)
    res.to_csv('results_round3.csv', index=False)
    pd.set_option('display.width', 220)
    print(f"\n{len(res)} varian di periode penemuan (s/d Jul 2026). Lolos: {res.lolos.sum()}")
    print(res.sort_values('t', ascending=False).head(25).round(3).to_string())
    print('\nRata-rata per aturan keluar:')
    print(res.groupby('exit')[['R', 't']].mean().round(3).to_string())
    print('\nTerbaik per sinyal (t tertinggi):')
    print(res.loc[res.groupby('sinyal').t.idxmax(), ['sinyal', 'exit', 'n', 'R', 't', 'R2024', 'R2025', 'R2026']]
          .sort_values('t', ascending=False).round(3).to_string())
