#!/usr/bin/env python3

import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


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

    def test_mouse_buttons(self):
        self.assertEqual(self.formatter.handle(reader.BTN_LEFT, 1, "mouse"), [["LMB"]])
        self.assertEqual(self.formatter.handle(reader.BTN_LEFT, 0, "mouse"), [])
        self.assertEqual(self.formatter.handle(reader.BTN_MIDDLE, 1, "mouse"), [["MMB"]])
        self.assertEqual(self.formatter.handle(reader.BTN_RIGHT, 1, "mouse"), [["RMB"]])

    def test_keyboard_modifier_with_mouse_button(self):
        self.assertEqual(self.formatter.handle(125, 1, "keyboard"), [])
        self.assertEqual(
            self.formatter.handle(reader.BTN_RIGHT, 1, "mouse"),
            [["SUPER", "RMB"]],
        )
        self.assertEqual(self.formatter.handle(125, 0, "keyboard"), [])

    def test_touch_buttons_are_not_displayed(self):
        self.assertFalse(reader.displayable_code(0x14A))  # BTN_TOUCH

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

    def test_resynchronized_modifier_does_not_emit_standalone_release(self):
        self.formatter.sync_source_modifiers("keyboard", {125})
        self.assertEqual(self.formatter.handle(125, 0, "keyboard"), [])

    def test_friendly_key_names(self):
        self.assertEqual(reader.key_name(111), "DELETE")
        self.assertEqual(reader.key_name(164), "PLAY/PAUSE")


class TokenBucketTests(unittest.TestCase):
    def setUp(self):
        self.now = [100.0]
        self.bucket = reader.TokenBucket(
            rate=2.0,
            burst=2.0,
            clock=lambda: self.now[0],
        )

    def test_burst_is_bounded(self):
        self.assertTrue(self.bucket.allow())
        self.assertTrue(self.bucket.allow())
        self.assertFalse(self.bucket.allow())

    def test_tokens_refill_at_configured_rate(self):
        self.bucket.allow()
        self.bucket.allow()
        self.now[0] += 0.49
        self.assertFalse(self.bucket.allow())
        self.now[0] += 0.01
        self.assertTrue(self.bucket.allow())

    def test_backward_clock_does_not_create_tokens(self):
        self.bucket.allow()
        self.bucket.allow()
        self.now[0] -= 10.0
        self.assertFalse(self.bucket.allow())
        self.now[0] = 100.5
        self.assertTrue(self.bucket.allow())


class EventReaderRateLimitTests(unittest.TestCase):
    def test_reader_limits_emitted_events(self):
        captured = []
        original_emit = reader.emit
        reader.emit = captured.append
        try:
            with tempfile.TemporaryFile() as source:
                for _index in range(20):
                    source.write(reader.EVENT.pack(0, 0, reader.EV_KEY, reader.KEY_A, 1))
                source.seek(0)
                fd = os.dup(source.fileno())
                event_reader = reader.EventReader()
                event_reader.output_limiter = reader.TokenBucket(
                    rate=0.0,
                    burst=3.0,
                    clock=lambda: 0.0,
                )
                event_reader.devices["test-device"] = fd
                event_reader.read_device("test-device", fd)
        finally:
            reader.emit = original_emit

        self.assertEqual(len(captured), 3)


class EventReaderSynchronizationTests(unittest.TestCase):
    def read_events(self, events, pressed_modifiers):
        captured = []
        with tempfile.TemporaryFile() as source:
            for event_type, code, value in events:
                source.write(reader.EVENT.pack(0, 0, event_type, code, value))
            source.seek(0)
            fd = os.dup(source.fileno())
            event_reader = reader.EventReader()
            event_reader.devices["test-device"] = fd
            try:
                with (
                    patch.object(reader, "emit", captured.append),
                    patch.object(
                        reader,
                        "_pressed_modifier_codes",
                        return_value=set(pressed_modifiers),
                    ),
                ):
                    event_reader.read_device("test-device", fd)
            finally:
                event_reader.close_device("test-device")
                event_reader.selector.close()
        return captured

    def test_syn_dropped_discards_events_until_report_and_resyncs_modifiers(self):
        captured = self.read_events(
            [
                (reader.EV_SYN, reader.SYN_DROPPED, 0),
                (reader.EV_KEY, reader.KEY_A, 1),
                (reader.EV_SYN, reader.SYN_REPORT, 0),
                (reader.EV_KEY, 38, 1),
            ],
            {125},
        )
        self.assertEqual(captured, [{"type": "key", "keys": ["SUPER", "L"]}])

    def test_syn_dropped_clears_a_stale_modifier(self):
        captured = self.read_events(
            [
                (reader.EV_KEY, 125, 1),
                (reader.EV_SYN, reader.SYN_DROPPED, 0),
                (reader.EV_SYN, reader.SYN_REPORT, 0),
                (reader.EV_KEY, 38, 1),
            ],
            set(),
        )
        self.assertEqual(captured, [{"type": "key", "keys": ["L"]}])


class EventReaderStatusTests(unittest.TestCase):
    def rescan_status(self, readable_paths, discovered_paths, denied=False):
        captured = []
        event_reader = reader.EventReader()
        event_reader.devices = {path: -1 for path in readable_paths}
        open_error = PermissionError("denied") if denied else OSError("unavailable")
        try:
            with (
                patch.object(reader, "emit", captured.append),
                patch.object(reader.glob, "glob", return_value=discovered_paths),
                patch.object(reader, "_sysfs_is_supported_input", return_value=True),
                patch.object(reader.os, "open", side_effect=open_error),
            ):
                event_reader.rescan()
        finally:
            event_reader.selector.close()
        return captured[-1]

    def test_ready_when_all_discovered_devices_are_readable(self):
        status = self.rescan_status(
            ["/dev/input/event0"],
            ["/dev/input/event0"],
        )
        self.assertEqual(status["state"], "ready")
        self.assertEqual(status["devices"], 1)

    def test_degraded_when_readable_and_denied_devices_coexist(self):
        status = self.rescan_status(
            ["/dev/input/event0"],
            ["/dev/input/event0", "/dev/input/event1"],
            denied=True,
        )
        self.assertEqual(status["state"], "degraded")
        self.assertEqual(status["devices"], 1)
        self.assertIn("1 unavailable", status["detail"])

    def test_permission_denied_when_no_devices_are_readable(self):
        status = self.rescan_status(
            [],
            ["/dev/input/event0"],
            denied=True,
        )
        self.assertEqual(status["state"], "permission-denied")
        self.assertEqual(status["devices"], 0)


class ErrorDetailTests(unittest.TestCase):
    def test_error_detail_is_bounded(self):
        detail = reader.error_detail(RuntimeError("x" * 10_000))
        self.assertLessEqual(len(detail), reader.MAX_ERROR_DETAIL_LENGTH)
        self.assertTrue(detail.startswith("Input reader failed: RuntimeError:"))


if __name__ == "__main__":
    unittest.main()
