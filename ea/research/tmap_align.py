import numpy as np, pandas as pd
exec(open('tmap_bt.py').read().split('# ---------- A. panah konfluensi')[0])
atr = lab.atr; COST = lab.COST
big = np.where((tr240 != 0) & (tr240 == tr60), tr240, 0)
full = (big != 0) & (tr15 == big) & (tr5 == big)
start = full & ~np.roll(full, 1)          # baru masuk fase selaras penuh
def run(entry_mask, sl_k, exit_rule, maxbars, sess=None):
    out = []; busy = -1
    for i in np.nonzero(entry_mask)[0]:
        if i <= busy or i < 300 or i >= N - maxbars - 2: continue
        if sess is not None and not sess[i]: continue
        d = big[i]; e = o[i + 1]; risk = sl_k * atr[i]; stop = e - d * risk; ex = None
        for j in range(i + 1, i + maxbars + 1):
            if (l[j] <= stop) if d > 0 else (h[j] >= stop):
                r = -1.0; ex = j; break
            if exit_rule == 'align' and tr15[j] != d:       # keluar saat M15 tidak lagi searah
                r = d * (c[j] - e) / risk; ex = j; break
        if ex is None:
            ex = i + maxbars; r = d * (c[ex] - e) / risk
        out.append((i, r - COST[i + 1] / risk)); busy = ex
    a = np.array(out); return a[:, 0].astype(int), a[:, 1]
pd.set_option('display.width', 200)
sess = (hour >= 7) & (hour < 18)
for lbl, m, k, rule, mb, ss in (
    ('masuk awal selaras, keluar saat M15 berbalik, SL 2 ATR', start, 2.0, 'align', 96, None),
    ('sama, hanya jam 07-18', start, 2.0, 'align', 96, sess),
    ('masuk awal selaras, tahan 12 candle (1 jam), SL 2 ATR', start, 2.0, 'time', 12, None),
    ('masuk awal selaras, tahan 48 candle (4 jam), SL 3 ATR', start, 3.0, 'time', 48, None)):
    ix, r = run(m, k, rule, mb, ss)
    y = pd.Series(r, index=year[ix]).groupby(level=0).agg(['count', 'mean'])
    tstat = r.mean() / r.std(ddof=1) * np.sqrt(len(r))
    print(f"{lbl}\n   n={len(r)} win={np.mean(r>0):.2f} rata2={r.mean():+.3f}R t={tstat:.2f} | per tahun: " +
          ", ".join(f"{yy}: {row['mean']:+.3f}R ({int(row['count'])})" for yy, row in y.iterrows()))
