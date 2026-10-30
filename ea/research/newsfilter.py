import sys, numpy as np, pandas as pd
import mtf, lab
cal=pd.read_csv(sys.argv[2],parse_dates=['time']); hi=np.array(sorted(set(cal[cal.importance=='high'].time)),dtype='datetime64[ns]')
t=lab.t.to_numpy().astype('datetime64[ns]')
pos=np.searchsorted(hi,t)
nxt=np.where(pos<len(hi),hi[np.minimum(pos,len(hi)-1)],np.datetime64('2100-01-01'))
prv=np.where(pos>0,hi[np.maximum(pos-1,0)],np.datetime64('1900-01-01'))
near=((nxt-t)<=np.timedelta64(30,'m'))|((t-prv)<=np.timedelta64(60,'m'))
print(f"bar dalam jendela berita (-30/+60 menit): {near.mean():.1%}")
cut=int(lab.N*.7)
cases=[('PB_pullback',lab.SIG['PB_pullback'],None),('MO_break48_h1',lab.SIG['MO_break48_h1'],None),
       ('pinbar M15+H1+H4',mtf.TRIG['pinbar'],mtf.FILT['M15+H1+H4_tren']),('inside H4+H1pb',mtf.TRIG['inside_break'],mtf.FILT['H4_tren+H1_pullback']),
       ('engulf H1+H4',mtf.TRIG['engulfing'],mtf.FILT['H1+H4_tren']),('RANDOM',lab.SIG['RANDOM'],None)]
print(f"{'sinyal':22s} {'filter berita':14s} {'n':>6s} {'R train':>8s} {'R test':>8s}")
for name,tg,f in cases:
    s=tg if f is None else np.where(tg==f,tg,0)
    s=np.where(mtf.SESSION,s,0)
    for lbl,m in (('semua',np.ones(lab.N,bool)),('hindari berita',~near),('HANYA berita',near)):
        ix,r=lab.simulate(np.where(m,s,0),1.5,3.0)
        print(f"{name:22s} {lbl:14s} {len(r):6d} {r[ix<cut].mean():+8.3f} {r[ix>=cut].mean():+8.3f}")
