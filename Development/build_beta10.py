"""Correct only max HP in the three custom Hive races with stale vanilla values."""
from pathlib import Path
import sys

import kenshimod as km


HEAD = b'32-gamedata.quack'
ANATOMY = b'combat anatomy'
# Final vanilla race records in rebirth.mod. Limb IDs remain the custom ones
# to preserve anatomy, existing medical references and NoSever registration.
HP_FIXES = {
    b'7104-KenshiShop.mod': (HEAD, 75, 125),   # Hive Worker, 18960-gamedata.base
    b'7105-KenshiShop.mod': (HEAD, 100, 200),  # Hive Soldier, 18961-gamedata.base
    b'7106-KenshiShop.mod': (None, 75, 80),   # Hive Prince, 5346-stick_people.mod
}


def build(source, destination):
    mod = km.ler(source)
    assert km.serializar(mod) == source.read_bytes()
    assert mod['description'].startswith(b'KenshiShop 1.0 beta.9:')
    by_id = {record['strid']: record for record in mod['records']}
    assert len(by_id) == len(mod['records']) == 284

    for race_id, (part_id, old_hp, new_hp) in HP_FIXES.items():
        race = by_id[race_id]
        assert race['typecode'] == 7
        index, = [i for i, (key, _) in enumerate(race['extra']) if key == ANATOMY]
        _, parts = race['extra'][index]
        updated_parts = []
        changed = 0
        for part, hit_chance, hp, metadata in parts:
            if part_id is None or part == part_id:
                assert hp == old_hp
                hp = new_hp
                changed += 1
            updated_parts.append((part, hit_chance, hp, metadata))
        assert changed == (7 if part_id is None else 1)
        race['extra'][index] = (ANATOMY, updated_parts)

    mod['description'] = b'KenshiShop 1.0 beta.10: chief services and vanilla Hive health limits.'
    km.gravar(destination, mod)
    assert km.serializar(km.ler(destination)) == destination.read_bytes()


if __name__ == '__main__':
    build(*map(Path, sys.argv[1:3]))
