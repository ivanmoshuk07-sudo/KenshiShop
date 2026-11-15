"""Alpha.86 -> alpha.87: explicit native patrol followers; all old records retained."""
import sys
from pathlib import Path
import kenshimod as km

def build(src,dst):
    mod=km.ler(src)
    assert km.serializar(mod)==src.read_bytes()
    by={r['strid']:r for r in mod['records']}
    assert b'8700-KenshiShop.mod' not in by
    for i in range(5):
        old=by[f'860{i}-KenshiShop.mod'.encode()]
        record=km.clonar_registro(old,f'870{i}-KenshiShop.mod',old['name'].decode().replace('KS86','KS87'))
        record['id']=8700+i
        if i==4:
            for cat,rows in record['extra']:
                if cat in [b'Squad AI Goals',b'Squad2 AI Goals']:
                    rows.append((b'1166-gamedata.base',0,24,0))
        mod['records'].append(record)
    mod['description']=b'KenshiShop alpha.87 test: native patrol followers, one-time planner cache refresh and native post-finder audit. Furniture, stock and post coordinates unchanged.'
    mod['unknown']=max(mod['unknown'],8800)
    km.gravar(dst,mod)
    assert km.serializar(km.ler(dst))==dst.read_bytes()
    print('alpha.87 written:',len(mod['records']),'records')
if __name__=='__main__':build(*map(Path,sys.argv[1:3]))
