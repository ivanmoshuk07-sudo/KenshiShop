"""Validate the alpha.86 -> alpha.87 delta without running Kenshi."""
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
from build_alpha87 import build
oldpath, newpath = map(Path, sys.argv[1:3])
oldmod, newmod = km.ler(oldpath), km.ler(newpath)
old = {r['strid']: r for r in oldmod['records']}
new = {r['strid']: r for r in newmod['records']}
assert len(new) == len(newmod['records'])
assert km.serializar(newmod) == newpath.read_bytes()
assert old.keys() <= new.keys()
assert all(new[sid] == record for sid,record in old.items()), 'Existing data changed'
assert new.keys()-old.keys() == {f'{n}-KenshiShop.mod'.encode() for n in range(8700,8705)}
for i in range(5):
    r = new[f'870{i}-KenshiShop.mod'.encode()]
    source = old[f'860{i}-KenshiShop.mod'.encode()]
    assert r['typecode'] == 72
    expected = km.clonar_registro(source,'expected')['extra']
    if i==4:
        for cat,rows in expected:
            if cat in [b'Squad AI Goals',b'Squad2 AI Goals']: rows.append((b'1166-gamedata.base',0,24,0))
    assert r['extra'] == expected, 'Unexpected jobs/schedules/targets/care delta'
    assert km.campo(r,'long','unloaded func') == 5
    assert km.campo(r,'long','signal func') == 0
    a,b = dict(source),dict(r)
    for record in (a,b):
        record.pop('extra')
        for key in ('id','strid','name'): record.pop(key)
        record['long'] = [(k,v) for k,v in record['long'] if k not in (b'unloaded func',b'signal func')]
    assert a==b, 'Unexpected package delta'
for r in newmod['records']:
    for cat,rows in r['extra']:
        for sid,*_ in rows:
            if sid.endswith(b'-KenshiShop.mod'): assert sid in new,(r['strid'],sid)
with tempfile.TemporaryDirectory() as folder:
    rebuilt=Path(folder)/'rebuilt.mod'
    build(oldpath,rebuilt)
    assert rebuilt.read_bytes()==newpath.read_bytes()
print('PASS reproducible binary; every alpha.86 record unchanged; exactly five work packages added')
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

protected = subprocess.check_output(['git','ls-tree','-r','--name-only','v0.3.0-alpha.86'],cwd=ROOT,text=True).splitlines()
protected = [p for p in protected if '/Building/' in p or p.startswith('KenshiShop_LegendaryCompat/') or p.endswith('/Catalog.lua') or 'Furniture' in p or '/Floor' in p or '/Layout' in p]
for path in protected:
    original = subprocess.check_output(['git','show','v0.3.0-alpha.86:'+path],cwd=ROOT)
    assert (ROOT/path).read_bytes() == original,path
print('PASS',len(protected),'physical building/furniture/layout, stock and compatibility files unchanged')
