import sys, numpy as np, pandas as pd
import lab
base_cost = lab.COST.copy()
src = open('oos_news.py').read().split("r, y, tt = report('NP (saat berita)', near)")[0]
for lbl, cost in (('biaya proporsional harga ($0.25 per $4000)', 0.25 * lab.c / 4000.0), ('tanpa biaya (gross)', np.zeros(lab.N))):
    lab.COST[:] = cost
    print('==', lbl)
    exec(src + "\nr, y, tt = report('NP (saat berita)', near)\nprint('   per tahun:', y.round(3).to_dict())\nreport('PB di luar berita', ~near)")
