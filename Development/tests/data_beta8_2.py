"""Verify native weather immunities and isolate the patch to the race fields."""
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'Development'))

import kenshimod as km
from build_beta8_2 import DESCRIPTION, HIVE_RACES, IMMUNITY_SLOT
from data_beta8_1 import main as audit_chief_services


def immunity(record):
    slots = [(key, value) for key, value in record['long'] if key.startswith(b'weather immunity')]
    return tuple(value for _, value in sorted(slots))


def main():
    path = 'KenshiShop/KenshiShop.mod'
    baseline = subprocess.check_output(['git', 'show', f'v1.0-beta.8.1:{path}'], cwd=ROOT)
    with tempfile.NamedTemporaryFile() as source:
        source.write(baseline)
        source.flush()
        audit_chief_services(source.name)
        original_description = km.ler(source.name)['description']

    updated = km.ler(ROOT / path)
    expected = {k: (0,) for k in range(7101, 7104)}
    expected.update({k: (2,) for k in range(7104, 7107)})
    expected.update({k: (1, 2, 3, 4) for k in range(7110, 7118)})
    expected = {f'{k}-KenshiShop.mod'.encode(): values for k, values in expected.items()}
    races = {record['strid']: record for record in updated['records'] if record['typecode'] == 7}
    assert {key: immunity(record) for key, record in races.items()} == expected
    assert updated['description'] == DESCRIPTION

    for race_id in HIVE_RACES:
        assert km.set_campo(races[race_id], 'long', IMMUNITY_SLOT.decode(), 0)
    updated['description'] = original_description
    assert km.serializar(updated) == baseline
    print('PASS all 14 race weather immunities. Exactly three immunity fields changed from beta.8.1.')


if __name__ == '__main__':
    main()
