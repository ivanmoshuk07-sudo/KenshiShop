"""Validate rescue/patrol changes, protected races and untouched furniture/stock."""
import json,subprocess,sys,copy
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'Development'))
import kenshimod as km
oldpath,newpath=map(Path,sys.argv[1:3])
old=km.ler(oldpath);mod=km.ler(newpath)
assert km.serializar(mod)==newpath.read_bytes()
by={r['strid']:r for r in mod['records']};previous={r['strid']:r for r in old['records']}
assert len(old['records'])==219 and len(mod['records'])==227
assert set(by)-set(previous)=={f'{n}-KenshiShop.mod'.encode() for n in range(9000,9008)}
for sid,r in previous.items():
    if sid!=b'7604-KenshiShop.mod':assert by[sid]==r,sid
care=copy.deepcopy(previous[b'7604-KenshiShop.mod'])
for cat,rows in care['extra']:
    for i,row in enumerate(list(rows)):
        if row[0]==b'51395-rebirth.mod':
            rows[i:i+1]=[(b'9005-KenshiShop.mod',0,24,0),(b'9006-KenshiShop.mod',0,24,110)]
assert by[b'7604-KenshiShop.mod']==care
for n,enum in [(9005,148),(9006,106)]:
    r=by[f'{n}-KenshiShop.mod'.encode()]
    assert r['typecode']==22 and dict(r['long'])=={b'enum':enum,b'classification':3,b'ending':0,b'targeting':0}
for n in range(9000,9005):
    r=by[f'{n}-KenshiShop.mod'.encode()];assert r['typecode']==72
    for cat,rows in r['extra']:
        if b'AI Goals' not in cat:continue
        assert (b'9005-KenshiShop.mod',0,24,0) in rows
        assert (b'9006-KenshiShop.mod',0,24,110) in rows
        assert not any(x[0]==b'51395-rebirth.mod' for x in rows)
        if n==9004:
            for sid,a,b,c in rows:
                if sid in [b'965-gamedata.base',b'1166-gamedata.base']:assert (a,b)==(6,23)
    if n==9004:
        refs=dict(r['extra'])
        assert (b'965-gamedata.base',6,23,0) in refs[b'Leader AI Goals']
        for cat in [b'Squad AI Goals',b'Squad2 AI Goals']:
            assert (b'1166-gamedata.base',6,23,0) in refs[cat]
assert by[b'9007-KenshiShop.mod']['extra']==[(b'Leader AI Goals',[(b'9006-KenshiShop.mod',0,24,110)])]
print('PASS 218 original records unchanged; pre-arrival care updated; native rescue and carry-to-bed above normal posts; patrol/follow 06-23')

races=[r for r in mod['records'] if r['typecode']==7]
assert len(races)==14 and all(r['name'].startswith(b'KS NoSever:') for r in races)
limbs={f'700{n}-KenshiShop.mod'.encode() for n in range(1,5)}
for sid in limbs:
    part=by[sid];assert part['typecode']==16 and dict(part['bool'])[b'severance']==0
for race in races:
    anatomy=dict(race['extra'])[b'combat anatomy']
    parts={sid for sid,*values in anatomy}
    assert limbs<=parts
    for sid in parts & by.keys():
        part=by[sid]
        if part['typecode']==16 and dict(part['long']).get(b'body part type') in [1,2]:
            assert dict(part['bool'])[b'severance']==0
    assert race==previous[race['strid']]
print('PASS all 14 custom NoSever races retain four protected limbs, original HP/stats and anatomy; vanilla races not edited')

paths=subprocess.check_output(['git','ls-tree','-r','--name-only','v0.3.0-alpha.89'],cwd=ROOT,text=True).splitlines()
protected=[p for p in paths if '/Building/' in p or p.startswith('KenshiShop_LegendaryCompat/') or p.endswith('/Catalog.lua') or 'Furniture' in p or '/Floor' in p or '/Layout' in p]
protected+=['KenshiShop/scripts/Core/NPC/PostData.lua','KenshiShop/scripts/Core/NPC/Transport.lua','KenshiShop/scripts/Core/NPC/HomeAssignment.lua','KenshiShop/scripts/Core/NPC/OriginTown.lua','KenshiShop/scripts/Core/NPC/ServiceTown.lua']
for path in protected:
    assert (ROOT/path).read_bytes()==subprocess.check_output(['git','show','v0.3.0-alpha.89:'+path],cwd=ROOT),path
print('PASS',len(protected),'protected stock/furniture/compatibility, original 72 post definitions, delivery and town assignment files unchanged')


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
