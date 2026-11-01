#!/usr/bin/env python3
"""Record a verified AUR commit in a release without overwriting other notes."""
import argparse
import json
import re
import subprocess
import tempfile
from pathlib import Path

START = '<!-- aur-sync:start -->'
END = '<!-- aur-sync:end -->'
OLD = 'AUR publication is managed separately.'

def update_body(body, tag, commit):
    if not re.fullmatch(r'v\d+\.\d+\.\d+-\d+', tag):
        raise ValueError('Unexpected release tag')
    if not re.fullmatch(r'[0-9a-f]{40}', commit):
        raise ValueError('Unexpected AUR commit')
    block = (f'{START}\nAUR: [synchronized with {tag}]'
             f'(https://aur.archlinux.org/cgit/aur.git/commit/?h=epic-games-launcher-proton-bin&id={commit}) '
             f'(verified at this commit).\n{END}')
    if body.count(START) != body.count(END) or body.count(START) > 1:
        raise ValueError('Ambiguous AUR status markers')
    if START in body:
        pattern = re.escape(START) + r'.*?' + re.escape(END)
        result, count = re.subn(pattern, lambda _: block, body, flags=re.S)
        if count != 1:
            raise ValueError('Invalid AUR status markers')
        return result
    if OLD in body:
        body = body.replace(OLD, '', 1).rstrip()
    return body.rstrip() + '\n\n' + block + '\n'

def main(tag, commit):
    raw = subprocess.check_output(['gh', 'release', 'view', tag, '--json', 'tagName,isDraft,isPrerelease,body'], text=True)
    release = json.loads(raw)
    if release['tagName'] != tag or release['isDraft'] or release['isPrerelease']:
        raise ValueError('Expected the published stable release')
    original = release['body'] or ''
    updated = update_body(original, tag, commit)
    if updated == original:
        print('Release AUR status already current')
        return
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / 'notes.md'
        path.write_text(updated)
        subprocess.run(['gh', 'release', 'edit', tag, '--notes-file', str(path)], check=True)

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('tag')
    parser.add_argument('commit')
    args = parser.parse_args()
    main(args.tag, args.commit)
