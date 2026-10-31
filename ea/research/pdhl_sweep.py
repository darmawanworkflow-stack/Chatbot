"""Strategi PDH/PDL sweep (ide repo ikeawesom/xauusd-backtest), diuji dengan benar di data M5 kita.
Bias: hari sebelumnya close > open = bullish. Bullish: tunggu harga sweep di bawah PDL, lalu candle M5
tutup kembali di atas PDL -> BUY di open berikutnya. SL di bawah low terendah sejak sweep (-0.1 ATR),
TP = kR. Bearish kebalikannya. Maks 1 trade/hari, tutup paksa akhir hari. Biaya sama dengan lab.py.
Juga dihitung 'win rate versi repo' (menang bila harga tidak menembus titik sweep), tanpa memperhatikan profit."""
import numpy as np, pandas as pd
import lab
t, o, h, l, c, atr, N, COST = lab.t, lab.o, lab.h, lab.l, lab.c, lab.atr, lab.N, lab.COST
day = pd.DatetimeIndex(t).normalize()
year = pd.DatetimeIndex(t).year.to_numpy()
dd = pd.DataFrame({'d': day, 'o': o, 'h': h, 'l': l, 'c': c}).groupby('d').agg(O=('o', 'first'), H=('h', 'max'), L=('l', 'min'), C=('c', 'last'))
prev = dd.shift(1)
rows = []
for rr in (1.0, 2.0):
    res = []
    for d0, g in pd.Series(np.arange(N)).groupby(day):
        if d0 not in prev.index or np.isnan(prev.loc[d0, 'H']):
            continue
        P = prev.loc[d0]; bull = P.C > P.O
        ix = g.to_numpy(); swept = False; ext = None; done = False
        for k, i in enumerate(ix[:-2]):
            if done:
                break
            if bull:
                if not swept and l[i] < P.L:
                    swept, ext = True, l[i]
                elif swept:
                    ext = min(ext, l[i])
                    if c[i] > P.L:
                        e = o[i + 1]; risk = max(e - (ext - 0.1 * atr[i]), 0.3 * atr[i]); d = 1
                        done = True
            else:
                if not swept and h[i] > P.H:
                    swept, ext = True, h[i]
                elif swept:
                    ext = max(ext, h[i])
                    if c[i] < P.H:
                        e = o[i + 1]; risk = max((ext + 0.1 * atr[i]) - e, 0.3 * atr[i]); d = -1
                        done = True
            if done:
                out = None; j_end = ix[-1]
                for j in range(i + 1, j_end + 1):
                    if (l[j] <= e - risk) if d > 0 else (h[j] >= e + risk):
                        out = -1.0; break
                    if (h[j] >= e + rr * risk) if d > 0 else (l[j] <= e - rr * risk):
                        out = rr; break
                if out is None:
                    out = d * (c[j_end] - e) / risk
                res.append((year[i], out - COST[i + 1] / risk))
    r = pd.DataFrame(res, columns=['th', 'R'])
    yr = r.groupby('th').R.mean()
    print(f"TP {rr:.0f}R: {len(r)} trade, win {np.mean(r.R > 0):.0%}, rata-rata {r.R.mean():+.3f}R, "
          f"t {r.R.mean() / r.R.std() * np.sqrt(len(r)):.2f} | " + ", ".join(f"{y}: {v:+.3f}R" for y, v in yr.items()))
