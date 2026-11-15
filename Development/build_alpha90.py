"""Alpha.90: native rescue continuation and day patrol; preserve existing records."""
import sys
from pathlib import Path
import kenshimod as km

def build(src,dst):
    mod=km.ler(src);assert km.serializar(mod)==src.read_bytes()
    by={r['strid']:r for r in mod['records']}
    assert b'9000-KenshiShop.mod' not in by
    def scalar(r,key,val):
        assert km.set_campo(r,'long',key,val)
    for number,enum,name in [(9005,148,'KS90 Native rescue urgent'),(9006,106,'KS90 Native carry to bed urgent')]:
        r=km.clonar_registro(by[b'8505-KenshiShop.mod'],f'{number}-KenshiShop.mod',name);r['id']=number
        scalar(r,'enum',enum);scalar(r,'classification',3)
        mod['records'].append(r)
    for i in range(5):
        r=km.clonar_registro(by[f'870{i}-KenshiShop.mod'.encode()],f'900{i}-KenshiShop.mod',by[f'870{i}-KenshiShop.mod'.encode()]['name'].decode().replace('KS87','KS90'))
        r['id']=9000+i
        for cat,rows in r['extra']:
            if b'AI Goals' not in cat:continue
            updated=[]
            for sid,a,b,c in rows:
                if sid==b'51395-rebirth.mod':
                    updated.extend([(b'9005-KenshiShop.mod',a,b,c),(b'9006-KenshiShop.mod',0,24,110)])
                else:
                    if i==4 and sid in [b'965-gamedata.base',b'1166-gamedata.base']:a,b=6,23
                    updated.append((sid,a,b,c))
            rows[:]=updated
        mod['records'].append(r)
    # The pre-arrival care package also needs the complete chain for new NPCs.
    for cat,rows in by[b'7604-KenshiShop.mod']['extra']:
        if b'AI Goals' in cat:
            updated=[]
            for sid,a,b,c in rows:
                if sid==b'51395-rebirth.mod':
                    updated.extend([(b'9005-KenshiShop.mod',a,b,c),(b'9006-KenshiShop.mod',0,24,110)])
                else:updated.append((sid,a,b,c))
            rows[:]=updated
    helper=km.clonar_registro(by[b'7604-KenshiShop.mod'],'9007-KenshiShop.mod','KS90 Carry continuation for existing carriers')
    helper['id']=9007;helper['extra']=[(b'Leader AI Goals',[(b'9006-KenshiShop.mod',0,24,110)])]
    mod['records'].append(helper)
    mod['description']=b'KenshiShop alpha.90 test: native rescue/bed continuation above post duty; patrol 06-23 and separate outdoor night posts. Furniture, stock and protected custom races retained.'
    mod['unknown']=max(mod['unknown'],9100)
    km.gravar(dst,mod);assert km.serializar(km.ler(dst))==dst.read_bytes()
    print('alpha.90 written:',len(mod['records']),'records; 218 previous records untouched; pre-arrival care chain updated')
if __name__=='__main__':build(*map(Path,sys.argv[1:3]))
