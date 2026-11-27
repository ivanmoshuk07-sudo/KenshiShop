"""Audit the new building, its operator and the unchanged beta.8.2 records."""
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'Development'))

import kenshimod as km
from build_beta8_3 import (BUILDING, DESCRIPTION, DISPOSE_CORPSE, DUTY, JOE,
                           MARTIAL_ARTS_GEAR, RESEARCH, RESCUE_GOALS,
                           SEARCH_CORPSE, SQUAD, STATS, TRANSIT, sid)


def main():
    path = 'KenshiShop/KenshiShop.mod'
    original = subprocess.check_output(['git', 'show', f'v1.0-beta.8.2:{path}'], cwd=ROOT)
    with tempfile.NamedTemporaryFile() as source:
        source.write(original)
        source.flush()
        baseline = km.ler(source.name)

    updated = km.ler(ROOT / path)
    added = {sid(number) for number in (BUILDING, RESEARCH, JOE, SQUAD, DUTY, TRANSIT, STATS)}
    by_id = {r['strid']: r for r in updated['records']}
    assert updated['description'] == DESCRIPTION and updated['unknown'] == 11700
    assert by_id.keys() - {r['strid'] for r in baseline['records']} == added

    building = by_id[sid(BUILDING)]
    assert building['typecode'] == 0
    assert dict(building['string'])[b'building category'] == b'KenshiShop'
    assert dict(building['long'])[b'power output'] == 0
    assert dict(building['extra'])[b'functionality'] == [(b'4004-gamedata.base', 0, 0, 0)]
    assert dict(building['extra'])[b'construction'] == [(b'42159-gamedata.base', 8, 0, 0)]
    assert dict(building['extra'])[b'parts'] == [(b'3964-gamedata.base', 0, 100, 0), (b'3971-gamedata.base', 0, 100, 0)]

    research = by_id[sid(RESEARCH)]
    assert research['typecode'] == 21 and dict(research['long'])[b'level'] == 4
    assert not dict(research['bool'])[b'blueprint only']
    assert dict(research['extra'])[b'requirements'] == [(b'2091-gamedata.base', 0, 0, 0)]
    assert dict(research['extra'])[b'enable buildings'] == [(sid(BUILDING), 0, 0, 0)]

    squad = by_id[sid(SQUAD)]
    squad_refs = dict(squad['extra'])
    assert squad['typecode'] == 52 and dict(squad['bool'])[b'dont multiply']
    assert squad_refs[b'leader'] == [(sid(JOE), 1, 0, 0)] and not squad_refs.get(b'squad')
    assert squad_refs[b'faction'] == [(sid(400), 0, 0, 0)]
    assert squad_refs[b'race override'] == [(sid(7101), 100, 0, 0)]
    assert squad_refs[b'AI packages'] == [(sid(TRANSIT), 0, 0, 0)]
    joe = by_id[sid(JOE)]
    guard = by_id[sid(7302)]
    assert joe['name'] == 'Могильщик Джо'.encode()
    stats = dict(joe['long'])
    gear = dict(joe['extra'])
    assert joe['typecode'] == 1 and not dict(joe['bool'])[b'unique'] and not dict(joe['bool'])[b'named']
    assert stats[b'combat stats'] == dict(guard['long'])[b'combat stats'] == stats[b'unarmed stats'] == 35
    assert not gear.get(b'weapons') and not gear.get(b'weapon level')
    assert [ref[0] for ref in gear[b'clothing']] == list(MARTIAL_ARTS_GEAR)
    assert gear[b'inventory'] == dict(guard['extra'])[b'inventory']
    assert gear[b'stats'] == [(sid(STATS), 0, 100, 0)]
    skills = dict(by_id[sid(STATS)]['float'])
    assert skills[b'dodge'] == skills[b'unarmed'] == 35

    assert by_id[sid(DUTY)]['name'] == b'KS Undertaker duty'
    for category, goals in by_id[sid(DUTY)]['extra']:
        assert b'AI Goals' in category
        assert DISPOSE_CORPSE in goals and SEARCH_CORPSE in goals
        assert {b'1360-gamedata.base', sid(7603), b'2825-gamedata.base', b'1535072-rebirth.mod'} <= {
            goal[0] for goal in goals
        }
        assert not any(goal[0] in RESCUE_GOALS for goal in goals)
    for _, goals in by_id[sid(TRANSIT)]['extra']:
        assert not any(goal[0] in RESCUE_GOALS | {DISPOSE_CORPSE[0], SEARCH_CORPSE[0]} for goal in goals)

    updated['records'] = [r for r in updated['records'] if r['strid'] not in added]
    updated['description'], updated['unknown'] = baseline['description'], baseline['unknown']
    assert km.serializar(updated) == original
    for name in ('KenshiShop/scripts/Core/NPC/Transport.lua', 'KenshiShop/scripts/Core/NPC/NativeCare.lua',
                 'KenshiShop/native/KenshiShopNative.dll', 'KenshiShop_LegendaryCompat/KenshiShop_LegendaryCompat.mod'):
        prior = subprocess.check_output(['git', 'show', f'v1.0-beta.8.2:{name}'], cwd=ROOT)
        assert (ROOT / name).read_bytes() == prior, name
    print('PASS original game data preserved. Level IV crematorium, one unarmed guard and native corpse disposal verified.')


if __name__ == '__main__':
    main()
