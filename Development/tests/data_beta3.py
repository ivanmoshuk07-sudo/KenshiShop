"""Validate chief dialogue/night-patrol additions without changing beta.2 data."""
from pathlib import Path
import copy
import hashlib
import json
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'Development'))
import kenshimod as km

source, destination = map(Path, sys.argv[1:3])
old, current = km.ler(source), km.ler(destination)
assert km.serializar(old) == source.read_bytes()
assert km.serializar(current) == destination.read_bytes()
before = {r['strid']: r for r in old['records']}
after = {r['strid']: r for r in current['records']}
expected_new = {f'{n}-KenshiShop.mod'.encode() for n in [11000, 11001, *range(11100, 11107)]}
assert len(before) == 242 and len(after) == len(current['records']) == 251
assert after.keys() - before.keys() == expected_new
for sid, record in before.items():
    if sid != b'7310-KenshiShop.mod':
        assert after[sid] == record, sid
chief = copy.deepcopy(before[b'7310-KenshiShop.mod'])
dict(chief['extra'])[b'dialogue package'].append((b'11100-KenshiShop.mod', 0, 0, 0))
assert after[b'7310-KenshiShop.mod'] == chief
normalized = copy.deepcopy(current)
normalized['records'] = old['records']
normalized['description'] = old['description']
assert current['unknown'] == 11200
normalized['unknown'] = old['unknown']
assert km.serializar(normalized) == source.read_bytes()
print('PASS 241 beta.2 records exact; only chief package reference added; all old roles/posts/stock/furniture/races retained')

squad = copy.deepcopy(before[b'311-KenshiShop.mod'])
squad.update(id=11000, strid=b'11000-KenshiShop.mod', name=after[b'11000-KenshiShop.mod']['name'])
assert km.set_campo(squad, 'bool', 'dont multiply', 1)
assert after[b'11000-KenshiShop.mod'] == squad
refs = dict(squad['extra'])
assert refs[b'leader'] == [(b'312-KenshiShop.mod', 1, 0, 0)]
assert refs[b'squad'] == [(b'312-KenshiShop.mod', 2, 2, 0)]

night = copy.deepcopy(before[b'10004-KenshiShop.mod'])
night.update(id=11001, strid=b'11001-KenshiShop.mod', name=b'KSB3 Hired night patrol')
for category, rows in night['extra']:
    if b'AI Goals' not in category:
        continue
    expected = []
    for sid, start, end, weight in rows:
        if sid in (b'10014-KenshiShop.mod', b'10015-KenshiShop.mod'):
            expected.extend([(sid, 0, 6, weight), (sid, 23, 24, weight)])
        else:
            expected.append((sid, start, end, weight))
    rows[:] = expected
assert after[b'11001-KenshiShop.mod'] == night
selector = (ROOT / 'KenshiShop/scripts/Core/NPC/RoleAI.lua').read_text()
assert "'11001-KenshiShop.mod','" + night['name'].decode() + "'" in selector, 'Runtime hired package label must match actual FCS data'
print('PASS paid squad exactly 3 with no population multiplication; private patrol/follow 23:00–06:00; emergency3/rescue2/work1 unchanged')

package = after[b'11100-KenshiShop.mod']
assert package['typecode'] == 73 and package['extra'] == [
    (b'dialogs', [(b'11101-KenshiShop.mod', 1, 0, 0)])]
dialogue = after[b'11101-KenshiShop.mod']
assert dialogue['typecode'] == 18 and dialogue['extra'] == [
    (b'lines', [(b'11102-KenshiShop.mod', 100, 0, 0)])]
greeting = after[b'11102-KenshiShop.mod']
assert greeting['typecode'] == 19 and dict(greeting['long'])[b'speaker'] == 0
assert dict(greeting['extra'])[b'lines'] == [
    (f'{n}-KenshiShop.mod'.encode(), 0, 0, 0) for n in range(11103, 11107)]
for number in range(11102, 11107):
    line = after[f'{number}-KenshiShop.mod'.encode()]
    assert line['typecode'] == 19
    assert dict(line['long'])[b'speaker'] == (0 if number == 11102 else 1)
    assert dict(line['string'])[b'text0'].decode('utf-8')
    assert not line['filename']
    assert not any(category in (b'effects', b'run lua script') for category, _ in line['extra'])
assert '10 000' in dict(after[b'11104-KenshiShop.mod']['string'])[b'text0'].decode()
assert '20 000' in dict(after[b'11105-KenshiShop.mod']['string'])[b'text0'].decode()
for record in current['records']:
    refs = [sid for _, rows in record['extra'] for sid, *_ in rows]
    for sid in refs:
        assert not sid.endswith(b'-KenshiShop.mod') or sid in after, (record['strid'], sid)
assert (ROOT / 'KenshiShop/scripts/Core/Police/Services/Dialogue.lua').is_file()
print('PASS actual FCS package73/dialogue18/lines19 tree with player replies; no unconditional charge, dangling local references or external script paths')

paths = subprocess.check_output(
    ['git', 'ls-tree', '-r', '--name-only', 'v1.0-beta.2'], cwd=ROOT, text=True).splitlines()
protected = [p for p in paths if '/Building/' in p or '/character/' in p
             or p.startswith('KenshiShop_LegendaryCompat/')
             or p.endswith('/Catalog.lua') or 'Furniture' in p or '/Floor' in p
             or '/Layout' in p or p.endswith('/PostData.lua')
             or p.endswith('/Transport.lua') or p.endswith('/OriginTown.lua')
             or p.endswith('/ServiceTown.lua') or p.endswith('/HomeAssignment.lua')]
for name in protected:
    assert (ROOT / name).read_bytes() == subprocess.check_output(
        ['git', 'show', 'v1.0-beta.2:' + name], cwd=ROOT), name
metadata = json.loads((ROOT / 'Development/references/native_no_sever91.json').read_text())
assert hashlib.sha256((ROOT / 'KenshiShop/native/KenshiShopNative.dll').read_bytes()).hexdigest() == metadata['bridge']['dll_sha256']
for name, digest in metadata['bridge']['source_sha256'].items():
    assert hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == digest, name
print('PASS', len(protected), 'physical/stock/compatibility/city files plus native DLL/source hashes unchanged')
