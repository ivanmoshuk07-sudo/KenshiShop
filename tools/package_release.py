"""Package a complete player release; development history stays in the repository."""
from pathlib import Path
import argparse
import hashlib
import re
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
DOCS = {'README.md', 'README_BETA13_RU.md'}


def payload(name):
    return (
        (name.startswith('KenshiShop/') and not name.startswith('KenshiShop/History/'))
        or name.startswith('KenshiShop_LegendaryCompat/')
        # Corresponding native source, SDK header, probes and GPL travel with DLL.
        or name.startswith('Development/NativeBridge/')
        or name in DOCS
    )


def package(tag):
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]*', tag):
        raise ValueError('Invalid release tag')
    tracked = subprocess.check_output(['git', 'ls-files', '-z'], cwd=ROOT).decode().split('\0')
    files = sorted(name for name in tracked if payload(name))
    for required in [*DOCS, 'KenshiShop/KenshiShop.mod',
                     'KenshiShop/native/KenshiShopNative.dll',
                     'Development/NativeBridge/LICENSE']:
        if required not in files:
            raise ValueError('Missing release file: ' + required)
    out = ROOT / 'dist'
    out.mkdir(exist_ok=True)
    path = out / f'KenshiShop_{tag.removeprefix("v")}_FULL.zip'
    with zipfile.ZipFile(path, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for name in files:
            archive.write(ROOT / name, name)
    with zipfile.ZipFile(path) as archive:
        assert archive.testzip() is None
    with path.open('rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    (out / 'SHA256SUMS.txt').write_text(f'{digest}  {path.name}\n')
    print(path.name, path.stat().st_size, 'bytes;', len(files), 'files')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tag', required=True)
    package(parser.parse_args().tag)
