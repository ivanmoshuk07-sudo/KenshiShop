"""Native autonomous roles, complete bar stock, persistent Armour King grades.
No physical building, interior, layout or furniture record is changed.
"""
import sys
from pathlib import Path
import kenshimod as km
src,dst=map(Path,sys.argv[1:3]);m=km.ler(src);by={r['strid']:r for r in m['records']}
assert km.serializar(m)==src.read_bytes()
def setv(r,section,key,value):
    if not km.set_campo(r,section,key,value):r[section].append((key.encode(),value))
def refs(r,key,values):
    r['extra']=[(k,v) for k,v in r['extra'] if k!=key.encode()]+[(key.encode(),values)]
def goal(n,name,enum,priority,target=1):
    r=km.clonar_registro(by[b'7603-KenshiShop.mod'],f'{n}-KenshiShop.mod','KS84 '+name);r['id']=n
    for k,v in [('enum',enum),('classification',priority),('targeting',target),('ending',0)]:setv(r,'long',k,v)
    m['records'].append(r);return r['strid']
# Ambient native town wandering chooses its own destinations. Followers use
# the engine's formation/follow behavior, with no Lua destination scheduler.
wander=goal(8405,'Patrol hometown (ambient)',37,1)
follow=goal(8406,'Follow patrol leader',141,1,2)
protect=goal(8407,'Protect allies stay in town',288,3)
home=goal(8408,'Protect own squad',143,3)
care=[(b'1360-gamedata.base',0,24,0),(b'7603-KenshiShop.mod',0,24,0),(b'51395-rebirth.mod',0,24,0)]
for i,name in enumerate(['Trader 24h','Trader 06-23','Indoor guards','Police chief','Town patrol']):
    r=km.clonar_registro(by[f'830{i}-KenshiShop.mod'.encode()],f'840{i}-KenshiShop.mod','KS84 '+name);r['id']=8400+i
    for k,v in [('signal func',0),('unloaded func',1 if i==4 else 4)]:setv(r,'long',k,v)
    for cat in ['Leader AI Goals','Squad AI Goals']:
        jobs=list(care)
        if i<2:
            start,end=(6,23) if i==1 else (0,24)
            jobs += [(home,0,24,0),(b'8000-KenshiShop.mod',start,end,10),(b'8006-KenshiShop.mod',start,end,5)]
            if i==1:jobs += [(b'8007-KenshiShop.mod',0,6,5),(b'8008-KenshiShop.mod',23,24,5)]
        elif i<4:jobs += [(home,0,24,0),(protect,0,24,0),(b'8001-KenshiShop.mod',0,24,10)]
        else:jobs += [(protect,0,24,0),(wander if cat=='Leader AI Goals' else follow,0,24,10)]
        refs(r,cat,jobs)
    m['records'].append(r)
# Complete native bar and expedition supplies, also present without runtime Lua.
bar=by[b'300-KenshiShop.mod']
refs(bar,'vendors',[(b'1973-gamedata.base',100,0,0),(b'44862-rebirth.mod',100,0,0)])
setv(bar,'long','vendors fill total amount',140)
# Grade chances belong to the faction. Keep them effective during native engine
# restocks too. Only our custom merchant faction changes, never Skeletons itself.
for i,value in enumerate([0,0,2,80,110,50]):setv(by[b'400-KenshiShop.mod'],'long',f'armors {i}',value)
m['description']=b'KenshiShop alpha.84: autonomous native AI roles, native location nodes, full bar/travel stock and persistent Armour King faction grades. No furniture changes. In-game validation required.'
m['unknown']=max(m['unknown'],8500)
km.gravar(dst,m);assert km.serializar(km.ler(dst))==dst.read_bytes()
print('alpha.84 written:',len(m['records']),'records')
