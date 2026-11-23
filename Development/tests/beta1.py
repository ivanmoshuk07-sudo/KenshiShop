"""Read-only beta audit; optionally verify an already built FULL ZIP.

Run from any directory: python Development/tests/beta1.py [archive.zip]
This checks shipped references and inventory, not the native game AI.
"""
from pathlib import Path, PurePosixPath
import argparse
import re
import struct
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'Development'))
import kenshimod as km


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def lua_tokens(source):
    """Enough lexical structure to ignore comments and strings containing code."""
    i = 0
    while i < len(source):
        if source[i].isspace():
            i += 1
            continue
        comment = source.startswith('--', i)
        start = i + 2 if comment else i
        bracket = re.match(r'\[(=*)\[', source[start:])
        if bracket:
            end_marker = ']' + bracket.group(1) + ']'
            content_start = start + len(bracket.group(0))
            end = source.find(end_marker, content_start)
            require(end >= 0, 'unterminated Lua long string/comment')
            if not comment:
                yield ('string', source[content_start:end])
            i = end + len(end_marker)
            continue
        if comment:
            end = source.find('\n', i)
            i = len(source) if end < 0 else end + 1
            continue
        if source[i] in "\"'":
            quote, value = source[i], []
            i += 1
            while i < len(source) and source[i] != quote:
                if source[i] == '\\':
                    i += 1
                    require(i < len(source), 'unterminated Lua quoted escape')
                value.append(source[i])
                i += 1
            require(i < len(source), 'unterminated Lua quoted string')
            i += 1
            yield ('string', ''.join(value))
            continue
        identifier = re.match(r'[A-Za-z_][A-Za-z_0-9]*', source[i:])
        if identifier:
            value = identifier.group(0)
            i += len(value)
            yield ('identifier', value)
        else:
            yield ('symbol', source[i])
            i += 1


def literal_requires(source):
    tokens = list(lua_tokens(source))
    for i, token in enumerate(tokens):
        if token == ('identifier', 'require'):
            after = tokens[i + 1:i + 3]
            if after and after[0][0] == 'string':
                yield after[0][1]
            elif len(after) == 2 and after[0] == ('symbol', '(') and after[1][0] == 'string':
                yield after[1][1]
        elif token == ('identifier', 'pcall'):
            after = tokens[i + 1:i + 5]
            if (len(after) == 4 and after[:3] == [
                    ('symbol', '('), ('identifier', 'require'), ('symbol', ',')]
                    and after[3][0] == 'string'):
                yield after[3][1]


def audit_lua():
    scripts = ROOT / 'KenshiShop/scripts'
    files = set(scripts.rglob('*.lua'))
    require(len(files) == 122, f'expected 122 Lua modules, found {len(files)}')
    seen, todo = set(), [scripts / 'init/main.lua']
    while todo:
        path = todo.pop()
        if path in seen:
            continue
        require(path in files, f'missing Lua module: {path}')
        seen.add(path)
        for name in literal_requires(path.read_text(encoding='utf-8')):
            relative = name.replace('.', '/')
            choices = [scripts / (relative + '.lua'), scripts / relative / 'init.lua']
            matches = [p for p in choices if p in files]
            require(matches, f'{path.relative_to(ROOT)} requires missing {name}')
            todo.append(matches[0])
    require(seen == files, 'unreachable Lua modules: ' + ', '.join(
        str(p.relative_to(scripts)) for p in sorted(files - seen)))
    for name in ['Core.lua', 'KenshiLuaConsole.lua']:
        require('1.0-beta.11' in (scripts / name).read_text(encoding='utf-8'),
                f'{name} does not identify beta 1.0')
    print('PASS all 122 Lua modules reachable from init.main; literal requires resolve; beta version matches')


def audit_mods():
    mods = []
    for name, count in [('KenshiShop', 287), ('KenshiShop_LegendaryCompat', 73)]:
        path = ROOT / name / (name + '.mod')
        mod = km.ler(path)
        require(km.serializar(mod) == path.read_bytes(), f'{name}: binary roundtrip differs')
        records = mod['records']
        require(len(records) == count, f'{name}: unexpected record count {len(records)}')
        ids = {r['strid'] for r in records}
        require(len(ids) == len(records), f'{name}: duplicate record IDs')
        suffix = ('-' + name + '.mod').encode()
        for record in records:
            for section in ['bool', 'float', 'long', 'vec3', 'vec4', 'string', 'filename', 'extra']:
                keys = [key for key, _ in record[section]]
                require(len(set(keys)) == len(keys), f'{record["strid"]}: duplicate {section} fields')
            refs = [sid for _, rows in record['extra'] for sid, *_ in rows]
            refs += [sid for _, target, _, _, states in record['instances'] for sid in [target, *states]]
            for sid in refs:
                require(not sid.endswith(suffix) or sid in ids,
                        f'{record["strid"]}: missing local reference {sid}')
        mods.append(mod)
        print(f'PASS {name}: {count} records, exact binary roundtrip, unique IDs/fields, local references resolve')
    # The optional compatibility file overrides main-mod records and can point
    # to records supplied by the main mod rather than by itself.
    all_ids = {record['strid'] for mod in mods for record in mod['records']}
    local_suffixes = (b'-KenshiShop.mod', b'-KenshiShop_LegendaryCompat.mod')
    for mod in mods:
        for record in mod['records']:
            refs = [sid for _, rows in record['extra'] for sid, *_ in rows]
            refs += [sid for _, target, _, _, states in record['instances'] for sid in [target, *states]]
            for sid in refs:
                require(not sid.endswith(local_suffixes) or sid in all_ids,
                        f'{record["strid"]}: missing cross-mod reference {sid}')
    return mods


def mesh_materials(data):
    """Read plausible OGRE submesh chunk headers (0x4000) and material names."""
    start = 0
    while True:
        offset = data.find(b'\x00\x40', start)
        if offset < 0:
            return
        start = offset + 2
        if offset + 7 > len(data):
            continue
        size = struct.unpack_from('<I', data, offset + 2)[0]
        if not 8 <= size <= len(data) - offset:
            continue
        end = data.find(b'\n', offset + 6, min(offset + size, offset + 108))
        if end < 0:
            continue
        name = data[offset + 6:end]
        if name and all(32 <= char <= 126 for char in name):
            yield name.decode('ascii')


def audit_assets(mods):
    files = {p.relative_to(ROOT).as_posix().lower(): p
             for p in (ROOT / 'KenshiShop/character').rglob('*') if p.is_file()}
    require(len(files) == 84, f'expected 84 character resources, found {len(files)}')
    used = set()
    for mod in mods:
        for record in mod['records']:
            for section in ['string', 'filename']:
                for key, value in record[section]:
                    relative = value.decode('utf-8', errors='replace').replace('\\', '/').lower()
                    if relative.startswith('./mods/'):
                        relative = relative[len('./mods/'):]
                    if relative.startswith('kenshishop/character/'):
                        require(relative in files, f'{record["strid"]}/{key}: missing asset {relative}')
                        used.add(relative)
    materials = {name for path in files.values() if path.suffix.lower() == '.mesh'
                 for name in mesh_materials(path.read_bytes())}
    for relative, path in files.items():
        if path.suffix.lower() == '.material':
            names = re.findall(r'\bmaterial\s+([^\s{]+)', path.read_text(encoding='utf-8'))
            require(names and all(name in materials for name in names),
                    f'unused material definitions: {relative}')
            used.add(relative)
    require(used == files.keys(), f'unreferenced character resources: {sorted(files.keys() - used)}')
    print('PASS all 84 character resources resolve and are used, including indirect OGRE material reference')


def audit_archive(path):
    expected = {p.relative_to(ROOT).as_posix(): p
                for folder in ['KenshiShop', 'KenshiShop_LegendaryCompat']
                for p in (ROOT / folder).rglob('*') if p.is_file()
                and 'History' not in p.relative_to(ROOT).parts}
    native = [
        'Development/NativeBridge/KenshiShopNative.cpp',
        'Development/NativeBridge/LimbProtection.h',
        'Development/NativeBridge/vendor/KenshiLua.h',
        'Development/NativeBridge/LICENSE',
    ]
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        require(len(names) == len(set(names)), 'ZIP has duplicate paths')
        require(all(not PurePosixPath(name).is_absolute() and '..' not in PurePosixPath(name).parts
                    and '\\' not in name for name in names), 'ZIP has unsafe paths')
        actual = {name for name in names if not name.endswith('/') and
                  name.startswith(('KenshiShop/', 'KenshiShop_LegendaryCompat/'))}
        require(actual == expected.keys(), 'ZIP runtime inventory differs: missing=' +
                str(sorted(expected.keys() - actual)) + '; extra=' + str(sorted(actual - expected.keys())))
        for name, file in expected.items():
            require(archive.read(name) == file.read_bytes(), f'ZIP runtime file differs: {name}')
        for name in native:
            require(name in names and archive.read(name) == (ROOT / name).read_bytes(),
                    f'ZIP lacks matching native source/license: {name}')
        require(archive.testzip() is None, 'ZIP CRC failure')
    print(f'PASS FULL ZIP: {len(expected)} exact runtime files; native source/license included; safe paths and CRC')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', nargs='?', type=Path)
    args = parser.parse_args()
    mods = audit_mods()
    audit_lua()
    audit_assets(mods)
    if args.archive:
        audit_archive(args.archive)


if __name__ == '__main__':
    main()
