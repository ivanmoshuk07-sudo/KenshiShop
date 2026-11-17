"""Prove beta.7 only changes the FCS description and permitted runtime code."""
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
assert current['description'].startswith(b'KenshiShop 1.0 beta.7:')
normalized = copy.deepcopy(current)
normalized['description'] = old['description']
assert km.serializar(normalized) == source.read_bytes()
print('PASS all 279 beta.6 FCS records and header fields byte exact except version description')

# Whitelist the intended code changes; every other shipped runtime file must
# match the published baseline, including furniture, stock, races and assets.
changed = {
    'KenshiShop/KenshiShop.mod',
    'KenshiShop/scripts/Core.lua',
    'KenshiShop/scripts/KenshiLuaConsole.lua',
    'KenshiShop/scripts/Core/Police/Services/Store.lua',
    'KenshiShop/scripts/Core/Police/Services/Dialogue.lua',
    'KenshiShop/scripts/Core/Police/Services/init.lua',
}
paths = subprocess.check_output(
    ['git', 'ls-tree', '-r', '--name-only', 'v1.0-beta.6'], cwd=ROOT, text=True).splitlines()
protected = [name for name in paths
             if (name.startswith('KenshiShop/') and not name.startswith('KenshiShop/History/')
                 or name.startswith('KenshiShop_LegendaryCompat/')) and name not in changed]
for name in protected:
    assert (ROOT / name).read_bytes() == subprocess.check_output(
        ['git', 'show', 'v1.0-beta.6:' + name], cwd=ROOT), name
metadata = json.loads((ROOT / 'Development/references/native_no_sever91.json').read_text())
assert hashlib.sha256((ROOT / 'KenshiShop/native/KenshiShopNative.dll').read_bytes()).hexdigest() == metadata['bridge']['dll_sha256']
for name, digest in metadata['bridge']['source_sha256'].items():
    assert hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == digest, name
print('PASS', len(protected), 'other shipped runtime files and native DLL/source hashes unchanged')
