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
        cls.service = (ROOT / "Service.qml").read_text()
        cls.key_stack = (ROOT / "KeyStack.qml").read_text()
        cls.bar_widget = (ROOT / "BarWidget.qml").read_text()

    def test_manifest_keeps_service_and_bar_widget_loaded(self):
        self.assertEqual(self.manifest["kinds"], ["service", "bar-widget"])
        self.assertTrue(self.manifest["keepLoaded"])
        self.assertEqual(
            self.manifest["entryPoints"],
            {"service": "Service.qml", "barWidget": "BarWidget.qml"},
        )
        self.assertFalse((ROOT / "Overlay.qml").exists())

    def test_service_has_no_overlay_lifecycle_bridge(self):
        self.assertIn("property var shell: null", self.service)
        self.assertNotIn("function barPopupWidget()", self.service)
        self.assertNotIn("readonly property bool opened:", self.service)
        self.assertNotIn("function open(", self.service)
        self.assertNotIn("function close(", self.service)

    def test_bar_widget_binds_to_service_controller_directly(self):
        self.assertIn(
            'typeof bar.shell.serviceFor === "function"', self.bar_widget
        )
        self.assertIn(
            "bar.shell.serviceFor(moduleName)", self.bar_widget
        )
        controller_bindings = (
            "controller.captureEnabled",
            "controller.position",
            "controller.scaleFactor",
            "controller.durationSeconds",
            "controller.stackLimit",
            "controller.readerStatus",
            "controller.readerDetail",
        )
        for binding in controller_bindings:
            with self.subTest(binding=binding):
                self.assertIn(binding, self.bar_widget)

        direct_calls = (
            "controller.setCaptureEnabled(!!value)",
            "controller.setPosition(value)",
            "controller.setScale(value)",
            "controller.setDuration(value)",
            "controller.setStackLimit(value)",
        )
        for call in direct_calls:
            with self.subTest(call=call):
                self.assertIn(call, self.bar_widget)

    def test_bar_widget_has_no_polling_or_shadow_state(self):
        obsolete_fragments = (
            "FileView {",
            "Process {",
            "id: stateProbe",
            "function send(",
            "function loadState(",
            "function loadSettings(",
            "function refreshState(",
            "Quickshell.execDetached",
            "omarchyShellPath",
            "configPath",
            "\n  property bool captureEnabled:",
            "\n  property string positionSetting:",
            "\n  property real scaleSetting:",
            "\n  property real durationSetting:",
            "\n  property int stackLimitSetting:",
            "\n  property string readerStatus:",
            "\n  property string readerDetail:",
        )
        for fragment in obsolete_fragments:
            with self.subTest(fragment=fragment):
                self.assertNotIn(fragment, self.bar_widget)

    def test_service_owns_one_persistent_surface_per_screen(self):
        self.assertEqual(self.service.count("Variants {"), 1)
        self.assertIn("model: Quickshell.screens", self.service)
        self.assertEqual(self.service.count("PanelWindow {"), 1)
        self.assertEqual(self.service.count("KeyStack {"), 1)
        self.assertNotIn("Loader {", self.service)
        self.assertNotIn("Component {", self.service)
        self.assertIn(
            "visible: root.captureEnabled && keyEntries.count > 0",
            self.service,
        )
        self.assertIn("entries: root.entries", self.service)
        self.assertIn("nowMs: root.nowMs", self.service)

    def test_surface_remains_passive_and_click_through(self):
        self.assertIn('color: "transparent"', self.service)
        self.assertIn("exclusionMode: ExclusionMode.Ignore", self.service)
        self.assertIn("WlrLayershell.layer: WlrLayer.Overlay", self.service)
        self.assertIn(
            "WlrLayershell.keyboardFocus: WlrKeyboardFocus.None", self.service
        )
        self.assertIn("mask: Region {}", self.service)

    def test_fullscreen_has_no_special_case_or_lifecycle_hook(self):
        production_qml = self.service + self.key_stack
        forbidden_fragments = (
            "fullscreen",
            "SUPER+F",
            '"SUPER", "F"',
            "onFullscreenChanged",
        )
        for fragment in forbidden_fragments:
            with self.subTest(fragment=fragment):
                self.assertNotIn(fragment, production_qml)

        self.assertEqual(
            self.service.count("WlrLayershell.layer: WlrLayer.Overlay"), 1
        )
        self.assertEqual(
            self.service.count(
                "visible: root.captureEnabled && keyEntries.count > 0"
            ),
            1,
        )

    def test_surface_uses_fixed_corner_geometry(self):
        geometry_fragments = (
            'readonly property real outerMargin: Style.spaceReal(42) * root.scaleFactor',
            'readonly property real rowWidthCap: Style.spaceReal(720) * root.scaleFactor',
            'modelData.width - outerMargin * 2',
            'modelData.height - outerMargin * 2',
            'readonly property real rowHeight: keyFontMetrics.height',
            'rowHeight * root.stackLimit',
            'stackSpacing * Math.max(0, root.stackLimit - 1)',
            'implicitWidth: Math.ceil(viewportWidth)',
            'implicitHeight: Math.ceil(viewportHeight)',
            'top: keyWindow.topPlacement',
            'bottom: !keyWindow.topPlacement',
            'left: keyWindow.leftPlacement',
            'right: !keyWindow.leftPlacement',
            'top: keyWindow.topPlacement ? keyWindow.outerMargin : 0',
            'bottom: keyWindow.topPlacement ? 0 : keyWindow.outerMargin',
            'left: keyWindow.leftPlacement ? keyWindow.outerMargin : 0',
            'right: keyWindow.leftPlacement ? 0 : keyWindow.outerMargin',
        )
        for fragment in geometry_fragments:
            with self.subTest(fragment=fragment):
                self.assertIn(fragment, self.service)

        self.assertNotIn(
            "anchors { top: true; bottom: true; left: true; right: true }",
            self.service,
        )

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
        self.assertIn("anchors.fill: parent", self.key_stack)
        self.assertIn("anchors.left: root.leftPlacement", self.key_stack)
        self.assertIn("anchors.right: root.leftPlacement", self.key_stack)
        self.assertIn(
            "color: Util.alpha(Color.popups.background, 0.96)", self.key_stack
        )
        self.assertIn(
            "borderSpec: Border.flat(Color.popups.border, "
            "Math.max(1, Style.spaceReal(1) * root.scaleFactor))",
            self.key_stack,
        )
        self.assertIn("font.pixelSize: Style.font.subtitle * root.scaleFactor", self.key_stack)

    def test_long_rows_are_bounded_inside_the_viewport(self):
        self.assertIn("clip: true", self.key_stack)
        self.assertIn(
            "readonly property real labelWidthCap: Style.spaceReal(240) * scaleFactor",
            self.key_stack,
        )
        self.assertIn(
            "width: Math.min(implicitWidth, keyRowSlot.maximumLabelWidth)",
            self.key_stack,
        )
        self.assertIn("elide: Text.ElideRight", self.key_stack)
        self.assertIn("function demoLong(): string", self.service)
        self.assertIn('"EXTRA-LONG-KEY-LABEL-EIGHT"', self.service)

    def test_reader_settings_entries_and_expiry_have_one_owner(self):
        self.assertEqual(self.service.count("ListModel { id: keyEntries }"), 1)
        self.assertEqual(self.service.count("id: readerProcess"), 1)
        self.assertEqual(self.service.count("id: settingsFile"), 1)
        self.assertEqual(self.service.count("id: settingsSaveTimer"), 1)
        self.assertEqual(
            self.service.count(
                "Number(keyEntries.get(i).expiresAt) <= root.nowMs"
            ),
            1,
        )
        self.assertNotIn("readerProcess", self.bar_widget)
        self.assertNotIn("keyEntries", self.bar_widget)

    def test_state_reports_service_identity_and_model_count(self):
        self.assertIn(
            "readonly property double serviceStartedAt: Date.now()", self.service
        )
        self.assertIn("serviceStartedAt: serviceStartedAt", self.service)
        self.assertIn("entryCount: keyEntries.count", self.service)

    def test_entry_lifetime_and_stack_limit_are_pinned(self):
        self.assertIn(
            "expiresAt: stamp + durationSeconds * 1000", self.service
        )
        self.assertIn(
            "while (keyEntries.count > stackLimit) "
            "keyEntries.remove(keyEntries.count - 1)",
            self.service,
        )
        self.assertRegex(
            self.service,
            re.compile(
                r"Timer\s*\{\s*interval:\s*50\s*repeat:\s*true\s*"
                r"running:\s*keyEntries\.count\s*>\s*0",
                re.MULTILINE,
            ),
        )


if __name__ == "__main__":
    unittest.main()
