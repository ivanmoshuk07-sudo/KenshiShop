"""Validate the alpha.84 -> alpha.85 delta and the original node coordinates."""
import json
import re
import subprocess
import sys
import tempfile
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'Development'))
import kenshimod as km
from build_alpha85 import build

oldpath, newpath = map(Path, sys.argv[1:3])
oldmod, newmod = km.ler(oldpath), km.ler(newpath)
old = {r['strid']: r for r in oldmod['records']}
new = {r['strid']: r for r in newmod['records']}
assert len(new) == len(newmod['records'])
assert km.serializar(newmod) == newpath.read_bytes()
staff = {f'{n}-KenshiShop.mod'.encode() for n in [300,303,305,307,309,310,311,7800,7801,7802,7803]}
assert old.keys() <= new.keys()
assert {sid for sid in old if old[sid] != new[sid]} == staff
for sid in staff:
    a, b = dict(old[sid]), dict(new[sid])
    a['extra'] = [(k,v) for k,v in a['extra'] if k != b'AI packages']
    b['extra'] = [(k,v) for k,v in b['extra'] if k != b'AI packages']
    assert a == b, ('Unrelated squad change', sid)
    assert dict(new[sid]['extra'])[b'AI packages'] == [(b'7604-KenshiShop.mod',0,0,0)]
assert new.keys() - old.keys() == {f'{n}-KenshiShop.mod'.encode() for n in range(8500,8506)}
for r in newmod['records']:
    for cat, rows in r['extra']:
        for sid, *values in rows:
            if sid.endswith(b'-KenshiShop.mod'):
                assert sid in new, (r['strid'], cat, sid)
for i in range(5):
    r = new[f'850{i}-KenshiShop.mod'.encode()]
    assert r['typecode'] == 72
    for cat in [b'Leader AI Goals', b'Squad AI Goals', b'Squad2 AI Goals']:
        jobs = dict(r['extra'])[cat]
        for care in [b'1360-gamedata.base',b'7603-KenshiShop.mod',b'51395-rebirth.mod']:
            assert (care,0,24,0) in jobs
        if i < 2:
            assert (b'1170-gamedata.base',6 if i else 0,23 if i else 24,0) in jobs
        elif i == 2:
            assert (b'8505-KenshiShop.mod',0,24,0) in jobs
        elif i == 3:
            assert (b'1188-gamedata.base',0,24,0) in jobs
        else:
            assert ((b'965-gamedata.base',0,24,0) in jobs) == (cat == b'Leader AI Goals')
        assert not any(sid.startswith(b'84') or sid.startswith(b'80') for sid,*_ in jobs)
assert km.campo(new[b'8505-KenshiShop.mod'],'long','targeting') == 0
assert km.campo(new[b'8505-KenshiShop.mod'],'long','enum') == 268
with tempfile.TemporaryDirectory() as folder:
    rebuilt = Path(folder)/'rebuilt.mod'
    build(oldpath, rebuilt)
    assert rebuilt.read_bytes() == newpath.read_bytes()
print('PASS reproducible binary, preserved stock/quality/buildings, role schedules, care and native targets')

reference = json.loads((ROOT/'Development/references/native_nodes.json').read_text())
source = (ROOT/'KenshiShop/scripts/Core/NPC/PostData.lua').read_text()
actual = {}
for line in source.splitlines():
    found = re.search(r"source='([^']+)',id='([^']+)',kind=(\d+),floor=(\d+),p=\{([^}]+)\},q=\{([^}]+)\}",line)
    if found:
        key, sid, kind, floor, p, q = found.groups()
        assert key not in actual
        actual[key] = (sid,int(kind),int(floor),list(map(float,p.split(','))),list(map(float,q.split(','))))
assert len(actual) == 72
assert {k:len(v['nodes']) for k,v in reference.items()} == {'bar':20,'armour':12,'weapons':15,'engineering':13,'robotics':3,'police':9}
counts = Counter()
for shop, info in reference.items():
    assert len({(n['id'],tuple(n['p']),tuple(n['q'])) for n in info['nodes']}) == len(info['nodes'])
    for n in info['nodes']:
        assert actual[n['instance']] == (n['id'],n['node_type'],n['floor'],n['p'],n['q'])
        counts[n['node_type']] += 1
assert counts == {0:16,1:10,2:46}
assert not any(abs(n['p'][0]-43.1231155)<0.01 for n in reference['armour']['nodes'] if n['node_type']==0)
print('PASS all 72 original nodes: exact positions/quaternions/types/floors, no duplicate bar nodes, corrected armour counter')

protected = subprocess.check_output(['git','ls-tree','-r','--name-only','v0.3.0-alpha.84'],cwd=ROOT,text=True).splitlines()
protected = [p for p in protected if '/Building/' in p or p.startswith('KenshiShop_LegendaryCompat/') or p.endswith('/Catalog.lua') or 'Furniture' in p or '/Floor' in p or '/Layout' in p]
for path in protected:
    original = subprocess.check_output(['git','show','v0.3.0-alpha.84:'+path],cwd=ROOT)
    assert (ROOT/path).read_bytes() == original,path
print('PASS',len(protected),'physical building/furniture/layout, stock and compatibility files unchanged')
