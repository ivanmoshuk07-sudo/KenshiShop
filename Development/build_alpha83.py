"""Apply alpha.83 to alpha.82. No building, layout or furniture changes."""
import sys
from pathlib import Path
import kenshimod as km
src,dst=map(Path,sys.argv[1:3]);m=km.ler(src);by={r['strid']:r for r in m['records']}
assert km.serializar(m)==src.read_bytes()
for i,name in enumerate(['Trader 24h','Trader 06-23','Indoor guards','Police chief','Town patrol']):
    r=km.clonar_registro(by[f'820{i}-KenshiShop.mod'.encode()],f'830{i}-KenshiShop.mod','KS83 '+name)
    r['id']=8300+i
    m['records'].append(r)
m['description']=b'KenshiShop alpha.83: compatible location goals, stable original vendor IDs, engineering technology lists and bounded movement recovery. No furniture changes. In-game verification required.'
m['unknown']=max(m['unknown'],8400)
km.gravar(dst,m)
assert km.serializar(km.ler(dst))==dst.read_bytes()
print('alpha.83 data written:',len(m['records']),'records')
