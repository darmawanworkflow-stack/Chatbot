"""Uji aturan gabungan DailyTrendStatus: PEGANG bila >= 2 dari 3 aturan (SMA 210, EMA 20/50, momentum 12 bulan)."""
import sys, numpy as np, pandas as pd
src = open('daily_long.py').read().split("vol20 = ret.rolling(20)")[0]
exec(src)
s1 = (c > sma210).astype(int)
s2 = ((c > e50) & (e20 > e50)).astype(int)
s3 = (c / c.shift(252) - 1 > 0).astype(int)
vote = ((s1 + s2 + s3) >= 2).astype(float)
S = {'Beli & tahan': pd.Series(1.0, index=D.index), 'Gabungan >= 2 dari 3 (long saja)': vote,
     'Faber SMA 10 bulan (long saja)': s1.astype(float), 'EMA 20/50 (long saja)': s2.astype(float)}
exec("vol20 = ret.rolling(20)" + open('daily_long.py').read().split("vol20 = ret.rolling(20)")[1].split("pd.set_option")[0])
rows = []
for name, p in S.items():
    for vt in (False, True):
        if vt and name.startswith('Beli'):
            continue
        # versi tanpa leverage: porsi maksimal 100%
        m, y = perf(p, vt)
        rows.append(dict(strategi=name + (' + vol target' if vt else ''), **{k: round(v * (100 if k != 'sharpe' else 1), 2) for k, v in m.items()}))
print(pd.DataFrame(rows).to_string(index=False))
