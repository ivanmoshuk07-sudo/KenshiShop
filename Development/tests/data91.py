"""Validate scoped native protection, with all alpha90 gameplay data retained."""
import json,subprocess,sys,hashlib,struct
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'Development'))
import kenshimod as km
oldpath,newpath=map(Path,sys.argv[1:3])
mod=km.ler(newpath);assert km.serializar(mod)==newpath.read_bytes() and len(mod['records'])==227
# Release labels are metadata. All other header fields and gameplay bytes must
# remain identical to the known alpha.90 data, including every record and layout.
baseline=km.ler(oldpath);description=mod['description']
mod['description']=baseline['description']
assert km.serializar(mod)==oldpath.read_bytes(),'Only the FCS release description may change'
mod['description']=description
by={r['strid']:r for r in mod['records']}
races=[r for r in mod['records'] if r['typecode']==7]
assert len(races)==14
limbs={f'700{i}-KenshiShop.mod'.encode() for i in range(1,5)}
for race in races:assert limbs<={row[0] for row in dict(race['extra'])[b'combat anatomy']}
for sid in limbs:assert dict(by[sid]['bool'])[b'severance']==0
print('PASS alpha90 gameplay bytes identical; all 227 records, rescue continuation, shifts and race stats preserved; release description may differ')
paths=subprocess.check_output(['git','ls-tree','-r','--name-only','v0.3.0-alpha.90'],cwd=ROOT,text=True).splitlines()
protected=[p for p in paths if '/Building/' in p or p.startswith('KenshiShop_LegendaryCompat/') or p.endswith('/Catalog.lua') or 'Furniture' in p or '/Floor' in p or '/Layout' in p]
protected+=['KenshiShop/scripts/Core/NPC/'+name+'.lua' for name in ['RoleAI','NativeCare','NativeNodes','PostDuty','PostJobs','PostData','Transport','HomeAssignment','OriginTown','ServiceTown']]
for path in protected:
 assert (ROOT/path).read_bytes()==subprocess.check_output(['git','show','v0.3.0-alpha.90:'+path],cwd=ROOT),path
print('PASS',len(protected),'protected physical/stock/compatibility and working AI/delivery/post/city files unchanged')
import hashlib,struct
meta=json.loads((ROOT/'Development/references/native_no_sever91.json').read_text())
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

for public_name in [b'GetRealAddress@KenshiLib',b'AddHook@KenshiLib',b'amputate@MedicalSystem',b'crushLimb@MedicalSystem',b'notifyRaceChange@MedicalSystem',b'_DESTRUCTOR@MedicalSystem']:
 assert public_name in dll,public_name
print('PASS native hook exports, new compiled DLL/source hashes and unchanged node-factory export')
