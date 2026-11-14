"""Rebuild data changes from the supplied alpha.80 .mod, preserving unrelated records."""
import sys, copy
from pathlib import Path
import kenshimod as km
src, dst = map(Path, sys.argv[1:3])
raw = src.read_bytes(); m=km.desserializar(raw)
assert km.serializar(m)==raw, 'Input must round-trip byte-for-byte'
by={r['strid'].decode():r for r in m['records']}
def setv(r,section,key,value):
 if not km.set_campo(r,section,key,value): r[section].append((km.b(key),value))
def refs(r,key,values):
 r['extra']=[(k,v) for k,v in r['extra'] if k!=km.b(key)]+[(km.b(key),values)]
def newrec(source,n,name):
 sid=f'{n}-KenshiShop.mod'; assert sid not in by
 r=km.clonar_registro(source,sid,name);r['id']=n;r['instance_count']=0
 by[sid]=r;m['records'].append(r);return r
def goal(n,name,task,priority):
 r=newrec(by['7603-KenshiShop.mod'],n,name)
 for k,v in [('enum',task),('classification',priority),('targeting',1),('ending',0)]:setv(r,'long',k,v)
 return r['strid']
g={}
for n,name,task,p in [(8000,'Shopkeeper',20,2),(8001,'Indoor shop guards',268,2),
 (8002,'Police chief guard home',38,2),(8003,'Town patrol',36,2),
 (8004,'Protect allies',15,3),(8005,'Attack enemies',16,3),
 (8006,'Open shop doors',86,2),(8007,'Night rest morning',153,2),
 (8008,'Night rest evening',153,2)]:g[task if n!=8008 else 'rest_evening']=goal(n,'KS Native '+name,task,p)
common=[(g[15],0,24,0),(g[16],0,24,0),(b'1360-gamedata.base',0,24,0),
 (b'7603-KenshiShop.mod',0,24,0),(b'51395-rebirth.mod',0,24,0)]
for n,name,role,day in [(8100,'Trader 24h',20,False),(8101,'Trader 06-23',20,True),
 (8102,'Indoor guards',268,False),(8103,'Police chief',38,False),(8104,'Town patrol',36,False)]:
 r=newrec(by['7604-KenshiShop.mod'],n,'KS Native '+name)
 setv(r,'long','signal func',0);setv(r,'long','unloaded func',1 if role==36 else 4)
 work=[(g[role],6 if day else 0,23 if day else 24,0)]
 if role==20:
  work.insert(0,(g[86],6 if day else 0,23 if day else 24,0))
  if day:work += [(g[153],0,6,0),(g['rest_evening'],23,24,0)]
 for cat in ['Leader AI Goals','Squad AI Goals']:refs(r,cat,common+work)
# Vanilla vendor lists remain the source of stock. Native budgets/restock are enabled.
for sid,money,night in [(300,25000,True),(303,35000,False),(305,100000,False),(307,100000,False),(309,100000,True)]:
 r=by[f'{sid}-KenshiShop.mod']
 for k,v in [('is trader',1),('dont multiply',1),('public day',1),('public night',int(night))]:setv(r,'bool',k,v)
 setv(r,'long','vendor money',money)
 # Keep 12h Armour King refresh; all other shops 24h.
 setv(r,'long','robotics levels',5 if sid==309 else 1)
# Chief had an undeclared optional Legendary weapon dependency.
r=by['7310-KenshiShop.mod']; values=dict(r['extra'])[b'weapons']
refs(r,'weapons',[(sid,a,b,100 if sid==b'52308-rebirth.mod' else c) for sid,a,b,c in values if b'Legendary of Kenshi.mod' not in sid])
m['description']=b'KenshiShop alpha.81: native role AI after delivery; 24h/day traders, indoor guards, town patrol; native vendor budgets and refresh; save-load recovery fixes. In-game validation required.'
m['unknown']=max(m['unknown'],8200)
dst.write_bytes(km.serializar(m))
assert km.serializar(km.ler(dst))==dst.read_bytes()
print(f'Built {dst}: {len(m["records"])} records')

# Optional compatibility file: keep the Legendary weapon choice out of the base mod.
compat_src=src.parent.parent/'KenshiShop_LegendaryCompat'/'KenshiShop_LegendaryCompat.mod'
compat_dst=dst.parent.parent/'KenshiShop_LegendaryCompat'/'KenshiShop_LegendaryCompat.mod'
if compat_src.exists():
 c=km.ler(compat_src)
 orig=next(r for r in km.ler(src)['records'] if r['strid']==b'7310-KenshiShop.mod')
 patch={k:[] for k,_,_ in km.SECOES}
 patch.update(instance_count=0,typecode=1,id=0,name=orig['name'],strid=orig['strid'],mod_data_type=19,
  extra=[(b'weapons',dict(orig['extra'])[b'weapons'])],instances=[])
 assert all(r['strid']!=patch['strid'] for r in c['records'])
 c['records'].append(patch)
 compat_dst.parent.mkdir(parents=True,exist_ok=True)
 km.gravar(compat_dst,c)
 print(f'Built optional compatibility: {len(c["records"])} records')
