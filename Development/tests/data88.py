"""Alpha.88 changes Lua node coordinates only. FCS data must remain byte-identical."""
import json,re,subprocess,sys
from collections import Counter
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'Development'))
import kenshimod as km
oldpath,newpath=map(Path,sys.argv[1:3])
assert oldpath.read_bytes()==newpath.read_bytes(),'FCS data, including patrol and stock, must remain unchanged'
mod=km.ler(newpath)
assert len(mod['records'])==219
assert km.serializar(mod)==newpath.read_bytes()
for name in ['RoleAI','NativeActivation','Transport','HomeAssignment','OriginTown','ServiceTown','Duty']:
    path='KenshiShop/scripts/Core/NPC/'+name+'.lua'
    assert (ROOT/path).read_bytes()==subprocess.check_output(['git','show','v0.3.0-alpha.87:'+path],cwd=ROOT),path
print('PASS byte-identical .mod; all 219 records and patrol packages retained; role/activation/delivery/city code unchanged')
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

protected = subprocess.check_output(['git','ls-tree','-r','--name-only','v0.3.0-alpha.87'],cwd=ROOT,text=True).splitlines()
protected = [p for p in protected if '/Building/' in p or p.startswith('KenshiShop_LegendaryCompat/') or p.endswith('/Catalog.lua') or 'Furniture' in p or '/Floor' in p or '/Layout' in p]
for path in protected:
    original = subprocess.check_output(['git','show','v0.3.0-alpha.87:'+path],cwd=ROOT)
    assert (ROOT/path).read_bytes() == original,path
print('PASS',len(protected),'physical building/furniture/layout, stock and compatibility files unchanged')
