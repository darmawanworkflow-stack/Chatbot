"""Trend following harian ala Turtle pada XAUUSD (dari data M5 -> D1).
Masuk saat close menembus high/low N hari (arah keluar sesudah tembus M hari lawan),
keluar saat close menembus low/high M hari. Risiko 1R = 2 x ATR(20) harian saat masuk.
Biaya $0.40 per trade (spread+komisi+slip). Swap tidak dihitung."""
import sys, numpy as np, pandas as pd
df = pd.read_csv(sys.argv[1], parse_dates=['time']).drop_duplicates('time').set_index('time')
D = df.resample('1D').agg({'open': 'first', 'high': 'max', 'low': 'min', 'close': 'last'}).dropna()
D = D[D.index.dayofweek < 5]
tr = np.maximum(D.high - D.low, np.maximum(abs(D.high - D.close.shift()), abs(D.low - D.close.shift())))
atr = tr.rolling(20).mean()
def run(n_in, n_out, longonly=False):
    hi = D.high.shift(1).rolling(n_in).max(); lo = D.low.shift(1).rolling(n_in).min()
    xhi = D.high.shift(1).rolling(n_out).max(); xlo = D.low.shift(1).rolling(n_out).min()
    pos, e, R, t0, trades = 0, 0, 0, None, []
    for i in range(max(n_in, 21), len(D)):
        c = D.close.iloc[i]
        if pos == 1 and c < xlo.iloc[i] or pos == -1 and c > xhi.iloc[i]:
            trades.append((t0, D.index[i], pos, (pos * (c - e) - 0.4) / R)); pos = 0
        if pos == 0:
            if c > hi.iloc[i]:
                pos, e, R, t0 = 1, c, 2 * atr.iloc[i], D.index[i]
            elif c < lo.iloc[i] and not longonly:
                pos, e, R, t0 = -1, c, 2 * atr.iloc[i], D.index[i]
    if pos != 0:
        trades.append((t0, D.index[-1], pos, (pos * (D.close.iloc[-1] - e) - 0.4) / R))
    t = pd.DataFrame(trades, columns=['masuk', 'keluar', 'arah', 'R'])
    return t
pd.set_option('display.width', 200)
for n_in, n_out in ((20, 10), (55, 20)):
    for lo_ in (False, True):
        t = run(n_in, n_out, lo_)
        yr = t.groupby(t.masuk.dt.year).R.agg(['count', 'sum'])
        print(f"Breakout {n_in}/{n_out} {'hanya BUY' if lo_ else 'BUY+SELL'}: {len(t)} trade, win {np.mean(t.R > 0):.0%}, "
              f"total {t.R.sum():+.1f}R, rata {t.R.mean():+.2f}R, terbaik {t.R.max():+.1f}R | per tahun (total R): "
              + ", ".join(f"{y}: {r['sum']:+.1f} ({int(r['count'])})" for y, r in yr.iterrows()))
bh = (D.close.iloc[-1] - D.close.iloc[21]) / (2 * atr.iloc[21])
print(f"Pembanding beli-dan-tahan sepanjang periode: {bh:+.1f}R (dengan R = 2 ATR harian awal)")
