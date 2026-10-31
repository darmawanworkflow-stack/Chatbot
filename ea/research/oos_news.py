"""Uji di luar sampel NP (pullback searah tren H1 di jendela berita USD high-impact) pada data Kaggle 2007-2023.
Aturan sama dengan newsfilter.py / NewsPullbackArrows / ForwardTestEA: sinyal PB_pullback dari lab.py, jam 07-18,
jendela -30/+60 menit berita high, masuk open candle berikutnya, SL 1.5 ATR, TP 3R, maks 48 candle, 1 posisi.
Kriteria lolos (ditetapkan sebelum melihat hasil): rata-rata R > 0, t >= 2, positif >= 10 dari 17 tahun."""
import sys, numpy as np, pandas as pd
import lab, mtf
cal = pd.read_csv(sys.argv[2], parse_dates=['time'])
hi = np.array(sorted(set(cal[cal.importance == 'high'].time)), dtype='datetime64[ns]')
t = lab.t.to_numpy().astype('datetime64[ns]')
pos = np.searchsorted(hi, t)
nxt = np.where(pos < len(hi), hi[np.minimum(pos, len(hi) - 1)], np.datetime64('2100-01-01'))
prv = np.where(pos > 0, hi[np.maximum(pos - 1, 0)], np.datetime64('1900-01-01'))
near = ((nxt - t) <= np.timedelta64(30, 'm')) | ((t - prv) <= np.timedelta64(60, 'm'))
covered = t >= hi[0]                                   # hanya periode yang punya kalender
year = pd.DatetimeIndex(lab.t).year.to_numpy()
pb = np.where(mtf.SESSION & covered, lab.SIG['PB_pullback'], 0)
def report(lbl, mask):
    ix, r = lab.simulate(np.where(mask, pb, 0), 1.5, 3.0)
    y = pd.Series(r, index=year[ix]).groupby(level=0).mean()
    tt = r.mean() / r.std(ddof=1) * np.sqrt(len(r))
    print(f"{lbl:22s} n={len(r):5d} win={np.mean(r > 0):.0%} rata2={r.mean():+.3f}R t={tt:5.2f} tahun positif {int((y > 0).sum())}/{len(y)}")
    return r, y, tt
r, y, tt = report('NP (saat berita)', near)
print('   per tahun:', y.round(3).to_dict())
report('PB di luar berita', ~near)
report('PB semua jam 07-18', np.ones(len(t), bool))
print('\nKRITERIA NP:', 'LOLOS' if (r.mean() > 0 and tt >= 2 and (y > 0).sum() >= 10) else 'TIDAK LOLOS')
