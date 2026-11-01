import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('aur_sync', Path(__file__).parents[1] / 'scripts/sync-aur.py')
sync = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sync)

class SyncTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        self.aur, self.release = root / 'aur', root / 'release'
        self.aur.mkdir(); self.release.mkdir()
        self.archive = self.release / f'{sync.PACKAGE}-0.108.0-1-x86_64.pkg.tar.zst'
        self.archive.write_bytes(b'published package')
        self.checksum = hashlib.sha256(self.archive.read_bytes()).hexdigest()
        (self.release / 'SHA256SUMS').write_text(f'{self.checksum}  {self.archive.name}\n')
        (self.release / 'SRCINFO').write_text('pkgbase = epic-games-launcher-proton-bin\n\tpkgver = 0.108.0\n\tpkgrel = 1\n\tarch = x86_64\n\tdepends = bash\n\tprovides = epic-games-launcher=0.108.0\n')
        (self.aur / '.SRCINFO').write_text('pkgbase = epic-games-launcher-proton-bin\n\tarch = x86_64\n\tdepends = bash\n')
        (self.aur / 'PKGBUILD').write_text("# Repackage the complete, prebuilt GitHub release;\npkgver=0.106.0\npkgrel=1\n_release=1\nsha256sums=('" + 'a'*64 + "')\n")
        self.proc = patch.object(sync.subprocess, 'check_output', side_effect=lambda args, **kw: '1' if args[0] == 'vercmp' else 'generated\n')
        self.proc.start(); self.addCleanup(self.proc.stop)

    def test_update(self):
        self.assertTrue(sync.prepare(self.aur, self.release, 'v0.108.0-1'))
        self.assertIn('pkgver=0.108.0', (self.aur / 'PKGBUILD').read_text())
        self.assertIn(self.checksum, (self.aur / 'PKGBUILD').read_text())

    def test_corrupt_package_is_rejected(self):
        self.archive.write_bytes(b'corrupt')
        with self.assertRaisesRegex(ValueError, 'checksum mismatch'):
            sync.prepare(self.aur, self.release, 'v0.108.0-1')

    def test_dependency_change_is_rejected(self):
        with (self.release / 'SRCINFO').open('a') as f: f.write('\tdepends = extra\n')
        with self.assertRaisesRegex(ValueError, 'depends changed'):
            sync.prepare(self.aur, self.release, 'v0.108.0-1')

    def test_downgrade_is_rejected(self):
        sync.subprocess.check_output.side_effect = lambda *a, **kw: '-1'
        with self.assertRaisesRegex(ValueError, 'downgrade'):
            sync.prepare(self.aur, self.release, 'v0.108.0-1')

    def test_same_release_checksum_change_is_rejected(self):
        p = self.aur / 'PKGBUILD'
        p.write_text(p.read_text().replace('0.106.0', '0.108.0'))
        sync.subprocess.check_output.side_effect = lambda *a, **kw: '0'
        with self.assertRaisesRegex(ValueError, 'checksum changed'):
            sync.prepare(self.aur, self.release, 'v0.108.0-1')
