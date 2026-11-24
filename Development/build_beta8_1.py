"""Builds the chief dialogue, departure package and tower guard squad from beta.8."""
from copy import deepcopy
from pathlib import Path
import sys

import kenshimod as km


def sid(number):
    return f'{number}-KenshiShop.mod'.encode()


def refs(*numbers):
    return [(sid(number), 0, 0, 0) for number in numbers]


PLAYER = 2  # TalkerEnum::T_TARGET_IF_PLAYER, as in KenshiLua's Crooked Dice.
PLAYER_LINES = (
    11103, 11105, 11106, *range(11210, 11216), 11220, 11221, 11222,
    *range(11240, 11246), *range(11250, 11256),
)


def build(source, destination):
    mod = km.ler(source)
    assert km.serializar(mod) == source.read_bytes()
    by_id = {record['strid']: record for record in mod['records']}
    assert len(by_id) == len(mod['records']) == 279 and mod['unknown'] == 11300
    assert mod['description'].startswith(b'KenshiShop 1.0 beta.8:')

    for number in PLAYER_LINES:
        record = by_id[sid(number)]
        assert dict(record['long'])[b'speaker'] == 1
        assert km.set_campo(record, 'long', 'speaker', PLAYER)

    greeting = by_id[sid(11102)]
    assert dict(greeting['extra'])[b'lines'] == refs(11103, 11105, 11106)
    greeting['extra'] = [(b'lines', refs(11103, 11105, 11107, 11106))]
    assert km.set_campo(greeting, 'string', 'text0', 'Что требуется городу?')
    assert km.set_campo(by_id[sid(11103)], 'string', 'text0', 'Кто из наших сотрудников пропал?')
    hire = by_id[sid(11105)]
    assert not hire['extra']
    assert km.set_campo(hire, 'string', 'text0', 'Мне нужен дополнительный отряд.')
    hire['extra'] = [(b'lines', refs(11400))]
    assert km.set_campo(by_id[sid(11200)], 'string', 'text0', 'Уточняю состав города.')

    def line(number, speaker, name, text, children=()):
        assert sid(number) not in by_id
        record = {section: [] for section, *_ in km.SECOES}
        record.update(instance_count=0, typecode=19, id=number, name=name.encode(), strid=sid(number),
                      mod_data_type=-2147483646, extra=[], instances=[])
        record['float'] = [(b'chance permanent', 100.0), (b'chance temporary', 100.0)]
        record['long'] = [(b'repetition limit', 0), (b'score bonus', 0),
                          (b'speaker', speaker), (b'target is type', 0)]
        record['string'] = [(b'text0', text.encode())]
        if children:
            record['extra'] = [(b'lines', refs(*children))]
        mod['records'].append(record)

    line(11107, PLAYER, 'KS Chief: leave the town', 'Уходим из города.', [11300])
    line(11300, 0, 'KS Chief: confirm town departure',
         'Наши сотрудники уйдут из города. Здания и мебель перейдут под твой контроль, '
         'а записи о службе и найме в этом городе будут очищены. Подтверждаешь?',
         [11301, 11302])
    line(11301, PLAYER, 'KS Chief: proceed with town departure', 'Да, уходим из города.')
    line(11302, PLAYER, 'KS Chief: cancel town departure', 'Нет, остаёмся.')
    line(11400, 0, 'KS Chief: additional squad offer', 'Уточняю, какой отряд можно нанять.',
         [11401, 11402])
    line(11401, PLAYER, 'KS Chief: confirm hire', 'Да, нанять за 20 000 кат.')
    line(11402, PLAYER, 'KS Chief: cancel hire', 'Нет, передумал.')

    # Vanilla 17917-gamedata.base supplies unloaded go-home behavior. Its
    # raid-specific signal and other raid goals are omitted for townsfolk.
    retreat = {section: [] for section, *_ in km.SECOES}
    retreat.update(instance_count=0, typecode=72, id=11303, name=b'KS Town retreat',
                   strid=sid(11303), mod_data_type=-2147483646, instances=[])
    retreat['bool'] = [(b'clears existing jobs', 1)]
    retreat['long'] = [(b'signal func', 0), (b'unloaded func', 4)]
    retreat_goals = [
        (b'2542-gamedata.base', 0, 100, 0),    # Go Home (Run away)
        (b'2825-gamedata.base', 0, 100, 0),    # Protect squad
        (b'62008-rebirth.mod', 0, 24, 0),      # Medic
    ]
    retreat['extra'] = [(b'Leader AI Goals', list(retreat_goals)), (b'Squad AI Goals', list(retreat_goals))]
    mod['records'].append(retreat)

    guards = deepcopy(by_id[sid(11000)])
    assert guards['typecode'] == 52
    guards.update(id=11500, name=b'KS Hired tower guards', strid=sid(11500))
    mod['records'].append(guards)

    mod['description'] = (
        b'KenshiShop 1.0 beta.8.1: chief services, two additional squads '
        b'and confirmed town departure.'
    )
    mod['unknown'] = 11600
    assert len(mod['records']) == 288
    km.gravar(destination, mod)
    assert km.serializar(km.ler(destination)) == destination.read_bytes()


if __name__ == '__main__':
    build(*map(Path, sys.argv[1:3]))
