"""Verify that this runtime fix leaves the beta.11 FCS records intact."""
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import kenshimod as km

previous, current = map(Path, sys.argv[1:3])
baseline = km.ler(previous)
updated = km.ler(current)
assert km.serializar(baseline) == previous.read_bytes()
assert km.serializar(updated) == current.read_bytes()
assert updated['description'].startswith(b'KenshiShop 1.0 beta.12:')
updated['description'] = baseline['description']
assert km.serializar(updated) == previous.read_bytes()
print('PASS all 287 beta.11 FCS records and references preserved')
