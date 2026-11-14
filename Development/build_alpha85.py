"""Apply alpha.85 to alpha.84; change NPC data only, never physical interiors.

Native task settings are documented in references/native_ai.json. These are
permanent roles, not the timed mercenary contract and its travel/expiry goals.
"""
import sys
from pathlib import Path
import kenshimod as km

def build(src, dst):
    m = km.ler(src)
    assert km.serializar(m) == src.read_bytes()
    by = {r['strid']: r for r in m['records']}
    assert b'8500-KenshiShop.mod' not in by, 'Input must be alpha.84'

    def setv(r, section, key, value):
        if not km.set_campo(r, section, key, value):
            r[section].append((key.encode(), value))

    def refs(r, key, rows):
        r['extra'] = [(k, v) for k, v in r['extra'] if k != key.encode()]
        r['extra'].append((key.encode(), rows))

    # Copy the original indoor-only guard task's four scalar settings.
    guard = km.clonar_registro(by[b'8001-KenshiShop.mod'], '8505-KenshiShop.mod', 'KS85 Indoor guard native targeting')
    guard['id'] = 8505
    for key, value in [('enum', 268), ('classification', 2), ('ending', 0), ('targeting', 0)]:
        setv(guard, 'long', key, value)
    m['records'].append(guard)

    def row(sid, start=0, end=24, weight=0):
        return (sid.encode(), start, end, weight)

    care = [row('1360-gamedata.base'), row('7603-KenshiShop.mod'), row('51395-rebirth.mod')]
    protection = [row('2825-gamedata.base'), row('1535072-rebirth.mod')]
    # Native ordinary work legitimately uses weight 0 (e.g. Shop-24hr).
    # Preserve native targeting instead of targeting the character itself.
    for i, name in enumerate(['Trader 24h', 'Trader 06-23', 'Indoor guards', 'Police chief', 'Town patrol']):
        p = km.clonar_registro(by[f'840{i}-KenshiShop.mod'.encode()], f'850{i}-KenshiShop.mod', 'KS85 ' + name)
        p['id'] = 8500 + i
        p['extra'] = []
        for key, value in [('clears existing jobs', 0), ('signal func', 2 if i < 2 else 0), ('unloaded func', 0 if i == 4 else 4)]:
            setv(p, 'long', key, value)
        for category in ['Leader AI Goals', 'Squad AI Goals', 'Squad2 AI Goals']:
            jobs = list(care) + list(protection)
            if i < 2:
                start, end = (6, 23) if i == 1 else (0, 24)
                jobs += [row('1170-gamedata.base', start, end), row('3104-gamedata.base', start, end)]
                if i == 1:
                    # Secure home/sleep uses the native task's target finder.
                    jobs += [row('46053-rebirth.mod', 0, 6), row('46053-rebirth.mod', 23, 24)]
            elif i == 2:
                jobs += [row('8505-KenshiShop.mod')]
            elif i == 3:
                jobs += [row('1188-gamedata.base')]
            else:
                # Like the native patrol town 24hr package, the leader patrols;
                # followers retain native platoon following and emergency care.
                if category == 'Leader AI Goals':
                    jobs += [row('965-gamedata.base')]
            refs(p, category, jobs)
        m['records'].append(p)

    # Before arrival: emergency care only. Work is installed by the bounded
    # native handoff after arrival, including migration of existing saves.
    for n in [300, 303, 305, 307, 309, 310, 311, 7800, 7801, 7802, 7803]:
        refs(by[f'{n}-KenshiShop.mod'.encode()], 'AI packages', [row('7604-KenshiShop.mod', 0, 0)])
    m['description'] = b'KenshiShop alpha.85: 72 original logical nodes; native residence and role AI handoff. Furniture and stock unchanged. In-game validation required.'
    m['unknown'] = max(m['unknown'], 8600)
    km.gravar(dst, m)
    assert km.serializar(km.ler(dst)) == dst.read_bytes()
    print('alpha.85 written:', len(m['records']), 'records')

if __name__ == '__main__':
    build(*map(Path, sys.argv[1:3]))
