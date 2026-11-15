"""Alpha.85 -> alpha.86: service-town packages only; retain all existing records."""
import sys
from pathlib import Path
import kenshimod as km

def build(src, dst):
    mod = km.ler(src)
    assert km.serializar(mod) == src.read_bytes()
    by = {r['strid']: r for r in mod['records']}
    assert b'8600-KenshiShop.mod' not in by, 'Input must be alpha.85'
    for i in range(5):
        old = by[f'850{i}-KenshiShop.mod'.encode()]
        label = old['name'].decode().replace('KS85', 'KS86')
        record = km.clonar_registro(old, f'860{i}-KenshiShop.mod', label)
        record['id'] = 8600+i
        # No safe/home-town signal should redirect a permanent service role.
        # Offscreen native travel uses missionTown, not the distant origin.
        for key, value in [('signal func', 0), ('unloaded func', 5)]:
            assert km.set_campo(record, 'long', key, value)
        mod['records'].append(record)
    mod['description'] = b'KenshiShop alpha.86 test: stable NPC origin; player service town via native missionTown. Furniture, nodes and stock unchanged. Gameplay unverified.'
    mod['unknown'] = max(mod['unknown'], 8700)
    km.gravar(dst, mod)
    assert km.serializar(km.ler(dst)) == dst.read_bytes()
    print('alpha.86 written:', len(mod['records']), 'records')

if __name__ == '__main__':
    build(*map(Path, sys.argv[1:3]))
