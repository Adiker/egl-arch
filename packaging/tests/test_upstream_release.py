import importlib.util
from pathlib import Path
import unittest
import hashlib
import json
import os
import tempfile
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('release', Path(__file__).parents[1] / 'scripts/upstream-release.py')
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)
BASE = """pkgver=0.97.0
pkgrel=4
_epic_gitrev=4f63cc1
sha256sums=(
  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
  'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' # port sources
)
"""


class DiscoveryTests(unittest.TestCase):
    def test_current_keeps_revision_and_expected_hash(self):
        plan = release.candidate('0.97.0+g4f63cc1', BASE)
        self.assertFalse(plan['changed'])
        self.assertEqual(plan['tag'], 'v0.97.0-4')
        self.assertEqual(plan['expected_sha256'], 'a' * 64)

    def test_new_version_resets_release(self):
        plan = release.candidate('0.98.0+gabcdef1', BASE)
        self.assertTrue(plan['changed'])
        self.assertEqual(plan['tag'], 'v0.98.0-1')
        self.assertIsNone(plan['expected_sha256'])

    def test_rebuilt_same_version_increases_release(self):
        self.assertEqual(release.candidate('0.97.0+gabcdef1', BASE)['pkgrel'], 5)

    def test_numeric_order_and_downgrade_guard(self):
        self.assertEqual(release.candidate('0.100.0+gabcdef1', BASE)['pkgver'], '0.100.0')
        with self.assertRaises(ValueError):
            release.candidate('0.96.9+gabcdef1', BASE)

    def test_untrusted_versions_are_rejected(self):
        for value in ['latest', '0.98.0+gabcdef1\nfoo=bar', '$(id)', '../0.98.0', '0.98.0+gBAD1234']:
            with self.subTest(value=value), self.assertRaises(ValueError):
                release.candidate(value, BASE)

    def test_installer_agreement_and_host(self):
        plan = release.candidate('0.97.0+g4f63cc1', BASE)
        release.verify_redirect(plan['url'] + '?launcherfilename=EpicGamesLauncher-x86_64.AppImage', plan)
        release.verify_redirect(plan['url'].replace('%2B', '+'), plan)
        for url in [plan['url'].replace('https:', 'http:'), plan['url'].replace('0.97.0', '0.98.0'),
                    plan['url'].replace('content-download-egs.distro.on.epicgames.com', 'example.org')]:
            with self.subTest(url=url), self.assertRaises(ValueError):
                release.verify_redirect(url, plan)

    def test_ambiguous_package_metadata_is_rejected(self):
        with self.assertRaises(ValueError):
            release.candidate('0.97.0+g4f63cc1', BASE + 'pkgver=0.98.0\n')

    def test_same_version_replacement_is_rejected_before_edit(self):
        plan = release.candidate('0.97.0+g4f63cc1', BASE)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            pkgbuild = root / 'PKGBUILD'
            pkgbuild.write_text(BASE)
            def download(args, **kwargs):
                Path(args[args.index('--output') + 1]).write_bytes(b'changed upstream image')
            previous = Path.cwd()
            try:
                os.chdir(root)
                with patch.object(release, 'PKGBUILD', pkgbuild), patch.dict(os.environ, RELEASE_PLAN=json.dumps(plan)), \
                     patch.object(release.subprocess, 'run', side_effect=download):
                    with self.assertRaisesRegex(ValueError, 'different AppImage checksum'):
                        release.stage()
                self.assertEqual(pkgbuild.read_text(), BASE)
            finally:
                os.chdir(previous)

    def test_stage_new_version_preserves_source_hash_until_refresh(self):
        plan = release.candidate('0.98.0+gabcdef1', BASE)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            pkgbuild = root / 'PKGBUILD'
            pkgbuild.write_text(BASE)
            def download(args, **kwargs):
                Path(args[args.index('--output') + 1]).write_bytes(b'new AppImage')
            previous = Path.cwd()
            try:
                os.chdir(root)
                with patch.object(release, 'PKGBUILD', pkgbuild), \
                     patch.dict(os.environ, RELEASE_PLAN=json.dumps(plan), GITHUB_SHA='c' * 40), \
                     patch.object(release.subprocess, 'run', side_effect=download):
                    release.stage()
                self.assertEqual(release.current_metadata(pkgbuild.read_text()),
                                 ('0.98.0', 1, 'abcdef1', hashlib.sha256(b'new AppImage').hexdigest()))
                self.assertIn("'" + 'b' * 64 + "' # port sources", pkgbuild.read_text())
                self.assertEqual(json.loads((root / 'build/arch/upstream.json').read_text())['build_commit'], 'c' * 40)
            finally:
                os.chdir(previous)

    def test_draft_recovery_when_tag_lookup_returns_404(self):
        draft = dict(tag_name='v0.98.0-1', draft=True)
        with patch.object(release, 'api', side_effect=[None, [draft]]):
            self.assertEqual(release.release_info('v0.98.0-1'), draft)


if __name__ == '__main__':
    unittest.main()
