"""Validate native replacement selection while preserving beta.3 gameplay data."""
from pathlib import Path
import copy
import hashlib
import json
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'Development'))
import kenshimod as km


def record_bytes(record):
    writer = km.Writer()
    km._gravar_registro(writer, record)
    return bytes(writer.out)


def sid(number):
    return f'{number}-KenshiShop.mod'.encode()


source, destination = map(Path, sys.argv[1:3])
old, current = km.ler(source), km.ler(destination)
assert km.serializar(old) == source.read_bytes()
assert km.serializar(current) == destination.read_bytes()
before = {r['strid']: r for r in old['records']}
after = {r['strid']: r for r in current['records']}
new_numbers = [11200, *range(11210, 11216), 11220, 11221, 11222,
               *range(11230, 11236), *range(11240, 11246), *range(11250, 11256)]
expected_new = {sid(number) for number in new_numbers}
assert len(before) == len(old['records']) == 251 and old['unknown'] == 11200
assert len(after) == len(current['records']) == 279
assert len(expected_new) == 28 and after.keys() - before.keys() == expected_new
assert before.keys() <= after.keys()
assert [r['strid'] for r in current['records'][:251]] == [r['strid'] for r in old['records']]
for key, record in before.items():
    if key not in (sid(11102), sid(11103)):
        assert record_bytes(after[key]) == record_bytes(record), key
greeting = copy.deepcopy(before[sid(11102)])
dict(greeting['extra'])[b'lines'].remove((sid(11104), 0, 0, 0))
assert record_bytes(after[sid(11102)]) == record_bytes(greeting)
losses = copy.deepcopy(before[sid(11103)])
assert km.set_campo(losses, 'string', 'text0', 'Кто из наших NPC погиб?')
losses['extra'] = [(b'lines', [(sid(11200), 0, 0, 0)])]
assert record_bytes(after[sid(11103)]) == record_bytes(losses)
assert current['unknown'] == 11300
assert current['description'].startswith(b'KenshiShop 1.0 beta.4:')
normalized = copy.deepcopy(current)
normalized.update(records=old['records'], description=old['description'], unknown=old['unknown'])
assert km.serializar(normalized) == source.read_bytes()
print('PASS 249 beta.3 records byte exact; only greeting edges and loss enquiry changed; header allocator 11300')

# Native edges deliberately end at page, cancel and payment replies. Runtime
# re-enters the list after those actions, avoiding cycles in the FCS tree.
children = {11200: [*range(11210, 11216), 11220, 11221, 11222]}
children.update({11210 + i: [11230 + i] for i in range(6)})
children.update({11230 + i: [11240 + i, 11250 + i] for i in range(6)})
for number in new_numbers:
    record = after[sid(number)]
    assert record['typecode'] == 19 and record['id'] == number
    assert record['mod_data_type'] == -2147483646
    assert record['instance_count'] == 0 and not record['instances']
    assert not record['bool'], 'Shared lines must default to unlocked'
    assert record['float'] == [(b'chance permanent', 100.0), (b'chance temporary', 100.0)]
    npc = number == 11200 or 11230 <= number <= 11235
    assert record['long'] == [(b'repetition limit', 0), (b'score bonus', 0),
                              (b'speaker', 0 if npc else 1), (b'target is type', 0)]
    assert not record['vec3'] and not record['vec4'] and not record['filename']
    assert len(record['string']) == 1 and record['string'][0][0] == b'text0'
    text = record['string'][0][1].decode('utf-8')
    if number == 11200 or 11210 <= number <= 11215 or 11230 <= number <= 11235:
        assert text == 'Нет подтвержденной записи'
    elif 11240 <= number <= 11245:
        assert text == 'Подтверждаю: нанять замену за 10 000 кат'
    elif 11250 <= number <= 11255:
        assert text == 'Назад к списку'
    else:
        assert text == {11220: 'Предыдущие', 11221: 'Следующие',
                        11222: 'Закончить разговор'}[number]
    expected = [(b'lines', [(sid(child), 0, 0, 0) for child in children[number]])] if number in children else []
    assert record['extra'] == expected, number

seen, active = set(), set()


def walk(number):
    assert number not in active, ('Native dialogue cycle', number)
    assert number not in seen, ('Native line reused by multiple parents', number)
    active.add(number)
    seen.add(number)
    for child in children.get(number, []):
        walk(child)
    active.remove(number)


walk(11200)
assert seen == set(new_numbers)
assert sum(map(len, children.values())) == 27
assert dict(after[sid(11103)]['extra'])[b'lines'] == [(sid(11200), 0, 0, 0)]
assert dict(after[sid(11102)]['extra'])[b'lines'] == [(sid(n), 0, 0, 0) for n in (11103, 11105, 11106)]
assert all(target != sid(11104) for r in current['records']
           for _, rows in r['extra'] for target, *_ in rows)
assert record_bytes(after[sid(11104)]) == record_bytes(before[sid(11104)])
for record in current['records']:
    for _, rows in record['extra']:
        for target, *_ in rows:
            assert not target.endswith(b'-KenshiShop.mod') or target in after, (record['strid'], target)
print('PASS all 28 native type19 rows reachable once; acyclic six-slot confirmation tree; fixed 10,000-cat replies; no FCS money, effects or Lua callbacks')

paths = subprocess.check_output(
    ['git', 'ls-tree', '-r', '--name-only', 'v1.0-beta.3'], cwd=ROOT, text=True).splitlines()
protected = [p for p in paths if '/Building/' in p or '/character/' in p
             or p.startswith('KenshiShop_LegendaryCompat/')
             or p.endswith('/Catalog.lua') or 'Furniture' in p or '/Floor' in p
             or '/Layout' in p or p.endswith('/PostData.lua')
             or p.endswith('/Transport.lua') or p.endswith('/OriginTown.lua')
             or p.endswith('/ServiceTown.lua') or p.endswith('/HomeAssignment.lua')]
for name in protected:
    assert (ROOT / name).read_bytes() == subprocess.check_output(
        ['git', 'show', 'v1.0-beta.3:' + name], cwd=ROOT), name
metadata = json.loads((ROOT / 'Development/references/native_no_sever91.json').read_text())
assert hashlib.sha256((ROOT / 'KenshiShop/native/KenshiShopNative.dll').read_bytes()).hexdigest() == metadata['bridge']['dll_sha256']
for name, digest in metadata['bridge']['source_sha256'].items():
    assert hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == digest, name
print('PASS', len(protected), 'physical/stock/compatibility/city files plus native DLL/source hashes unchanged')
