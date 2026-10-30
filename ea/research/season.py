import pandas as pd, numpy as np, sys
df=pd.read_csv(sys.argv[1],parse_dates=['time']).drop_duplicates('time').set_index('time').sort_index()
h1=df.close.resample('1h').last().dropna()
ret=h1.diff().shift(-1).dropna()           # gerak harga jam berikutnya (USD), mulai dari close jam ini
cut=df.index[int(len(df)*0.7)]
COST=0.25                                   # spread+komisi+slip per trade (USD)
pd.set_option('display.width',200)
rows=[]
for hr in range(24):
    for name,part in (('tr',ret[ret.index<cut]),('te',ret[ret.index>=cut])):
        x=part[(part.index.hour+1)%24==hr]   # posisi dibuka pada awal jam hr
        rows.append((hr,name,len(x),x.mean(),x.mean()/x.std()*np.sqrt(len(x))))
r=pd.DataFrame(rows,columns=['jam','set','n','gerak_rata','t']).pivot(index='jam',columns='set',values=['n','gerak_rata','t'])
print("Gerak rata-rata gold (USD) bila memegang posisi BUY selama 1 jam, per jam mulai (server/GMT):")
print(r.round(2).to_string())
d=df.close.resample('1D').last().dropna(); dr=d.diff().dropna()
for name,part in (('tr',dr[dr.index<cut]),('te',dr[dr.index>=cut])):
    print(name, part.groupby(part.index.dayofweek).agg(['count','mean']).round(2).T.to_string())
print('buy & hold total:', round(df.close.iloc[-1]-df.close.iloc[0],1),'USD; train', round(df.close[:cut].iloc[-1]-df.close.iloc[0],1),'test', round(df.close.iloc[-1]-df.close[cut:].iloc[0],1))
