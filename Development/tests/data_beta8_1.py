"""Audit the exact chief-service changes against beta.8."""
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'Development'))

import kenshimod as km
from build_beta8_1 import PLAYER, PLAYER_LINES, refs, sid


def baseline(path):
    return subprocess.check_output(['git', 'show', f'v1.0-beta.8:{path}'], cwd=ROOT)


def main(updated_path=None):
    path = 'KenshiShop/KenshiShop.mod'
    with tempfile.NamedTemporaryFile() as source:
        source.write(baseline(path))
        source.flush()
        original = km.ler(source.name)
    updated = km.ler(updated_path or ROOT / path)
    old = {row['strid']: row for row in original['records']}
    new = {row['strid']: row for row in updated['records']}
    assert not old.keys() - new.keys()
    changed = {key for key in old if old[key] != new[key]}
    assert changed == {sid(number) for number in (*PLAYER_LINES, 11102, 11200)}
    assert new.keys() - old.keys() == {
        sid(number) for number in (11107, 11300, 11301, 11302, 11303, 11400, 11401, 11402, 11500)
    }
    for reply in (*PLAYER_LINES, 11107, 11301, 11302, 11401, 11402):
        assert dict(new[sid(reply)]['long'])[b'speaker'] == PLAYER
    assert dict(new[sid(11105)]['extra'])[b'lines'] == refs(11400)
    assert dict(new[sid(11400)]['extra'])[b'lines'] == refs(11401, 11402)
    assert dict(new[sid(11107)]['extra'])[b'lines'] == refs(11300)
    assert dict(new[sid(11300)]['extra'])[b'lines'] == refs(11301, 11302)
    guard, patrol = new[sid(11500)], old[sid(11000)]
    identity = {'id', 'name', 'strid'}
    assert {key: value for key, value in guard.items() if key not in identity} == {
        key: value for key, value in patrol.items() if key not in identity
    }
    assert dict(new[sid(11303)]['long'])[b'unloaded func'] == 4
    unchanged_files = (
        'KenshiShop/scripts/Core/NPC/Transport.lua',
        'KenshiShop/scripts/Core/NPC/RoleAI.lua',
        'KenshiShop/scripts/Core/NPC/NativeCare.lua',
        'KenshiShop/scripts/Layouts.lua',
        'KenshiShop/native/KenshiShopNative.dll',
        'KenshiShop_LegendaryCompat/KenshiShop_LegendaryCompat.mod',
    )
    for name in unchanged_files:
        assert (ROOT / name).read_bytes() == baseline(name), name
    print('PASS chief dialogue, same native delivery template, scope, and unchanged beta.8 gameplay records')


if __name__ == '__main__':
    main(*sys.argv[1:2])
