"""Verify custom Hive health limits and preserve unrelated FCS data."""
from copy import deepcopy
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'Development'))
import kenshimod as km


source, destination = map(Path, sys.argv[1:3])
before = km.ler(source)
after = km.ler(destination)
assert km.serializar(before) == source.read_bytes()
assert km.serializar(after) == destination.read_bytes()
assert after['description'].startswith(b'KenshiShop 1.0 beta.10:')

head = b'32-gamedata.quack'
fixed = {
    b'7104-KenshiShop.mod': {head: 125},
    b'7105-KenshiShop.mod': {head: 200},
    b'7106-KenshiShop.mod': dict.fromkeys((
        b'7001-KenshiShop.mod', b'7002-KenshiShop.mod', b'7003-KenshiShop.mod',
        b'7004-KenshiShop.mod', head, b'100-gamedata.quack', b'101-gamedata.quack',
    ), 80),
}
restored = deepcopy(after)
restored['description'] = before['description']
by_id = {record['strid']: record for record in before['records']}
for race in restored['records']:
    if race['strid'] not in fixed:
        continue
    reference = by_id[race['strid']]
    index, = [i for i, (key, _) in enumerate(race['extra']) if key == b'combat anatomy']
    key, parts = race['extra'][index]
    prior_key, prior_parts = reference['extra'][index]
    assert key == prior_key and len(parts) == len(prior_parts)
    wanted = fixed[race['strid']]
    assert {sid: hp for sid, _, hp, _ in parts if sid in wanted} == wanted
    assert parts == [(sid, chance, wanted.get(sid, hp), metadata) for sid, chance, hp, metadata in prior_parts]
    race['extra'][index] = (key, prior_parts)
assert km.serializar(restored) == source.read_bytes()
print('PASS vanilla Hive maximum HP corrected; all other FCS data, anatomy IDs and NoSever flags preserved')
