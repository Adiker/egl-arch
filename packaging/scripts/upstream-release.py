#!/usr/bin/env python3
"""Discover Epic's stable AppImage and prepare/publish a tested Arch release."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
from urllib.parse import unquote, urlsplit
from urllib.request import Request, urlopen
from urllib.error import HTTPError

STABLE = "https://content-download-egs.distro.on.epicgames.com/Builds/EGLv2/stable-target.json"
INSTALLER = "https://launcher-public-service-prod06.ol.epicgames.com/launcher/api/installer/download/EpicGamesLauncher-x86_64.AppImage"
PKGBUILD = Path("packaging/arch/PKGBUILD")
PACKAGE = "epic-games-launcher-proton-bin"


def run(*args, **kwargs):
    return subprocess.check_output(args, text=True, **kwargs).strip()


def digest(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def field(text, key):
    matches = re.findall(rf"^{re.escape(key)}=([A-Za-z0-9.]+)$", text, re.M)
    if len(matches) != 1:
        raise ValueError(f"Expected exactly one simple {key} assignment")
    return matches[0]


def current_metadata(text):
    version, revision = field(text, "pkgver"), field(text, "_epic_gitrev")
    checksums = re.findall(r"^  '([a-f0-9]{64})'(?: # port sources)?$", text, re.M)
    if len(checksums) != 2:
        raise ValueError("Expected exactly two pinned SHA256 checksums")
    return version, int(field(text, "pkgrel")), revision, checksums[0]


def candidate(version, text):
    match = re.fullmatch(r"([0-9]+\.[0-9]+\.[0-9]+)\+g([a-f0-9]{7,40})", version)
    if not match:
        raise ValueError(f"Unsupported stable version format: {version!r}")
    pkgver, gitrev = match.groups()
    oldver, oldrel, oldrev, checksum = current_metadata(text)
    if tuple(map(int, pkgver.split('.'))) < tuple(map(int, oldver.split('.'))):
        raise ValueError("Stable metadata requests a downgrade; manual review required")
    changed = (pkgver, gitrev) != (oldver, oldrev)
    pkgrel = (1 if pkgver != oldver else oldrel + 1) if changed else oldrel
    return dict(version=version, pkgver=pkgver, pkgrel=pkgrel, gitrev=gitrev,
                changed=changed, expected_sha256=None if changed else checksum,
                tag=f"v{pkgver}-{pkgrel}",
                image=f"EpicGamesLauncher-{pkgver}+g{gitrev}-x86_64.AppImage",
                url=f"https://content-download-egs.distro.on.epicgames.com/Builds/EGLv2/{pkgver}%2Bg{gitrev}/Linux/EpicGamesLauncher-x86_64.AppImage")


def verify_redirect(url, plan):
    actual, expected = urlsplit(url), urlsplit(plan['url'])
    if (actual.scheme, actual.netloc, unquote(actual.path)) != (expected.scheme, expected.netloc, unquote(expected.path)):
        raise ValueError("Stable metadata and official installer redirect disagree")


def api(path):
    request = Request(f"https://api.github.com/repos/{os.environ['GITHUB_REPOSITORY']}/{path}",
                      headers={"Authorization": f"Bearer {os.environ['GH_TOKEN']}",
                               "Accept": "application/vnd.github+json"})
    try:
        with urlopen(request, timeout=60) as response:
            return json.load(response)
    except HTTPError as error:
        if error.code == 404:
            return None
        raise


def assets(plan):
    stem = f"{plan['pkgver']}-{plan['pkgrel']}"
    return [f"{PACKAGE}-{stem}-x86_64.pkg.tar.zst", f"egl-arch-sources-{stem}.tar.xz",
            "PKGBUILD", ".SRCINFO", "upstream.json", "SHA256SUMS"]


def release_info(tag):
    release = api(f"releases/tags/{tag}")
    if release:
        return release
    # A draft may not have a public Git tag yet. The publisher can still see it
    # in the releases list and complete a previously interrupted publication.
    return next((r for r in api('releases?per_page=100') if r['tag_name'] == tag), None)


def output(key, value):
    with Path(os.environ['GITHUB_OUTPUT']).open('a') as stream:
        stream.write(f"{key}={value}\n")


def check():
    with urlopen(STABLE, timeout=60) as response:
        version = json.load(response)['version']
    plan = candidate(version, PKGBUILD.read_text())
    with urlopen(Request(INSTALLER, method='HEAD'), timeout=60) as response:
        verify_redirect(response.url, plan)
    release = release_info(plan['tag'])
    existing = {asset['name'] for asset in release['assets']} if release else set()
    complete = release and not release['draft'] and set(assets(plan)) <= existing
    build = plan['changed'] or not complete or os.environ.get('BUILD_CURRENT') == 'true'
    output('build', str(bool(build)).lower())
    output('plan', json.dumps(plan, separators=(',', ':')))
    print(f"Stable {version}; target {plan['tag']}; build={bool(build)}")


def stage():
    plan = json.loads(os.environ['RELEASE_PLAN'])
    text = PKGBUILD.read_text()
    # Re-derive every build instruction rather than trusting arbitrary JSON URLs.
    if plan != candidate(plan['version'], text):
        raise ValueError("Candidate plan no longer matches the checked-out PKGBUILD")
    work = Path('build/arch')
    work.mkdir(parents=True, exist_ok=True)
    image = work / plan['image']
    subprocess.run(['curl', '--fail', '--location', '--proto', '=https', '--proto-redir', '=https',
                    '--retry', '3', '--max-time', '600', '--output', str(image), plan['url']], check=True)
    checksum = digest(image)
    if plan['expected_sha256'] and checksum != plan['expected_sha256']:
        raise ValueError("Same upstream version has a different AppImage checksum; refusing to repin")
    for key, value in [('pkgver', plan['pkgver']), ('pkgrel', plan['pkgrel']), ('_epic_gitrev', plan['gitrev'])]:
        text = re.sub(rf"^{key}=.*$", f"{key}={value}", text, count=1, flags=re.M)
    text = re.sub(r"(?m)^  '[a-f0-9]{64}'$", f"  '{checksum}'", text, count=1)
    PKGBUILD.write_text(text)
    plan['appimage_sha256'] = checksum
    plan['build_commit'] = os.environ['GITHUB_SHA']
    (work / 'upstream.json').write_text(json.dumps(plan, indent=2) + '\n')


def manifest():
    work = Path('build/arch')
    plan = json.loads((work / 'upstream.json').read_text())
    with (work / 'SHA256SUMS').open('w') as stream:
        for name in assets(plan):
            if name != 'SHA256SUMS':
                stream.write(f"{digest(work / name)}  {name}\n")


def publish():
    work = Path('release-assets')
    plan = json.loads((work / 'upstream.json').read_text())
    expected = json.loads(os.environ['RELEASE_PLAN'])
    if any(plan.get(key) != value for key, value in expected.items()):
        raise ValueError("Build artifact plan differs from discovery job")
    subprocess.run(['sha256sum', '--strict', '--check', 'SHA256SUMS'], cwd=work, check=True)
    # Do not publish an older checkout over new work on main.
    remote = run('git', 'ls-remote', 'origin', 'refs/heads/main').split()[0]
    if remote != os.environ['GITHUB_SHA']:
        raise ValueError("main changed during the build; rerun against the new head")
    release = release_info(plan['tag'])
    existing = {asset['name']: asset for asset in release['assets']} if release else {}
    # Check every collision before committing metadata or uploading any asset.
    # A failed rebuild must never repoint main at a conflicting source archive.
    if release and not release['draft']:
        for name in assets(plan):
            if name not in existing:
                continue
            with tempfile.TemporaryDirectory() as directory:
                run('gh', 'release', 'download', plan['tag'], '--pattern', name, '--dir', directory)
                if digest(Path(directory) / name) != digest(work / name):
                    raise ValueError(f"Published asset {name} differs; refusing to overwrite")
    for name in ('PKGBUILD', '.SRCINFO'):
        (Path('packaging/arch') / name).write_bytes((work / name).read_bytes())
    subprocess.run(['git', 'add', 'packaging/arch/PKGBUILD', 'packaging/arch/.SRCINFO'], check=True)
    if run('git', 'diff', '--cached', '--name-only'):
        run('git', '-c', 'user.name=github-actions[bot]', '-c',
            'user.email=41898282+github-actions[bot]@users.noreply.github.com',
            'commit', '-m', f"Update Epic AppImage to {plan['version']}")
        run('git', 'push', 'origin', 'HEAD:main')
    commit = run('git', 'rev-parse', 'HEAD')
    if not release:
        # Never attach a new release to a tag left by a different operation.
        if run('git', 'ls-remote', 'origin', f"refs/tags/{plan['tag']}"):
            raise ValueError("Release tag already exists without release metadata")
        notes = (f"Native Epic Games Launcher Preview {plan['version']} for Arch Linux / EndeavourOS.\n\n"
                 "Built and tested automatically using system GTK/GLib/WebKitGTK. "
                 "Includes per-game Proton selection and Wayland-first integration.\n\n"
                 "SHA256SUMS covers the package, port sources and metadata. "
                 "AppImage SHA256 is recorded in upstream.json and PKGBUILD.\n\n"
                 "Install the downloaded package with `sudo pacman -U ./epic-games-launcher-proton-bin-*.pkg.tar.zst`. "
                 "User data and games are preserved. AUR publication is managed separately.\n")
        run('gh', 'release', 'create', plan['tag'], '--target', commit, '--draft',
            '--title', f"Arch / EndeavourOS port {plan['pkgver']}-{plan['pkgrel']}", '--notes', notes)
        release = release_info(plan['tag'])
    existing = {asset['name']: asset for asset in release['assets']}
    for name in assets(plan):
        if name in existing and not release['draft']:
            continue
        args = ['gh', 'release', 'upload', plan['tag'], str(work / name)]
        if release['draft']:
            args.append('--clobber')
        run(*args)
    if release['draft']:
        run('gh', 'release', 'edit', plan['tag'], '--draft=false', '--latest')
    confirmed = api(f"releases/tags/{plan['tag']}")
    if confirmed['draft'] or not set(assets(plan)) <= {a['name'] for a in confirmed['assets']}:
        raise ValueError("Release publication verification failed")
    print(confirmed['html_url'])
    with Path(os.environ['GITHUB_STEP_SUMMARY']).open('a') as stream:
        stream.write(f"Published [{plan['tag']}]({confirmed['html_url']}) with all six assets.\n")


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['check', 'stage', 'manifest', 'publish'])
    globals()[parser.parse_args().action]()
