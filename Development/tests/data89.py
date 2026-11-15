"""Alpha.89 changes native job subjects and shift flags only. FCS data must remain byte-identical."""
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
for name in ['RoleAI','NativeActivation','Transport','HomeAssignment','OriginTown','ServiceTown']:
    path='KenshiShop/scripts/Core/NPC/'+name+'.lua'
    assert (ROOT/path).read_bytes()==subprocess.check_output(['git','show','v0.3.0-alpha.88:'+path],cwd=ROOT),path
print('PASS byte-identical .mod; all 219 records and patrol packages retained; role/activation/delivery/city code unchanged; shifts and native post jobs may change')
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

protected = subprocess.check_output(['git','ls-tree','-r','--name-only','v0.3.0-alpha.88'],cwd=ROOT,text=True).splitlines()
protected = [p for p in protected if '/Building/' in p or p.startswith('KenshiShop_LegendaryCompat/') or p.endswith('/Catalog.lua') or 'Furniture' in p or '/Floor' in p or '/Layout' in p]
for path in protected:
    original = subprocess.check_output(['git','show','v0.3.0-alpha.88:'+path],cwd=ROOT)
    assert (ROOT/path).read_bytes() == original,path
print('PASS',len(protected),'physical building/furniture/layout, stock and compatibility files unchanged')

# Distribute only our compiled bridge; inspect its PE metadata without loading it.
import hashlib,struct
meta=json.loads((ROOT/'Development/references/native_posts89.json').read_text())
dll=(ROOT/'KenshiShop/native/KenshiShopNative.dll').read_bytes()
assert hashlib.sha256(dll).hexdigest()==meta['bridge']['dll_sha256']
for path,digest in meta['bridge']['source_sha256'].items():
    assert hashlib.sha256((ROOT/path).read_bytes()).hexdigest()==digest,path
nt=struct.unpack_from('<I',dll,0x3c)[0]
assert dll[:2]==b'MZ' and dll[nt:nt+4]==b'PE\0\0'
assert struct.unpack_from('<H',dll,nt+4)[0]==0x8664
opt=nt+24
assert struct.unpack_from('<H',dll,opt)[0]==0x20b
sections=[]
for i in range(struct.unpack_from('<H',dll,nt+6)[0]):
    off=opt+struct.unpack_from('<H',dll,nt+20)[0]+40*i
    sections.append(struct.unpack_from('<IIII',dll,off+8))
def offset(rva):
    for vsize,va,size,raw in sections:
        if va<=rva<va+max(vsize,size):return raw+rva-va
    raise AssertionError(hex(rva))
def u32(off):return struct.unpack_from('<I',dll,off)[0]
def string(rva):return dll[offset(rva):].split(b'\0',1)[0].decode()
export=offset(u32(opt+112));count=u32(export+24);names=offset(u32(export+32))
assert [string(u32(names+4*i)) for i in range(count)]==['luaopen_KenshiShopNative']
imports=[];at=offset(u32(opt+120))
while any(dll[at:at+20]):
    imports.append(string(u32(at+12)));at+=20
assert imports==['KERNEL32.dll'],imports
assert b'createLocationNode@RootObjectFactory' in dll
print('PASS Windows x64 bridge export, only KERNEL32 import, exact tested DLL/source hashes; no game DLLs distributed')
