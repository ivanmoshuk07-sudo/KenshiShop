"""Restore Hive weather immunity and add a native hire confirmation."""
from copy import deepcopy
from pathlib import Path
import sys

import kenshimod as km
from build_beta9 import refs, sid


HIVE_RACES = (
    b'7104-KenshiShop.mod',  # Hive Worker Drone, 18960-gamedata.base
    b'7105-KenshiShop.mod',  # Hive Soldier Drone, 18961-gamedata.base
    b'7106-KenshiShop.mod',  # Hive Prince, 5346-stick_people.mod
)


def restore_hive_immunity(mod):
    by_id = {record['strid']: record for record in mod['records']}
    for race_id in HIVE_RACES:
        race = by_id[race_id]
        assert race['typecode'] == 7
        index, = [i for i, (key, _) in enumerate(race['long']) if key == b'weather immunity0']
        assert race['long'][index] == (b'weather immunity0', 0)
        race['long'][index] = (b'weather immunity0', 2)  # WeatherAffecting::WA_ACID


def add_patrol_offer(mod):
    by_id = {record['strid']: record for record in mod['records']}
    hire = by_id[sid(11105)]
    assert hire['typecode'] == 19 and not hire['extra']
    assert km.set_campo(hire, 'string', 'text0', 'Мне нужен дополнительный патруль.')
    hire['extra'] = [(b'lines', refs(11400))]
    new_lines = (
        (11400, 11300, 'KS Chief: patrol hire quote',
         'Три патрульных за 20 000 кат. Днём они стоят у башни, ночью патрулируют. Подтверждаешь?',
         [(b'lines', refs(11401, 11402))]),
        (11401, 11301, 'KS Chief: accept patrol hire', 'Да, нанять за 20 000 кат.', []),
        (11402, 11302, 'KS Chief: cancel patrol hire', 'Нет, передумал.', []),
    )
    for number, reference, name, text, children in new_lines:
        assert sid(number) not in by_id
        record = deepcopy(by_id[sid(reference)])
        record.update(id=number, name=name.encode(), strid=sid(number), extra=children)
        assert km.set_campo(record, 'string', 'text0', text)
        mod['records'].append(record)
    assert mod['unknown'] == 11400
    mod['unknown'] = 11500


def build(source, destination):
    mod = km.ler(source)
    assert km.serializar(mod) == source.read_bytes()
    assert mod['description'].startswith(b'KenshiShop 1.0 beta.10:')
    restore_hive_immunity(mod)
    add_patrol_offer(mod)
    mod['description'] = b'KenshiShop 1.0 beta.11: chief services and native Hive weather immunity.'
    km.gravar(destination, mod)
    assert km.serializar(km.ler(destination)) == destination.read_bytes()


if __name__ == '__main__':
    build(*map(Path, sys.argv[1:3]))
