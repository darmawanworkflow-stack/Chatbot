import openpyxl, sys, collections, numpy as np, pandas as pd
rows = list(openpyxl.load_workbook(sys.argv[1], read_only=True).worksheets[0].iter_rows(values_only=True))
for r in rows[:110]:
    s = [x for x in r if x is not None]
    if s and any(k in str(s[0]) for k in ('Period', 'Modelling', 'History', 'Initial', 'Total Net', 'Profit Factor', 'Total Trades', 'Balance Drawdown Max', 'InpUse', 'InpRisk')):
        print(s)
h = [i for i, r in enumerate(rows) if r and r[0] == 'Time' and r[1] == 'Deal'][0]
D = [r for r in rows[h + 1:] if r[1] is not None and r[2] not in (None, '')]
# pasangkan in/out lewat urutan per strategi (tiap strategi maks 1 posisi)
open_ = {}
res = []
ambiguous = []
for r in D:
    cm = str(r[12] or '')
    if r[4] == 'in':
        p = cm.split('|')
        tag = p[1] if len(p) >= 3 else '?'
        risk = float(p[2]) if len(p) >= 3 else np.nan
        open_[tag] = dict(t=r[0], comm=float(r[8] or 0), risk=risk, dir=r[3], vol=float(r[5]))
    elif r[4] == 'out':
        # cari strategi yang posisinya berlawanan arah dan masih terbuka (paling lama)
        cands = [k for k, v in open_.items() if v['dir'] != r[3] and abs(v['vol'] - float(r[5])) < 1e-9]
        if not cands:
            continue
        amb = len(cands) > 1
        if amb:
            ambiguous.append(r[0])
        k = sorted(cands, key=lambda x: open_[x]['t'])[0]
        v = open_.pop(k)
        prof = float(r[10] or 0) + float(r[8] or 0) + float(r[9] or 0) + v['comm']
        res.append((k, str(v['t'])[:4], v['dir'], prof, prof / v['risk'] if v['risk'] else np.nan, str(r[12] or '')[:2]))
df = pd.DataFrame(res, columns=['strategi', 'tahun', 'arah', 'profit', 'R', 'exit'])
pd.set_option('display.width', 200)
for k, g in df.groupby('strategi'):
    t = g.R.mean() / g.R.std() * np.sqrt(len(g))
    print(f"\n{k}: {len(g)} trade, win {np.mean(g.R > 0):.0%}, rata-rata {g.R.mean():+.3f}R, t {t:.2f}, total {g.R.sum():+.1f}R, profit ${g.profit.sum():,.0f}")
    print("  per tahun:", g.groupby('tahun').R.agg(['count', 'mean']).round(3).to_dict('index'))
    print("  BUY :", f"{g[g.arah == 'buy'].R.mean():+.3f}R ({(g.arah == 'buy').sum()})", " SELL:", f"{g[g.arah == 'sell'].R.mean():+.3f}R ({(g.arah == 'sell').sum()})")
    print("  exit:", g.exit.value_counts().to_dict())
print("\nOut deal ambigu (volume & arah sama di kedua strategi):", len(ambiguous), "| tidak terpasang:", len(open_))
