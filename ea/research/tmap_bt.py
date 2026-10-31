"""Backtest kasar TechnicalMap (M5 XAUUSD).

Meniru indikator: tren M5/M15/H1/H4, pola candle, level S/R (swing H1/H4 fraktal, PDH/PDL,
pivot P/R1/S1, high/low Asia, angka bulat $50) dengan waktu-berlaku (tanpa melihat masa depan),
panah konfluensi, skor kesimpulan, dan fase sinkronisasi.
Perbedaan kecil dengan indikator: ATR H1 di sini Wilder, zona tidak diklaster (kekuatan = jumlah
bobot level dalam toleransi).
"""
import sys
import numpy as np
import pandas as pd
import lab, mtf

t, o, h, l, c, N = lab.t, lab.o, lab.h, lab.l, lab.c, lab.N
idx = pd.DatetimeIndex(t)
tt = idx.values.astype('datetime64[s]').astype(np.int64)
year = idx.year.to_numpy()
hour = idx.hour.to_numpy()
base = mtf.base

# ---------- tren tiap TF ----------
e20, e50 = lab.e20, lab.e50
tr5 = np.where((c > e50) & (e20 > e50), 1, np.where((c < e50) & (e20 < e50), -1, 0))
tr15, tr60, tr240 = mtf.tr15, mtf.tr60, mtf.tr240
rsi5 = lab.rsi

# ATR H1 (bar H1 tutup)
h1 = base.resample('1h').agg({'open': 'first', 'high': 'max', 'low': 'min', 'close': 'last'}).dropna()
trh = np.maximum(h1.high - h1.low, np.maximum(abs(h1.high - h1.close.shift()), abs(h1.low - h1.close.shift())))
atrh1 = trh.ewm(alpha=1 / 14, adjust=False).mean()
atrh1.index = atrh1.index + pd.Timedelta(hours=1)
atrH1 = atrh1.reindex(idx + pd.Timedelta(minutes=5), method='ffill').bfill().to_numpy()

# ---------- pola candle (sama dengan Pattern() di indikator) ----------
po, pc, ph, pl = np.roll(o, 1), np.roll(c, 1), np.roll(h, 1), np.roll(l, 1)
o2, c2, h2, l2 = np.roll(o, 2), np.roll(c, 2), np.roll(h, 2), np.roll(l, 2)
body = abs(c - o); rng = np.maximum(h - l, 1e-9)
up = h - np.maximum(o, c); lo = np.minimum(o, c) - l
pb = abs(pc - po); b2 = abs(c2 - o2)
pat = np.zeros(N, int)
eng_b = (pc < po) & (c > o) & (c >= po) & (o <= pc) & (body > pb)
eng_s = (pc > po) & (c < o) & (c <= po) & (o >= pc) & (body > pb)
ms = (c2 < o2) & (b2 > 0.6 * (h2 - l2)) & (abs(pc - po) < 0.3 * b2) & (c > o) & (c > (o2 + c2) / 2)
es = (c2 > o2) & (b2 > 0.6 * (h2 - l2)) & (abs(pc - po) < 0.3 * b2) & (c < o) & (c < (o2 + c2) / 2)
ham = (lo >= 2 * body) & (up <= body) & (c >= l + 0.66 * rng)
ss = (up >= 2 * body) & (lo <= body) & (c <= h - 0.66 * rng)
pat = np.select([eng_b, eng_s, ms & ~eng_b & ~eng_s, es & ~eng_b & ~eng_s,
                 ham & ~eng_b & ~eng_s & ~ms & ~es, ss & ~eng_b & ~eng_s & ~ms & ~es], [1, -1, 1, -1, 1, -1], 0)

# ---------- level dengan waktu berlaku ----------
def swings(rule, hours, lookback_h, w):
    b = base.resample(rule).agg({'high': 'max', 'low': 'min'}).dropna()
    H, L, T = b.high.to_numpy(), b.low.to_numpy(), b.index.values.astype('datetime64[s]').astype(np.int64)
    out = []
    for k in range(2, len(b) - 2):
        known = T[k + 2] + hours * 3600
        if H[k] >= H[k - 1] and H[k] >= H[k - 2] and H[k] > H[k + 1] and H[k] > H[k + 2]:
            out.append((known, known + lookback_h * 3600, H[k], w))
        if L[k] <= L[k - 1] and L[k] <= L[k - 2] and L[k] < L[k + 1] and L[k] < L[k + 2]:
            out.append((known, known + lookback_h * 3600, L[k], w))
    return out

lv = swings('1h', 1, 240, 1) + swings('4h', 4, 180 * 4, 2)
dd = base.resample('1D').agg({'high': 'max', 'low': 'min', 'close': 'last'}).dropna()
days = dd.index.values.astype('datetime64[s]').astype(np.int64)
for k in range(1, len(dd)):
    t0 = days[k]; H, L, C = dd.high.iloc[k - 1], dd.low.iloc[k - 1], dd.close.iloc[k - 1]
    P = (H + L + C) / 3
    for p, w in ((H, 2), (L, 2), (P, 1), (2 * P - L, 1), (2 * P - H, 1)):
        lv.append((t0, t0 + 86400, p, w))
    a = base.loc[str(dd.index[k].date())].between_time('00:00', '06:55')
    if len(a) > 30:
        lv.append((t0 + 7 * 3600, t0 + 86400, a.high.max(), 1))
        lv.append((t0 + 7 * 3600, t0 + 86400, a.low.min(), 1))
lv = np.array(sorted(lv))
LS, LE, LP, LW = lv[:, 0], lv[:, 1], lv[:, 2], lv[:, 3]
MAXSPAN = 180 * 4 * 3600

def strength(p, tq, tol, side=0):
    """Jumlah bobot level aktif di sekitar p; side=+1 hanya level <= p (support), -1 hanya >= p."""
    a = np.searchsorted(LS, tq - MAXSPAN); b = np.searchsorted(LS, tq, side='right')
    m = (LE[a:b] > tq) & (np.abs(LP[a:b] - p) <= tol)
    if side > 0:
        m &= LP[a:b] <= p
    elif side < 0:
        m &= LP[a:b] >= p
    s = LW[a:b][m].sum()
    rn = np.round(p / 50) * 50
    if abs(rn - p) <= tol and (side == 0 or (side > 0 and rn <= p) or (side < 0 and rn >= p)):
        s += 1
    return s

tclose = tt + 300
tol = 0.30 * atrH1

# ---------- A. panah konfluensi ----------
arrow = np.zeros(N, int)
for i in np.nonzero(pat)[0]:
    if i < 300:
        continue
    d = pat[i]
    if strength(l[i] if d > 0 else h[i], tclose[i], tol[i]) >= 2 and tr60[i] != -d:
        arrow[i] = d
print(f"Panah konfluensi: {np.count_nonzero(arrow)} dari {np.count_nonzero(pat)} pola ({hour[arrow != 0].min()}-{hour[arrow != 0].max()} jam)")
pd.set_option('display.width', 200)
def by_year(ix, r):
    s = pd.Series(r, index=year[ix])
    return s.groupby(level=0).agg(['count', 'mean']).round(3).T.to_string()
for k, rr in ((1.5, 2.0), (1.5, 3.0)):
    for lbl, sig in (('konfluensi', arrow), ('pola saja', pat), ('acak', lab.SIG['RANDOM'])):
        ix, r = lab.simulate(sig, k, rr)
        print(f"  SL {k} ATR, TP {rr:.0f}R  {lbl:11s} n={len(r):5d} win={np.mean(r > 0):.2f} rata2={r.mean():+.3f}R")
ix, r = lab.simulate(arrow, 1.5, 2.0)
print("  konfluensi 2R per tahun:\n" + by_year(ix, r))

# ---------- B. skor kesimpulan -> arah candle berikutnya ----------
S = np.arange(300, N - 13, 3)                                # sampel tiap 15 menit
score = tr15[S] + tr60[S] + tr240[S] + pat[S]
near_sup = np.array([strength(c[i], tclose[i], tol[i], side=+1) > 0 for i in S])
near_res = np.array([strength(c[i], tclose[i], tol[i], side=-1) > 0 for i in S])
score = score + near_sup - near_res + (rsi5[S] < 30) - (rsi5[S] > 70)
bias = np.where(score >= 2, 1, np.where(score <= -2, -1, 0))
print("\nSkor kesimpulan -> arah ke depan (hanya saat CONDONG NAIK/TURUN):")
for n_ahead, lbl in ((1, '1 candle (5 mnt)'), (3, '3 candle (15 mnt)'), (12, '12 candle (1 jam)')):
    mv = c[S + n_ahead] - c[S]
    m = bias != 0
    hit = (np.sign(mv[m]) == bias[m]).mean()
    gain = (bias[m] * mv[m]).mean()
    print(f"  {lbl:18s} tepat arah {hit:.1%} | rata2 gerak searah ${gain:+.2f} (biaya ~$0.25) | n={m.sum()}")

# ---------- C. fase sinkronisasi ----------
big = np.where((tr240 != 0) & (tr240 == tr60), tr240, 0)
phase = np.select([(big != 0) & (tr15 == big) & (tr5 == big), (big != 0) & (tr15 == -big), (big != 0) & (tr15 == 0),
                   (big != 0) & (tr15 == big), (tr240 != 0) & (tr60 == -tr240)],
                  ['selaras penuh', 'pullback M15', 'pullback melemah', 'M15 searah, M5 koreksi', 'konflik H4/H1'], 'tanpa tren besar')
print("\nFase sinkronisasi -> gerak 1 jam ke depan searah tren besar, dan pemicu pola M5 searah (SL 1.5 ATR, TP 2R):")
for ph in ['selaras penuh', 'pullback M15', 'pullback melemah', 'M15 searah, M5 koreksi', 'konflik H4/H1', 'tanpa tren besar']:
    m = phase[S] == ph
    dirn = big[S][m]
    mv = (c[S + 12] - c[S])[m]
    fwd = (dirn * mv)[dirn != 0].mean() if (dirn != 0).any() else np.nan
    trig = np.where((phase == ph) & (big != 0) & (pat == big), pat, 0)
    ix, r = lab.simulate(trig, 1.5, 2.0)
    print(f"  {ph:24s} {m.mean():5.1%} waktu | gerak 1 jam searah tren besar ${fwd:+.2f} | "
          f"pola M5 searah: n={len(r):4d} rata2={r.mean() if len(r) else float('nan'):+.3f}R")
