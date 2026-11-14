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
print('PASS binary round trips, all original records retained, exactly six existing records changed, 14 added records, unique IDs, internal references, schedules, care goals, trader budgets, optional dependency removed')
