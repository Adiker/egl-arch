#!/usr/bin/env python3
"""Prepare the prebuilt AUR recipe for a published GitHub release."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

PACKAGE = 'epic-games-launcher-proton-bin'

def field(text, name):
    matches = re.findall(rf'^{re.escape(name)}=([0-9.]+)$', text, re.M)
    if len(matches) != 1:
        raise ValueError(f'Expected one {name} assignment')
    return matches[0]

def replace(text, pattern, replacement):
    result, count = re.subn(pattern, lambda _: replacement, text, flags=re.M)
    if count != 1:
        raise ValueError(f'Expected one match for {pattern}')
    return result

def metadata(path):
    values = {}
    for line in path.read_text().splitlines():
        if ' = ' in line:
            key, value = line.strip().split(' = ', 1)
            values.setdefault(key, []).append(value)
    return values

def prepare(aur, release, tag):
    match = re.fullmatch(r'v(\d+\.\d+\.\d+)-(\d+)', tag)
    if not match:
        raise ValueError('Unexpected release tag')
    version, revision = match.groups()
    recipe = aur / 'PKGBUILD'
    original = recipe.read_text()
    oldver, oldrel, oldsource = (field(original, x) for x in ('pkgver', 'pkgrel', '_release'))
    if not re.search(r'(?m)^# Repackage the complete, prebuilt GitHub release;', original):
        raise ValueError('Unrecognized AUR recipe; manual review required')
    result = subprocess.check_output(['vercmp', version, oldver], text=True).strip()
    if int(result) < 0 or (int(result) == 0 and int(revision) < int(oldsource)):
        raise ValueError('Refusing to downgrade AUR')
    expected_name = f'{PACKAGE}-{version}-{revision}-x86_64.pkg.tar.zst'
    lines = (release / 'SHA256SUMS').read_text().splitlines()
    sums = [m.group(1) for line in lines if (m := re.fullmatch(r'([a-f0-9]{64})  ' + re.escape(expected_name), line))]
    if len(sums) != 1:
        raise ValueError('Missing or ambiguous release checksum')
    checksum = sums[0]
    archive = release / expected_name
    with archive.open('rb') as stream:
        if hashlib.file_digest(stream, 'sha256').hexdigest() != checksum:
            raise ValueError('Release package checksum mismatch')
    release_meta, aur_meta = metadata(release / 'SRCINFO'), metadata(aur / '.SRCINFO')
    for key in ('pkgbase', 'arch', 'license', 'depends', 'provides', 'conflicts'):
        if key == 'provides':
            if release_meta.get(key) != [f'epic-games-launcher={version}']:
                raise ValueError('Unexpected release provides')
        elif sorted(release_meta.get(key, [])) != sorted(aur_meta.get(key, [])):
            raise ValueError(f'{key} changed; manual review required')
    if release_meta.get('pkgver') != [version] or release_meta.get('pkgrel') != [revision]:
        raise ValueError('Release metadata does not match tag')
    same = version == oldver and revision == oldsource
    current_sum = re.findall(r"(?m)^sha256sums=\('([a-f0-9]{64})'\)$", original)
    if len(current_sum) != 1:
        raise ValueError('Unrecognized AUR checksum')
    if same:
        if current_sum[0] != checksum:
            raise ValueError('Existing release checksum changed')
        print('AUR is already current')
        return False
    newrel = str(int(oldrel) + 1) if version == oldver else '1'
    updated = original
    for name, value in [('pkgver', version), ('pkgrel', newrel), ('_release', revision)]:
        updated = replace(updated, rf'^{name}=[0-9.]+$', f'{name}={value}')
    updated = replace(updated, r"^sha256sums=\('[a-f0-9]{64}'\)$", f"sha256sums=('{checksum}')")
    recipe.write_text(updated)
    (aur / '.SRCINFO').write_text(subprocess.check_output(['makepkg', '--printsrcinfo'], cwd=aur, text=True))
    print(f'Prepared AUR {version}-{newrel} from release {tag}')
    return True

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('aur', type=Path)
    parser.add_argument('release', type=Path)
    parser.add_argument('tag')
    args = parser.parse_args()
    prepare(args.aur.resolve(), args.release.resolve(), args.tag)
