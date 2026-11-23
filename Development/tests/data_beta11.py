"""Verify all custom race weather immunities and isolate the changed FCS fields."""
from copy import deepcopy
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'Development'))
import kenshimod as km
from build_beta9 import refs, sid


def immunity(record):
    return [(key, value) for key, value in record['long'] if key.startswith(b'weather immunity')]


def expected_slots(values):
    return [(f'weather immunity{index}'.encode(), value) for index, value in enumerate(values)]


source, destination = map(Path, sys.argv[1:3])
before = km.ler(source)
after = km.ler(destination)
assert km.serializar(before) == source.read_bytes()
assert km.serializar(after) == destination.read_bytes()
assert after['description'].startswith(b'KenshiShop 1.0 beta.11:')

expected = {number: (0,) for number in range(7101, 7104)}
expected.update({number: (2,) for number in range(7104, 7107)})
expected.update({number: (1, 2, 3, 4) for number in range(7110, 7118)})
expected = {f'{number}-KenshiShop.mod'.encode(): expected_slots(values) for number, values in expected.items()}
races = {record['strid']: immunity(record) for record in after['records'] if record['typecode'] == 7}
assert races == expected

restored = deepcopy(after)
restored['description'] = before['description']
restored['unknown'] = before['unknown']
assert after['unknown'] == 11500
for record in restored['records']:
    if record['strid'] in (b'7104-KenshiShop.mod', b'7105-KenshiShop.mod', b'7106-KenshiShop.mod'):
        index, = [i for i, (key, _) in enumerate(record['long']) if key == b'weather immunity0']
        record['long'][index] = (b'weather immunity0', 0)
before_by_id = {record["strid"]: record for record in before["records"]}
after_by_id = {record['strid']: record for record in after['records']}
assert dict(after_by_id[sid(11105)]['extra'])[b'lines'] == refs(11400)
assert dict(after_by_id[sid(11400)]['extra'])[b'lines'] == refs(11401, 11402)
assert dict(after_by_id[sid(11400)]['long'])[b'speaker'] == 0
for number in (11401, 11402):
    record = after_by_id[sid(number)]
    assert not record['extra'] and dict(record['long'])[b'speaker'] == 2
assert '20 000' in dict(after_by_id[sid(11401)]['string'])[b'text0'].decode()
restored['records'] = [before_by_id[sid(11105)] if record['strid'] == sid(11105) else record
                       for record in restored['records']
                       if record['strid'] not in {sid(n) for n in (11400, 11401, 11402)}]
assert km.serializar(restored) == source.read_bytes()
print('PASS 14 race weather immunities match vanilla; native hire quote/confirm/cancel; other FCS data exact')
