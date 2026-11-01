import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('aur_note', Path(__file__).parents[1] / 'scripts/aur-release-note.py')
note = importlib.util.module_from_spec(spec)
spec.loader.exec_module(note)

class ReleaseNoteTests(unittest.TestCase):
    def test_pending_becomes_verified_and_is_idempotent(self):
        text = 'Release notes\n\n' + note.START + '\nAUR: synchronization pending.\n' + note.END + '\n'
        updated = note.update_body(text, 'v0.108.0-1', 'a' * 40)
        self.assertIn('synchronized with v0.108.0-1', updated)
        self.assertNotIn('pending', updated)
        self.assertEqual(updated, note.update_body(updated, 'v0.108.0-1', 'a' * 40))

    def test_legacy_note_and_other_text(self):
        updated = note.update_body('Intro. AUR publication is managed separately.\n', 'v0.108.0-1', 'a' * 40)
        self.assertIn('Intro.', updated)
        self.assertNotIn(note.OLD, updated)

    def test_invalid_markers_are_rejected(self):
        with self.assertRaises(ValueError):
            note.update_body(note.START, 'v0.108.0-1', 'a' * 40)

    def test_invalid_identifiers_are_rejected(self):
        with self.assertRaises(ValueError):
            note.update_body('', 'bad', 'a' * 40)
        with self.assertRaises(ValueError):
            note.update_body('', 'v0.108.0-1', 'bad')
