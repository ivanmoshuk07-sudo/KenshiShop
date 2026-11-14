import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import kenshimod as km
original,release=map(Path,sys.argv[1:3])
a,b=km.ler(original),km.ler(release)
assert km.serializar(a)==original.read_bytes()
assert km.serializar(b)==release.read_bytes()
old={r['strid']:r for r in a['records']};new={r['strid']:r for r in b['records']}
assert len(old)==len(a['records']) and len(new)==len(b['records'])
assert all(sid in new for sid in old)
changed={sid for sid in old if old[sid]!=new[sid]}
expected={f'{i}-KenshiShop.mod'.encode() for i in [300,303,305,307,309,7310]}
assert changed==expected,changed
for r in b['records']:
 for cat,items in r['extra']:
  for sid,*v in items:
   if sid.endswith(b'-KenshiShop.mod'):assert sid in new,(r['strid'],cat,sid)
   assert b'Legendary of Kenshi.mod' not in sid
for n in range(8100,8105):
 r=new[f'{n}-KenshiShop.mod'.encode()];assert r['typecode']==72
 for cat in [b'Leader AI Goals',b'Squad AI Goals']:
  goals=dict(r['extra'])[cat]
  for sid in [b'1360-gamedata.base',b'7603-KenshiShop.mod',b'51395-rebirth.mod']:
   assert (sid,0,24,0) in goals
  for sid,start,end,unused in goals:assert 0<=start<end<=24
  if n==8101:
   assert (b'8000-KenshiShop.mod',6,23,0) in goals
   assert (b'8007-KenshiShop.mod',0,6,0) in goals
   assert (b'8008-KenshiShop.mod',23,24,0) in goals
for n in [300,303,305,307,309]:
 r=new[f'{n}-KenshiShop.mod'.encode()]
 assert km.campo(r,'bool','is trader')==1
 assert km.campo(r,'long','vendor money')>0
 assert km.campo(r,'bool','public night')==int(n in [300,309])
assert new[b'7603-KenshiShop.mod']==old[b'7603-KenshiShop.mod']
for n in range(8200,8205):
 r=new[f'{n}-KenshiShop.mod'.encode()]
 for cat in [b'Leader AI Goals',b'Squad AI Goals']:
  goals=dict(r['extra'])[cat]
  for sid in [b'1360-gamedata.base',b'7603-KenshiShop.mod',b'51395-rebirth.mod']:
   assert (sid,0,24,0) in goals
  assert all(sid not in {b'8000-KenshiShop.mod',b'8001-KenshiShop.mod',b'8002-KenshiShop.mod',b'8003-KenshiShop.mod',b'8004-KenshiShop.mod',b'8005-KenshiShop.mod'} for sid,*_ in goals)
for n in range(8300,8305):
 r=new[f'{n}-KenshiShop.mod'.encode()];previous=new[f'{n-100}-KenshiShop.mod'.encode()]
 assert r['name'].startswith(b'KS83 ')
 assert r['extra']==previous['extra'] # Emergency care and native idle preserved.
for sid,r in old.items():
 if r['typecode'] in [0,21]:assert new[sid]==r,('Building/furniture data changed',sid)
assert dict(new[b'303-KenshiShop.mod']['extra'])[b'vendors']==[(b'1502-gamedata.base',100,0,0)]
assert dict(new[b'305-KenshiShop.mod']['extra'])[b'vendors']==[(b'50319-rebirth.mod',100,0,0)]
print('PASS binary round trips, preserved building/layout records, unique IDs/references, care/schedules, explicit vendors; no absent-node or roaming goals in alpha.82 packages')

import subprocess
# Check alpha.81 physical interiors and furniture logic byte-for-byte.
files=subprocess.check_output(['git','ls-tree','-r','--name-only','v0.3.0-alpha.81'],text=True).splitlines()
protected=[p for p in files if '/Building/' in p or p.startswith('KenshiShop/scripts/Core/Ownership/') and p.rsplit('/',1)[-1]!='Manager.lua']
for name in protected:
 assert Path(name).read_bytes()==subprocess.check_output(['git','show','v0.3.0-alpha.81:'+name]),name
print('PASS all physical building modules and furniture ownership/restore files identical to alpha.81')

# The alpha.83 update may add versioned AI packages, but must leave every
# existing alpha.82 binary record and all physical Lua modules unchanged.
import tempfile
with tempfile.TemporaryDirectory() as tmp:
 path=Path(tmp)/'alpha82.mod'
 path.write_bytes(subprocess.check_output(['git','show','v0.3.0-alpha.82:KenshiShop/KenshiShop.mod']))
 prior=km.ler(path)
 for r in prior['records']:assert new[r['strid']]==r,('alpha.82 record changed',r['strid'])
print('PASS every alpha.82 binary record preserved, new versioned packages retain the original care tasks')
