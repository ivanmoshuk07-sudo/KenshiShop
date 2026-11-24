"""Verify that an FCS release differs from its predecessor only in description."""
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import kenshimod as km

previous, current = map(Path, sys.argv[1:3])
baseline = km.ler(previous)
updated = km.ler(current)
assert km.serializar(baseline) == previous.read_bytes()
assert km.serializar(updated) == current.read_bytes()
assert updated['description'].startswith(f'KenshiShop {sys.argv[3]}:'.encode())
updated['description'] = baseline['description']
assert km.serializar(updated) == previous.read_bytes()
print(f'PASS all {len(baseline["records"])} FCS records and references preserved')
