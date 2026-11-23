"""Verify the published FCS against the beta.8 dialogue-only upgrade."""
from pathlib import Path
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'Development'))
import build_beta9
import kenshimod as km

source, destination = map(Path, sys.argv[1:3])
with tempfile.TemporaryDirectory() as temp:
    expected = Path(temp) / 'KenshiShop.mod'
    build_beta9.build(source, expected)
    assert destination.read_bytes() == expected.read_bytes()

before = {record['strid']: record for record in km.ler(source)['records']}
after = {record['strid']: record for record in km.ler(destination)['records']}
changes = {build_beta9.sid(number) for number in (*build_beta9.PLAYER_LINES, 11102, 11200)}
additions = {build_beta9.sid(number) for number in (11107, 11300, 11301, 11302, 11303)}
assert before.keys() - after.keys() == set()
assert after.keys() - before.keys() == additions
assert {key for key in before if before[key] != after[key]} == changes
print(f'PASS {len(before) - len(changes)} prior FCS records unchanged and departure requires a separate confirmation')

retreat = after[build_beta9.sid(11303)]
assert retreat['typecode'] == 72
assert dict(retreat['long']) == {b'signal func': 0, b'unloaded func': 4}
assert dict(retreat['bool']) == {b'clears existing jobs': 1}
assert {row for key, rows in retreat['extra'] for row in rows} == {
    (b'2542-gamedata.base', 0, 100, 0),
    (b'2825-gamedata.base', 0, 100, 0),
    (b'62008-rebirth.mod', 0, 24, 0),
}
assert [key for key, _ in retreat['extra']] == [b'Leader AI Goals', b'Squad AI Goals']
print('PASS native retreat uses go-home behavior for unloaded squads and omits raid signals')
