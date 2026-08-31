#!/usr/bin/env python3

import importlib.util
from pathlib import Path
import unittest


MODULE_PATH = Path(__file__).parents[1] / "scripts" / "key-reader.py"
SPEC = importlib.util.spec_from_file_location("screencast_key_reader", MODULE_PATH)
reader = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(reader)


class KeyChordFormatterTests(unittest.TestCase):
    def setUp(self):
        self.formatter = reader.KeyChordFormatter()

    def test_single_key(self):
        self.assertEqual(self.formatter.handle(38, 1), [["L"]])
        self.assertEqual(self.formatter.handle(38, 0), [])

    def test_super_chord(self):
        self.assertEqual(self.formatter.handle(125, 1), [])
        self.assertEqual(self.formatter.handle(38, 1), [["SUPER", "L"]])
        self.assertEqual(self.formatter.handle(38, 0), [])
        self.assertEqual(self.formatter.handle(125, 0), [])

    def test_modifiers_use_stable_order(self):
        self.formatter.handle(125, 1)
        self.formatter.handle(42, 1)
        self.formatter.handle(29, 1)
        self.assertEqual(self.formatter.handle(25, 1), [["CTRL", "SHIFT", "SUPER", "P"]])

    def test_standalone_modifier_appears_on_release(self):
        self.assertEqual(self.formatter.handle(29, 1), [])
        self.assertEqual(self.formatter.handle(29, 0), [["CTRL"]])

    def test_repeat_is_suppressed(self):
        self.assertEqual(self.formatter.handle(30, 2), [])

    def test_disconnected_source_does_not_leave_modifier_stuck(self):
        self.formatter.handle(125, 1, "external")
        self.formatter.release_source("external")
        self.assertEqual(self.formatter.handle(38, 1, "laptop"), [["L"]])

    def test_friendly_key_names(self):
        self.assertEqual(reader.key_name(111), "DELETE")
        self.assertEqual(reader.key_name(164), "PLAY/PAUSE")


if __name__ == "__main__":
    unittest.main()
