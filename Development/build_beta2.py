"""Beta 2: private native goals with emergency 3 / rescue 2 / work 1.

Input is the beta.1 binary. Existing definitions remain available to saved
platoons; only the initial care package changes its two rescue references.
"""
from pathlib import Path
import sys

import kenshimod as km


# Target finders/ending semantics match the vanilla task definitions recorded
# in references/native_ai.json; follow141 and home239 were cross-checked in
# the supplied vanilla AiTask dump. No original game task is overridden.
WORK = [
    (10010, '1170-gamedata.base', 20, 0, 'Shopkeeper'),
    (10011, '3104-gamedata.base', 86, 0, 'Open shop doors'),
    (10012, '8505-KenshiShop.mod', 268, 0, 'Indoor guard'),
    (10013, '1188-gamedata.base', 38, 0, 'Guard building'),
    (10014, '965-gamedata.base', 36, 0, 'Patrol town'),
    (10015, '1166-gamedata.base', 141, 2, 'Follow leader'),
    (10016, '46053-rebirth.mod', 239, 0, 'Go home and rest'),
]


def build(source, destination):
    mod = km.ler(source)
    assert km.serializar(mod) == source.read_bytes()
    by = {record['strid']: record for record in mod['records']}
    assert len(mod['records']) == 227 and b'10000-KenshiShop.mod' not in by, 'Input must be beta.1'

    def clone(source_id, number, name):
        record = km.clonar_registro(by[source_id.encode()], f'{number}-KenshiShop.mod', name)
        record['id'] = number
        mod['records'].append(record)
        return record

    def value(record, key, number):
        assert km.set_campo(record, 'long', key, number)

    mapping = {
        b'9005-KenshiShop.mod': b'10005-KenshiShop.mod',
        b'9006-KenshiShop.mod': b'10006-KenshiShop.mod',
    }
    for number, task, name in [(10005, 148, 'Rescue'), (10006, 106, 'Carry to bed')]:
        record = clone('8505-KenshiShop.mod', number, 'KSB2 ' + name)
        value(record, 'enum', task)
        value(record, 'classification', 2)
    for number, original, task, targeting, name in WORK:
        record = clone('8505-KenshiShop.mod', number, 'KSB2 ' + name)
        value(record, 'enum', task)
        value(record, 'classification', 1)
        value(record, 'targeting', targeting)
        mapping[original.encode()] = record['strid']

    def update_goals(record):
        for category, rows in record['extra']:
            if b'AI Goals' in category:
                rows[:] = [(mapping.get(sid, sid), start, end, weight)
                           for sid, start, end, weight in rows]

    for index in range(5):
        original = by[f'900{index}-KenshiShop.mod'.encode()]
        record = clone(f'900{index}-KenshiShop.mod', 10000 + index,
                       original['name'].decode().replace('KS90', 'KSB2'))
        update_goals(record)

    # New/unarrived squads get the same rescue hierarchy before work handoff.
    update_goals(by[b'7604-KenshiShop.mod'])
    helper = clone('9007-KenshiShop.mod', 10007, 'KSB2 Carry continuation for existing carriers')
    update_goals(helper)
    mod['description'] = (
        b'KenshiShop 1.0 beta.2: all roles use native emergency protection/medical priority 3, '
        b'rescue and carry-to-bed priority 2, work/posts priority 1. Furniture, stock, '
        b'shifts and native limb protection retained.'
    )
    mod['unknown'] = max(mod['unknown'], 10100)
    km.gravar(destination, mod)
    assert km.serializar(km.ler(destination)) == destination.read_bytes()
    print('beta.2 written:', len(mod['records']), 'records; 226 old records unchanged; 15 private definitions added')


if __name__ == '__main__':
    build(*map(Path, sys.argv[1:3]))
