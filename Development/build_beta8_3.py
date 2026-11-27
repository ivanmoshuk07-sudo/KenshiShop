"""Add the staffed crematorium using vanilla building and undertaker data."""
import argparse
from pathlib import Path

import kenshimod as km


DESCRIPTION = b'KenshiShop 1.0 beta.8.3: staffed crematorium and native undertaker duty.'
BUILDING, RESEARCH, JOE, SQUAD, DUTY, TRANSIT, STATS = (106, 206, 11600, 11601, 11602, 11603, 11604)
SEARCH_CORPSE = (b'2680-gamedata.base', 0, 24, 100)
DISPOSE_CORPSE = (b'2679-gamedata.base', 0, 24, 200)
RESCUE_GOALS = {b'10005-KenshiShop.mod', b'10006-KenshiShop.mod'}
MARTIAL_ARTS_GEAR = (
    b'564-gamedata.base',   # Gi
    b'2193-gamedata.base',  # Gi Pants
    b'2326-gamedata.base',  # Martial Artist Bindings
    b'557-gamedata.base',   # Wooden Sandals
)


def sid(number):
    return f'{number}-KenshiShop.mod'.encode()


def merged(base, overrides):
    record = dict(base)
    for name in [*(section[0] for section in km.SECOES), 'extra']:
        fields = dict(base[name])
        fields.update(overrides[name])
        record[name] = list(fields.items())
    return record


def build(source, vanilla_dir, destination):
    mod = km.ler(source)
    assert km.serializar(mod) == source.read_bytes()
    assert mod['description'].startswith(b'KenshiShop 1.0 beta.8.2:') and mod['unknown'] == 11600
    assert len(mod['records']) == 288
    by_id = {record['strid']: record for record in mod['records']}
    base = {r['strid']: r for r in km.ler(vanilla_dir / 'gamedata.base')['records']}
    overrides = {r['strid']: r for r in km.ler(vanilla_dir / 'rebirth.mod')['records']}
    for goal, task in ((DISPOSE_CORPSE, 137), (SEARCH_CORPSE, 138)):
        record = base[goal[0]]
        assert record['typecode'] == 22
        assert dict(record['long']) == {b'classification': 2, b'ending': 0, b'enum': task, b'targeting': 0}
    vanilla_undertaker = dict(overrides[b'1533839-rebirth.mod']['extra'])[b'Leader AI Goals']
    assert DISPOSE_CORPSE in vanilla_undertaker and SEARCH_CORPSE in vanilla_undertaker

    def add(original, number, name):
        assert sid(number) not in by_id
        record = km.clonar_registro(original, sid(number), name)
        record.update(id=number, mod_data_type=16)
        mod['records'].append(record)
        return record

    furnace = b'3962-gamedata.base'
    building = add(merged(base[furnace], overrides[furnace]), BUILDING, 'KS: Крематорий')
    component = dict(building['extra'])[b'functionality']
    assert len(component) == 1 and dict(base[component[0][0]]['long'])[b'function'] == 11
    assert km.set_campo(building, 'string', 'building category', 'KenshiShop')
    assert km.set_campo(building, 'string', 'Description', 'Городской крематорий. Могильщик Джо собирает и сжигает тела погибших.')

    research = add(by_id[sid(205)], RESEARCH, 'KS: Крематорий (IV)')
    assert km.set_campo(research, 'long', 'level', 4)
    assert km.set_campo(research, 'string', 'description', 'Открывает крематорий и назначает могильщика на службу.')
    costs = dict(research['extra'])[b'cost']
    research['extra'] = [(b'cost', costs),
                         (b'requirements', [(b'2091-gamedata.base', 0, 0, 0)]),
                         (b'enable buildings', [(sid(BUILDING), 0, 0, 0)])]

    guard = by_id[sid(7302)]
    guard_stats_id = dict(guard['extra'])[b'stats'][0][0]
    stats = add(merged(base[guard_stats_id], overrides[guard_stats_id]), STATS, 'KS Undertaker stats')
    combat = dict(guard['long'])[b'combat stats']
    for field in ('dodge', 'unarmed'):
        assert km.set_campo(stats, 'float', field, float(combat))

    joe = add(guard, JOE, 'Могильщик Джо')
    assert km.set_campo(joe, 'long', 'female chance', 0)
    assert km.set_campo(joe, 'long', 'unarmed stats', combat)
    assert km.set_campo(joe, 'bool', 'assigns bounties', 0)
    filters = {b'clothing', b'dialogue package', b'stats', b'weapons', b'weapon level'}
    joe['extra'] = [(category, refs) for category, refs in joe['extra'] if category not in filters]
    joe['extra'] += [(b'clothing', [(gear, 1, 100, 0) for gear in MARTIAL_ARTS_GEAR]),
                     (b'stats', [(sid(STATS), 0, 100, 0)])]

    transit = add(by_id[sid(7604)], TRANSIT, 'KS Undertaker delivery')
    for _, goals in transit['extra']:
        goals[:] = [goal for goal in goals if goal[0] not in RESCUE_GOALS]

    duty = add(by_id[sid(10002)], DUTY, 'KS Undertaker duty')
    for _, goals in duty['extra']:
        goals[:] = [goal for goal in goals if goal[0] not in RESCUE_GOALS | {sid(10012)}]
        goals.extend((DISPOSE_CORPSE, SEARCH_CORPSE, (sid(10013), 0, 24, 0)))

    squad = add(by_id[sid(310)], SQUAD, 'KS Crematorium: Undertaker (1)')
    assert km.set_campo(squad, 'bool', 'dont multiply', 1)
    assert km.set_campo(squad, 'long', 'building designation', 0)
    squad['extra'] = [(b'race override', [(sid(7101), 100, 0, 0)]),
                      (b'faction', [(sid(400), 0, 0, 0)]),
                      (b'leader', [(sid(JOE), 1, 0, 0)]),
                      (b'AI packages', [(sid(TRANSIT), 0, 0, 0)])]

    mod['unknown'] = 11700
    mod['description'] = DESCRIPTION
    km.gravar(destination, mod)
    assert km.serializar(km.ler(destination)) == destination.read_bytes()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('vanilla_dir', type=Path)
    parser.add_argument('destination', type=Path)
    args = parser.parse_args()
    build(args.source, args.vanilla_dir, args.destination)
