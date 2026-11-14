"""Apply alpha.82 changes to alpha.81; never edit buildings, layouts or furniture."""
import sys
from pathlib import Path
import kenshimod as km
src,dst=map(Path,sys.argv[1:3]);m=km.ler(src);by={r['strid']:r for r in m['records']}
assert km.serializar(m)==src.read_bytes()
# Native emergency care remains. Routine goals are assigned to actual post/route
# locations in Lua instead of asking the engine for absent usage-node objects.
for i,name in enumerate(['Trader 24h','Trader 06-23','Indoor guards','Police chief','Town patrol']):
 old=by[f'810{i}-KenshiShop.mod'.encode()]
 r=km.clonar_registro(old,f'820{i}-KenshiShop.mod','KS82 '+name);r['id']=8200+i
 r['extra']=[(cat,[(sid,start,end,v)for sid,start,end,v in goals if sid not in {
  b'8000-KenshiShop.mod',b'8001-KenshiShop.mod',b'8002-KenshiShop.mod',b'8003-KenshiShop.mod',
  b'8004-KenshiShop.mod',b'8005-KenshiShop.mod'}])for cat,goals in r['extra']]
 km.set_campo(r,'long','unloaded func',4)
 m['records'].append(r)
# Safe native idle is a lower-priority fallback while Lua configures real goals.
base=by[b'7603-KenshiShop.mod'];idle=km.clonar_registro(base,'8205-KenshiShop.mod','KS82 Standby');idle['id']=8205
km.set_campo(idle,'long','enum',62);km.set_campo(idle,'long','classification',1)
m['records'].append(idle)
for r in m['records']:
 if r['strid'] in {f'820{i}-KenshiShop.mod'.encode() for i in range(5)}:
  r['extra']=[(cat,goals+[(b'8205-KenshiShop.mod',0,24,0)])for cat,goals in r['extra']]
# Remove the log-confirmed lore substitute. Runtime resolves a mechanical/tech shop.
r=by[b'303-KenshiShop.mod'];r['extra']=[(cat,[x for x in rows if x[0]!=b'53662-Dialogue.mod'])if cat==b'vendors'else(cat,rows)for cat,rows in r['extra']]
# Correct the known Armour King native list even if no donor squad is available.
r=by[b'305-KenshiShop.mod'];r['extra']=[(cat,[(b'50319-rebirth.mod',100,0,0)])if cat==b'vendors'else(cat,rows)for cat,rows in r['extra']]
m['description']=b'KenshiShop alpha.82: original vendor resolution, verified NPC posts, resident pointer repair, inside-city routes and scoped native defence. No furniture changes. In-game verification required.'
m['unknown']=max(m['unknown'],8300)
km.gravar(dst,m);assert km.serializar(km.ler(dst))==dst.read_bytes()
print('alpha.82 data written:',len(m['records']),'records')
