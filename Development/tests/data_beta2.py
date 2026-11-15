"""Check the actual beta.2 task hierarchy and compatibility with beta.1 data."""
from pathlib import Path
import copy
import hashlib
import json
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'Development'))
import kenshimod as km

old_path, current_path = map(Path, sys.argv[1:3])
old, current = km.ler(old_path), km.ler(current_path)
assert km.serializar(old) == old_path.read_bytes()
assert km.serializar(current) == current_path.read_bytes()
previous = {r['strid']: r for r in old['records']}
records = {r['strid']: r for r in current['records']}
assert len(previous) == 227 and len(records) == len(current['records']) == 242
new_ids = set(range(10000, 10008)) | set(range(10010, 10017))
assert records.keys() - previous.keys() == {f'{n}-KenshiShop.mod'.encode() for n in new_ids}
for sid, record in previous.items():
    if sid != b'7604-KenshiShop.mod':
        assert records[sid] == record, sid
expected_care = copy.deepcopy(previous[b'7604-KenshiShop.mod'])
for category, rows in expected_care['extra']:
    if b'AI Goals' in category:
        rows[:] = [(sid.replace(b'9005-KenshiShop.mod', b'10005-KenshiShop.mod')
                    .replace(b'9006-KenshiShop.mod', b'10006-KenshiShop.mod'), a, b, c)
                   for sid, a, b, c in rows]
assert records[b'7604-KenshiShop.mod'] == expected_care
# Only release text and the next-record allocator are allowed to change outside
# the actual list of records. The allocator must exceed our new highest ID.
normalized = copy.deepcopy(current)
normalized['records'] = old['records']
normalized['description'] = old['description']
assert current['unknown'] == 10100 > max(new_ids)
normalized['unknown'] = old['unknown']
assert km.serializar(normalized) == old_path.read_bytes()
assert b'1.0 beta.2' in current['description']
print('PASS 226 old records byte-identical, initial care remapped only; old saved packages and all physical/stock/race data preserved')

# Explicit independent expected task definitions, including native target types.
goals = {
    10005: (148, 2, 0), 10006: (106, 2, 0),
    10010: (20, 1, 0), 10011: (86, 1, 0), 10012: (268, 1, 0),
    10013: (38, 1, 0), 10014: (36, 1, 0), 10015: (141, 1, 2),
    10016: (239, 1, 0),
}
for number, (task, priority, targeting) in goals.items():
    record = records[f'{number}-KenshiShop.mod'.encode()]
    assert record['typecode'] == 22
    assert dict(record['long']) == {
        b'enum': task, b'classification': priority, b'targeting': targeting, b'ending': 0,
    }, record['strid']

mapping = {
    b'9005-KenshiShop.mod': b'10005-KenshiShop.mod',
    b'9006-KenshiShop.mod': b'10006-KenshiShop.mod',
    b'1170-gamedata.base': b'10010-KenshiShop.mod',
    b'3104-gamedata.base': b'10011-KenshiShop.mod',
    b'8505-KenshiShop.mod': b'10012-KenshiShop.mod',
    b'1188-gamedata.base': b'10013-KenshiShop.mod',
    b'965-gamedata.base': b'10014-KenshiShop.mod',
    b'1166-gamedata.base': b'10015-KenshiShop.mod',
    b'46053-rebirth.mod': b'10016-KenshiShop.mod',
}
urgent = {b'1360-gamedata.base': 58, b'7603-KenshiShop.mod': 57,
          b'2825-gamedata.base': 143, b'1535072-rebirth.mod': 288}
references = json.loads((ROOT / 'Development/references/native_ai.json').read_text())
for sid, task in urgent.items():
    definition = dict(records[sid]['long']) if sid in records else references[sid.decode()]['fields']
    if sid in records:
        assert definition[b'enum'] == task and definition[b'classification'] == 3
    else:
        assert definition['enum'] == task and definition['classification'] == 3

for offset in range(5):
    before = copy.deepcopy(previous[f'900{offset}-KenshiShop.mod'.encode()])
    actual = records[f'{10000 + offset}-KenshiShop.mod'.encode()]
    for category, rows in before['extra']:
        if b'AI Goals' not in category:
            continue
        rows[:] = [(mapping.get(sid, sid), a, b, c) for sid, a, b, c in rows]
        # Every role section has all four emergency tasks and both rescue stages.
        actual_rows = dict(actual['extra'])[category]
        assert set(urgent) <= {row[0] for row in actual_rows}
        assert (b'10005-KenshiShop.mod', 0, 24, 0) in actual_rows
        assert (b'10006-KenshiShop.mod', 0, 24, 110) in actual_rows
        assert not any(sid in mapping for sid, *_ in actual_rows)
    before['id'] = actual['id']
    before['strid'] = actual['strid']
    before['name'] = before['name'].replace(b'KS90', b'KSB2')
    assert actual == before, actual['strid']
assert records[b'10007-KenshiShop.mod']['extra'] == [
    (b'Leader AI Goals', [(b'10006-KenshiShop.mod', 0, 24, 110)])]
print('PASS all five role packages: medical/protection 3, rescue+bed 2, every work/door/return/patrol/follow goal 1; original weights and schedules unchanged')

protected = subprocess.check_output(
    ['git', 'ls-tree', '-r', '--name-only', 'v1.0-beta.1'], cwd=ROOT, text=True).splitlines()
protected = [p for p in protected if '/Building/' in p or '/character/' in p
             or p.startswith('KenshiShop_LegendaryCompat/')
             or p.endswith('/Catalog.lua') or 'Furniture' in p or '/Floor' in p
             or '/Layout' in p or p.endswith('/PostData.lua')
             or p.endswith('/Transport.lua') or p.endswith('/OriginTown.lua')
             or p.endswith('/ServiceTown.lua') or p.endswith('/HomeAssignment.lua')]
for name in protected:
    assert (ROOT / name).read_bytes() == subprocess.check_output(
        ['git', 'show', 'v1.0-beta.1:' + name], cwd=ROOT), name
print('PASS', len(protected), 'physical models/textures/furniture, stock, compatibility, posts, delivery and town files unchanged')

meta = json.loads((ROOT / 'Development/references/native_no_sever91.json').read_text())
assert hashlib.sha256((ROOT / 'KenshiShop/native/KenshiShopNative.dll').read_bytes()).hexdigest() == meta['bridge']['dll_sha256']
for name, digest in meta['bridge']['source_sha256'].items():
    assert hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == digest, name
print('PASS tested native DLL and source hashes unchanged; limb protection retained')
