"""Restore the vanilla acid-immunity flag on the three KenshiShop Hive races."""
from pathlib import Path
import argparse

import kenshimod as km


IMMUNITY_SLOT = b'weather immunity0'
ACID_IMMUNITY = 2  # WeatherAffecting::WA_ACID
HIVE_RACES = (
    b'7104-KenshiShop.mod',  # Hive Worker Drone, 18960-gamedata.base
    b'7105-KenshiShop.mod',  # Hive Soldier Drone, 18961-gamedata.base
    b'7106-KenshiShop.mod',  # Hive Prince, 5346-stick_people.mod
)
DESCRIPTION = b'KenshiShop 1.0 beta.8.2: chief services and restored Hive acid immunity.'


def build(source, destination):
    mod = km.ler(source)
    assert km.serializar(mod) == source.read_bytes()
    assert mod['description'].startswith(b'KenshiShop 1.0 beta.8.1:')
    by_id = {record['strid']: record for record in mod['records']}
    for race_id in HIVE_RACES:
        race = by_id[race_id]
        assert race['typecode'] == 7 and dict(race['long'])[IMMUNITY_SLOT] == 0
        assert km.set_campo(race, 'long', IMMUNITY_SLOT.decode(), ACID_IMMUNITY)
    mod['description'] = DESCRIPTION
    km.gravar(destination, mod)
    assert km.serializar(km.ler(destination)) == destination.read_bytes()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('destination', type=Path)
    args = parser.parse_args()
    build(args.source, args.destination)
