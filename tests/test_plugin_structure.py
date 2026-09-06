#!/usr/bin/env python3

import json
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).parents[1]


class PluginStructureBaselineTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = json.loads((ROOT / "manifest.json").read_text())
        cls.overlay = (ROOT / "Overlay.qml").read_text()
        cls.key_stack = (ROOT / "KeyStack.qml").read_text()
        cls.bar_widget = (ROOT / "BarWidget.qml").read_text()

    def test_manifest_keeps_overlay_and_bar_widget_loaded(self):
        self.assertEqual(self.manifest["kinds"], ["overlay", "bar-widget"])
        self.assertTrue(self.manifest["keepLoaded"])
        self.assertEqual(
            self.manifest["entryPoints"],
            {"overlay": "Overlay.qml", "barWidget": "BarWidget.qml"},
        )

    def test_surface_is_persistent_full_screen_and_click_through(self):
        self.assertIn("model: Quickshell.screens", self.overlay)
        self.assertEqual(self.overlay.count("PanelWindow {"), 1)
        self.assertNotIn("Loader {", self.overlay)
        self.assertIn(
            "visible: root.captureEnabled && keyEntries.count > 0",
            self.overlay,
        )
        self.assertIn(
            "anchors { top: true; bottom: true; left: true; right: true }",
            self.overlay,
        )
        self.assertIn("exclusionMode: ExclusionMode.Ignore", self.overlay)
        self.assertIn("WlrLayershell.layer: WlrLayer.Overlay", self.overlay)
        self.assertIn(
            "WlrLayershell.keyboardFocus: WlrKeyboardFocus.None", self.overlay
        )
        self.assertIn("mask: Region {}", self.overlay)

    def test_key_stack_transition_timings_are_pinned(self):
        transition_patterns = (
            r'add:\s*Transition\s*\{\s*NumberAnimation\s*\{\s*properties:\s*"opacity";'
            r"\s*from:\s*0;\s*to:\s*1;\s*duration:\s*150;"
            r"\s*easing\.type:\s*Easing\.OutCubic\s*\}\s*\}",
            r'remove:\s*Transition\s*\{\s*NumberAnimation\s*\{\s*properties:\s*"opacity";'
            r"\s*to:\s*0;\s*duration:\s*160;"
            r"\s*easing\.type:\s*Easing\.OutCubic\s*\}\s*\}",
            r'displaced:\s*Transition\s*\{\s*NumberAnimation\s*\{\s*properties:\s*"y";'
            r"\s*duration:\s*150;\s*easing\.type:\s*Easing\.OutCubic\s*\}\s*\}",
        )
        for pattern in transition_patterns:
            with self.subTest(pattern=pattern):
                self.assertRegex(self.key_stack, pattern)

        self.assertIn("readonly property real fadeDuration: 350", self.key_stack)
        self.assertIn(
            "opacity: remaining >= root.fadeDuration ? 1 : remaining / root.fadeDuration",
            self.key_stack,
        )

    def test_key_stack_placement_and_keycap_style_are_pinned(self):
        self.assertIn(
            "verticalLayoutDirection: root.topPlacement ? "
            "ListView.TopToBottom : ListView.BottomToTop",
            self.key_stack,
        )
        self.assertIn(
            "anchors.leftMargin: root.leftPlacement ? root.outerMargin : 0",
            self.key_stack,
        )
        self.assertIn(
            "anchors.rightMargin: root.leftPlacement ? 0 : root.outerMargin",
            self.key_stack,
        )
        self.assertIn(
            "color: Util.alpha(Color.popups.background, 0.96)", self.key_stack
        )
        self.assertIn(
            "borderSpec: Border.flat(Color.popups.border, "
            "Math.max(1, Style.spaceReal(1) * root.scaleFactor))",
            self.key_stack,
        )
        self.assertIn("font.pixelSize: Style.font.subtitle * root.scaleFactor", self.key_stack)

    def test_reader_settings_entries_and_expiry_have_one_owner(self):
        self.assertEqual(self.overlay.count("ListModel { id: keyEntries }"), 1)
        self.assertEqual(self.overlay.count("id: readerProcess"), 1)
        self.assertEqual(self.overlay.count("id: settingsFile"), 1)
        self.assertEqual(self.overlay.count("id: settingsSaveTimer"), 1)
        self.assertEqual(
            self.overlay.count(
                "Number(keyEntries.get(i).expiresAt) <= root.nowMs"
            ),
            1,
        )
        self.assertNotIn("readerProcess", self.bar_widget)
        self.assertNotIn("keyEntries", self.bar_widget)

    def test_entry_lifetime_and_stack_limit_are_pinned(self):
        self.assertIn(
            "expiresAt: stamp + durationSeconds * 1000", self.overlay
        )
        self.assertIn(
            "while (keyEntries.count > stackLimit) "
            "keyEntries.remove(keyEntries.count - 1)",
            self.overlay,
        )
        self.assertRegex(
            self.overlay,
            re.compile(
                r"Timer\s*\{\s*interval:\s*50\s*repeat:\s*true\s*"
                r"running:\s*keyEntries\.count\s*>\s*0",
                re.MULTILINE,
            ),
        )


if __name__ == "__main__":
    unittest.main()
