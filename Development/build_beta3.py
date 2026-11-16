"""Beta 3: chief service dialogue and a private three-person night patrol.

Input is beta.2. Existing gameplay records remain unchanged except the chief's
additional dialogue-package reference. Native payment is handled by the Lua
service only after validation, never by an unconditional dialogue action.
"""
from pathlib import Path
import copy
import sys

import kenshimod as km


def build(source, destination):
    mod = km.ler(source)
    assert km.serializar(mod) == source.read_bytes()
    by = {record['strid']: record for record in mod['records']}
    assert len(by) == 242 and b'11000-KenshiShop.mod' not in by, 'Input must be beta.2'

    def clone(sid, number, name):
        record = km.clonar_registro(by[sid.encode()], f'{number}-KenshiShop.mod', name)
        record['id'] = number
        mod['records'].append(record)
        return record

    def fresh(number, kind, name):
        record = {section: [] for section, *_ in km.SECOES}
        record.update(instance_count=0, typecode=kind, id=number, name=name.encode(),
                      strid=f'{number}-KenshiShop.mod'.encode(),
                      mod_data_type=-2147483646, extra=[], instances=[])
        mod['records'].append(record)
        return record

    squad = clone('311-KenshiShop.mod', 11000, 'KS Chief services: hired night patrol (3)')
    assert km.set_campo(squad, 'bool', 'dont multiply', 1)
    # One leader plus two followers is the original exact squad composition.
    assert dict(squad['extra'])[b'leader'] == [(b'312-KenshiShop.mod', 1, 0, 0)]
    assert dict(squad['extra'])[b'squad'] == [(b'312-KenshiShop.mod', 2, 2, 0)]

    package = clone('10004-KenshiShop.mod', 11001, 'KSB3 Hired night patrol')
    for category, rows in package['extra']:
        if b'AI Goals' not in category:
            continue
        updated = []
        for sid, start, end, weight in rows:
            if sid in (b'10014-KenshiShop.mod', b'10015-KenshiShop.mod'):
                assert (start, end) == (6, 23)
                updated.extend([(sid, 0, 6, weight), (sid, 23, 24, weight)])
            else:
                updated.append((sid, start, end, weight))
        rows[:] = updated

    dialog_package = fresh(11100, 73, 'KS Chief services dialogue package')
    dialog_package['extra'] = [(b'dialogs', [(b'11101-KenshiShop.mod', 1, 0, 0)])]
    dialog = fresh(11101, 18, 'KS Chief services: player conversation')
    dialog['bool'] = [(b'for enemies', 0), (b'locked', 0), (b'monologue', 1),
                      (b'once only', 0), (b'one at a time', 0)]
    dialog['float'] = [(b'chance permanent', 100.0), (b'chance temporary', 100.0)]
    dialog['long'] = [(b'repetition limit', 0), (b'score bonus', 100), (b'target is type', 0)]
    dialog['extra'] = [(b'lines', [(b'11102-KenshiShop.mod', 100, 0, 0)])]

    def line(number, speaker, name, text, children=()):
        record = fresh(number, 19, name)
        record['float'] = [(b'chance permanent', 100.0), (b'chance temporary', 100.0)]
        record['long'] = [(b'repetition limit', 0), (b'score bonus', 0),
                          (b'speaker', speaker), (b'target is type', 0)]
        record['string'] = [(b'text0', text.encode())]
        if children:
            record['extra'] = [(b'lines', [(f'{n}-KenshiShop.mod'.encode(), 0, 0, 0)
                                         for n in children])]
        return record

    line(11102, 0, 'KS Chief services greeting',
         'Что требуется городу? Проверю потери или найму дополнительный ночной патруль.',
         [11103, 11104, 11105, 11106])
    line(11103, 1, 'KS Chief services: check losses', 'Проверь, кто из наших работников погиб.')
    line(11104, 1, 'KS Chief services: replace one',
         'Нанять замену одному погибшему работнику — 10 000 кат.')
    line(11105, 1, 'KS Chief services: hire night patrol',
         'Нанять дополнительный отряд из трёх патрульных — 20 000 кат.')
    line(11106, 1, 'KS Chief services: leave', 'Пока ничего не нужно.')

    chief = by[b'7310-KenshiShop.mod']
    rows = dict(chief['extra'])[b'dialogue package']
    assert (b'9660-Dialogue.mod', 0, 0, 0) in rows
    rows.append((b'11100-KenshiShop.mod', 0, 0, 0))
    mod['description'] = (
        b'KenshiShop 1.0 beta.3: chief dialogue for confirmed-death replacement and '
        b'paid additional three-person night patrols. Native priorities 3/2/1, '
        b'existing shops, schedules, furniture, stock and limb protection retained.'
    )
    mod['unknown'] = max(mod['unknown'], 11200)
    km.gravar(destination, mod)
    assert km.serializar(km.ler(destination)) == destination.read_bytes()
    print('beta.3 written:', len(mod['records']), 'records; chief dialogue added; existing base patrol unchanged')


if __name__ == '__main__':
    build(*map(Path, sys.argv[1:3]))
