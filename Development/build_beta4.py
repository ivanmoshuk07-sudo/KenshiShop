"""Beta 4: native, paged selection of a confirmed-dead worker before payment.

Input is beta.3. The old direct replacement reply remains in the file for
compatibility, but is no longer reachable. Lua fills and locks the six native
slots per conversation; payment is still validated and charged by the service.
"""
from pathlib import Path
import sys

import kenshimod as km


def build(source, destination):
    mod = km.ler(source)
    assert km.serializar(mod) == source.read_bytes()
    by = {record['strid']: record for record in mod['records']}
    assert len(by) == len(mod['records']) == 251, 'Input must be beta.3'
    assert mod['unknown'] == 11200 and b'11200-KenshiShop.mod' not in by

    def line(number, speaker, name, text, children=()):
        sid = f'{number}-KenshiShop.mod'.encode()
        assert sid not in by
        record = {section: [] for section, *_ in km.SECOES}
        record.update(instance_count=0, typecode=19, id=number,
                      name=name.encode(), strid=sid, mod_data_type=-2147483646,
                      extra=[], instances=[])
        # Shared FCS records stay unlocked. The runtime locks each conversation's
        # unavailable slots through Dialogue.setLineLocked.
        record['float'] = [(b'chance permanent', 100.0), (b'chance temporary', 100.0)]
        record['long'] = [(b'repetition limit', 0), (b'score bonus', 0),
                          (b'speaker', speaker), (b'target is type', 0)]
        record['string'] = [(b'text0', text.encode())]
        if children:
            record['extra'] = [(b'lines', [(f'{n}-KenshiShop.mod'.encode(), 0, 0, 0)
                                         for n in children])]
        mod['records'].append(record)
        by[sid] = record
        return record

    greeting = by[b'11102-KenshiShop.mod']
    rows = dict(greeting['extra'])[b'lines']
    assert rows == [(f'{n}-KenshiShop.mod'.encode(), 0, 0, 0)
                    for n in range(11103, 11107)]
    rows.remove((b'11104-KenshiShop.mod', 0, 0, 0))
    losses = by[b'11103-KenshiShop.mod']
    assert not losses['extra']
    assert km.set_campo(losses, 'string', 'text0', 'Кто из наших NPC погиб?')
    losses['extra'] = [(b'lines', [(b'11200-KenshiShop.mod', 0, 0, 0)])]

    placeholder = 'Нет подтвержденной записи'
    line(11200, 0, 'KS Chief replacements: confirmed losses', placeholder,
         [*range(11210, 11216), 11220, 11221, 11222])
    for slot in range(6):
        line(11210 + slot, 1, f'KS Chief replacements: choose slot {slot + 1}',
             placeholder, [11230 + slot])
    line(11220, 1, 'KS Chief replacements: previous page', 'Предыдущие')
    line(11221, 1, 'KS Chief replacements: next page', 'Следующие')
    line(11222, 1, 'KS Chief replacements: leave', 'Закончить разговор')
    for slot in range(6):
        line(11230 + slot, 0, f'KS Chief replacements: confirm slot {slot + 1}',
             placeholder, [11240 + slot, 11250 + slot])
    for slot in range(6):
        line(11240 + slot, 1, f'KS Chief replacements: pay for slot {slot + 1}',
             'Подтверждаю: нанять замену за 10 000 кат')
    for slot in range(6):
        line(11250 + slot, 1, f'KS Chief replacements: cancel slot {slot + 1}',
             'Назад к списку')

    mod['description'] = (
        b'KenshiShop 1.0 beta.4: chief dialogue lists confirmed-dead workers, '
        b'selects one and confirms a 10,000-cat replacement. Paid additional '
        b'three-person night patrols, priorities 3/2/1, shops, schedules, '
        b'furniture, stock and limb protection retained.'
    )
    mod['unknown'] = 11300
    assert len(mod['records']) == 279
    km.gravar(destination, mod)
    assert km.serializar(km.ler(destination)) == destination.read_bytes()
    print('beta.4 written: 279 records; 28 native selection lines; old direct reply unreachable')


if __name__ == '__main__':
    build(*map(Path, sys.argv[1:3]))
