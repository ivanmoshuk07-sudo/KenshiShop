"""Prove beta.8 only changes the FCS description and permitted runtime code."""
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
assert len(old['records']) == len(current['records']) == 279
assert current['description'].startswith(b'KenshiShop 1.0 beta.8:')
normalized = copy.deepcopy(current)
normalized['description'] = old['description']
assert km.serializar(normalized) == source.read_bytes()
print('PASS all 279 beta.7 FCS records and header fields byte exact except version description')

# Confirm the exact runtime inventory change and preserve all unrelated files.
baseline = 'v1.0-beta.7'
changed = {
    'KenshiShop/KenshiShop.mod',
    'KenshiShop/scripts/Core.lua',
    'KenshiShop/scripts/KenshiLuaConsole.lua',
    'KenshiShop/scripts/Core/NPC/Controller.lua',
    'KenshiShop/scripts/Core/NPC/LiveState.lua',
    'KenshiShop/scripts/Core/NPC/PostDuty.lua',
    'KenshiShop/scripts/Core/NPC/Catalog.lua',
    'KenshiShop/scripts/Core/NPC/RoleAI.lua',
    'KenshiShop/scripts/Core/Ownership/Manager.lua',
    'KenshiShop/scripts/Core/Ownership/ShopTests.lua',
    'KenshiShop/scripts/Core/Bar/Building/LiveFurniture.lua',
    'KenshiShop/scripts/Core/Bar/Building/Interior.lua',
    'KenshiShop/scripts/Core/Bar/Building/FurnitureRestore.lua',
    'KenshiShop/scripts/Core/Police/init.lua',
    'KenshiShop/scripts/Core/Police/Building/FurnitureData.lua',
    'KenshiShop/scripts/Core/Police/Services/Store.lua',
    'KenshiShop/scripts/Core/Police/Services/Roster.lua',
    'KenshiShop/scripts/Core/Police/Services/init.lua',
}
removed = {
    'KenshiShop/FIX_BUILDING_PREVIEW_CACHE.bat',
    'KenshiShop/History/alpha80/CHANGE_REPORT_ALPHA80_RU.md',
    'KenshiShop/History/alpha80/INSTALL_ALPHA80_RU.txt',
    'KenshiShop/History/alpha80/TEST_REPORT_ALPHA80_RU.md',
    'KenshiShop/scripts/Core/Police/Building/NodeMarkers.lua',
}
paths = subprocess.check_output(
    ['git', 'ls-tree', '-r', '--name-only', baseline, 'KenshiShop', 'KenshiShop_LegendaryCompat'],
    cwd=ROOT, text=True).splitlines()
current_paths = {path.relative_to(ROOT).as_posix()
                 for folder in ('KenshiShop', 'KenshiShop_LegendaryCompat')
                 for path in (ROOT / folder).rglob('*') if path.is_file()}
assert removed <= set(paths)
assert current_paths == set(paths) - removed
protected = set(paths) - changed - removed
for name in sorted(protected):
    assert (ROOT / name).read_bytes() == subprocess.check_output(
        ['git', 'show', baseline + ':' + name], cwd=ROOT), name
print('PASS only the five identified obsolete files removed from the mod directories')
metadata = json.loads((ROOT / 'Development/references/native_no_sever91.json').read_text())
assert hashlib.sha256((ROOT / 'KenshiShop/native/KenshiShopNative.dll').read_bytes()).hexdigest() == metadata['bridge']['dll_sha256']
for name, digest in metadata['bridge']['source_sha256'].items():
    assert hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == digest, name
print('PASS', len(protected), 'other shipped runtime files and native DLL/source hashes unchanged')
