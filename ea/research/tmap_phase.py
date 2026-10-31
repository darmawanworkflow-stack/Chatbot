import numpy as np, pandas as pd
exec(open('tmap_bt.py').read().split('# ---------- A. panah konfluensi')[0])
big = np.where((tr240 != 0) & (tr240 == tr60), tr240, 0)
phase = np.select([(big != 0) & (tr15 == big) & (tr5 == big), (big != 0) & (tr15 == -big), (big != 0) & (tr15 == 0),
                   (big != 0) & (tr15 == big)], ['selaras penuh', 'pullback M15', 'pullback melemah', 'M15 searah M5 koreksi'], '-')
S = np.arange(300, N - 13, 12)          # sampel tiap 1 jam (tidak tumpang tindih)
mv = (c[S + 12] - c[S]) * big[S]
df = pd.DataFrame({'fase': phase[S], 'tahun': year[S], 'gerak': mv, 'jam': hour[S]})
df = df[df.fase != '-']
g = df.groupby(['fase', 'tahun']).gerak.agg(['count', 'mean', 'std'])
g['t'] = g['mean'] / g['std'] * np.sqrt(g['count'])
pd.set_option('display.width', 200)
print("Gerak 1 jam ke depan searah tren besar (USD), sampel per jam tanpa tumpang tindih:")
print(g.round(2).to_string())
a = df.groupby('fase').gerak.agg(['count', 'mean', 'std']); a['t'] = a['mean'] / a['std'] * np.sqrt(a['count'])
print(a.round(2).to_string())
