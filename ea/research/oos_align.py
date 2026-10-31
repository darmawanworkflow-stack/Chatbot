"""Uji di luar sampel 2004-2023 (data Kaggle, dikonversi ke GMT+0) untuk aturan yang SUDAH dikunci:
1. Fase sinkronisasi: gerak 1 jam ke depan searah tren besar (sama dengan tmap_phase.py), per tahun.
2. AL: masuk saat baru selaras penuh, keluar saat M15 berbalik, SL 2 ATR, jam 07-18 (sama dengan tmap_align.py).
Kriteria lolos AL (ditetapkan sebelum melihat hasil): rata-rata R > 0, t >= 2, positif di >= 12 dari 20 tahun."""
import numpy as np, pandas as pd
exec(open('tmap_bt.py').read().split('# ---------- A. panah konfluensi')[0])
atr = lab.atr; COST = lab.COST
big = np.where((tr240 != 0) & (tr240 == tr60), tr240, 0)
full = (big != 0) & (tr15 == big) & (tr5 == big)
phase = np.select([full, (big != 0) & (tr15 == -big), (big != 0) & (tr15 == 0), (big != 0) & (tr15 == big)],
                  ['selaras penuh', 'pullback M15', 'pullback melemah', 'M15 searah M5 koreksi'], '-')
S = np.arange(600, N - 13, 12)
mv = (c[S + 12] - c[S]) * big[S] / atrH1[S]           # dalam satuan ATR H1 (harga 2004 vs 2023 berbeda jauh)
df = pd.DataFrame({'fase': phase[S], 'tahun': year[S], 'gerak': mv})
df = df[df.fase != '-']
a = df.groupby('fase').gerak.agg(['count', 'mean', 'std']); a['t'] = a['mean'] / a['std'] * np.sqrt(a['count'])
a['tahun_positif'] = df.groupby(['fase', 'tahun']).gerak.mean().gt(0).groupby(level=0).sum()
pd.set_option('display.width', 220)
print("1) Gerak 1 jam ke depan searah tren besar, dalam ATR H1 (2004-2023):")
print(a.round(3).to_string())
print("   per tahun (selaras penuh):", df[df.fase == 'selaras penuh'].groupby('tahun').gerak.mean().round(3).to_dict())

start = full & ~np.roll(full, 1)
sess = (hour >= 7) & (hour < 18)
out = []; busy = -1
for i in np.nonzero(start & sess)[0]:
    if i <= busy or i < 600 or i >= N - 98: continue
    d = big[i]; e = o[i + 1]; risk = 2.0 * atr[i]; stop = e - d * risk; ex = None
    for j in range(i + 1, i + 97):
        if (l[j] <= stop) if d > 0 else (h[j] >= stop):
            r = -1.0; ex = j; break
        if tr15[j] != d:
            r = d * (c[j] - e) / risk; ex = j; break
    if ex is None:
        ex = i + 96; r = d * (c[ex] - e) / risk
    out.append((year[i], d, r - COST[i + 1] / risk)); busy = ex
r = pd.DataFrame(out, columns=['tahun', 'arah', 'R'])
yr = r.groupby('tahun').R.agg(['count', 'mean'])
t = r.R.mean() / r.R.std() * np.sqrt(len(r))
print(f"\n2) AL (jam 07-18): {len(r)} trade, win {np.mean(r.R > 0):.0%}, rata-rata {r.R.mean():+.3f}R, t {t:.2f}, "
      f"tahun positif {int((yr['mean'] > 0).sum())}/{len(yr)}")
print("   BUY :", f"{r[r.arah > 0].R.mean():+.3f}R ({(r.arah > 0).sum()})", " SELL:", f"{r[r.arah < 0].R.mean():+.3f}R ({(r.arah < 0).sum()})")
print(yr.round(3).T.to_string())
lolos = r.R.mean() > 0 and t >= 2 and (yr['mean'] > 0).sum() >= 12
print("\nKRITERIA AL:", "LOLOS" if lolos else "TIDAK LOLOS")
