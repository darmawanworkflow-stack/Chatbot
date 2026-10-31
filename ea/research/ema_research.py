"""Uji insight riset EMA pada fase 'selaras penuh' (gerak 1 jam ke depan searah tren besar).
1. Pasangan EMA lain (Levine & Pedersen: horizon lebih panjang lebih baik).
2. Rezim volatilitas (Han, Yang & Zhou: tren lebih efektif saat volatilitas tinggi).
Sampel per jam (tidak tumpang tindih). Hanya bar yang sudah tutup."""
import numpy as np, pandas as pd
import lab
t, c, N = lab.t, lab.c, lab.N
idx = pd.DatetimeIndex(t)
year = idx.year.to_numpy()
base = pd.DataFrame({'close': c, 'high': lab.h, 'low': lab.l}, index=idx)

def trend_tf(rule, minutes, fast, slow):
    if rule is None:
        cl = pd.Series(c, index=idx)
        ef, es = cl.ewm(span=fast, adjust=False).mean(), cl.ewm(span=slow, adjust=False).mean()
        return np.where((cl > es) & (ef > es), 1, np.where((cl < es) & (ef < es), -1, 0))
    b = base.close.resample(rule).last().dropna()
    ef, es = b.ewm(span=fast, adjust=False).mean(), b.ewm(span=slow, adjust=False).mean()
    tr = np.where((b > es) & (ef > es), 1, np.where((b < es) & (ef < es), -1, 0))
    s = pd.Series(tr, index=b.index + pd.Timedelta(minutes=minutes))
    return s.reindex(idx + pd.Timedelta(minutes=5), method='ffill').fillna(0).to_numpy().astype(int)

S = np.arange(600, N - 13, 12)
fwd = c[S + 12] - c[S]

def phase_stats(fast, slow, mask=None):
    t5 = trend_tf(None, 0, fast, slow); t15 = trend_tf('15min', 15, fast, slow)
    t60 = trend_tf('1h', 60, fast, slow); t240 = trend_tf('4h', 240, fast, slow)
    big = np.where((t240 != 0) & (t240 == t60), t240, 0)
    full = (big != 0) & (t15 == big) & (t5 == big)
    m = full[S] if mask is None else full[S] & mask
    x = (fwd * big[S])[m]; yr = year[S][m]
    out = dict(n=len(x), mean=x.mean(), t=x.mean() / x.std() * np.sqrt(len(x)), share=m.mean())
    for y in (2024, 2025, 2026):
        out[str(y)] = x[yr == y].mean()
    return out

pd.set_option('display.width', 200)
rows = []
for f, s in ((9, 21), (10, 30), (20, 50), (20, 100), (50, 100), (50, 200)):
    rows.append(dict(ema=f'{f}/{s}', **phase_stats(f, s)))
print("1) Fase selaras penuh dengan pasangan EMA berbeda (USD/jam searah tren besar):")
print(pd.DataFrame(rows).round(3).to_string(index=False))

# rezim volatilitas: ATR H1 dibanding median 30 hari sebelumnya
h1 = base.resample('1h').agg({'high': 'max', 'low': 'min', 'close': 'last'}).dropna()
trh = np.maximum(h1.high - h1.low, np.maximum(abs(h1.high - h1.close.shift()), abs(h1.low - h1.close.shift())))
atr = trh.ewm(alpha=1 / 14, adjust=False).mean()
rel = atr / atr.rolling(24 * 30).median()
rel.index = rel.index + pd.Timedelta(hours=1)
relv = rel.reindex(idx + pd.Timedelta(minutes=5), method='ffill').to_numpy()[S]
rows = []
for lbl, m in (('volatilitas rendah (< 0.85x median)', relv < 0.85), ('normal (0.85-1.2x)', (relv >= 0.85) & (relv <= 1.2)),
               ('tinggi (> 1.2x median)', relv > 1.2)):
    rows.append(dict(rezim=lbl, **phase_stats(20, 50, m)))
print("\n2) Fase selaras penuh (EMA 20/50) per rezim volatilitas:")
print(pd.DataFrame(rows).round(3).to_string(index=False))
