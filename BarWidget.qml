import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui

BarWidget {
  id: root

  moduleName: "leomoon-studios.omarchy-screencast-keys"

  readonly property var controller: bar && bar.shell
    && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor(moduleName) : null

  property bool opened: false
  property bool popoutSwitchClosing: false
  readonly property bool captureEnabled: controller
    ? controller.captureEnabled === true : false
  readonly property bool hotkeysOnlySetting: controller
    ? controller.hotkeysOnly === true : false
  readonly property string monitorTargetSetting: controller
    ? String(controller.monitorTarget) : "all"
  readonly property string positionSetting: controller
    ? String(controller.position) : "bottom-right"
  readonly property real scaleSetting: controller
    ? Number(controller.scaleFactor) : 1.0
  readonly property real durationSetting: controller
    ? Number(controller.durationSeconds) : 3.0
  readonly property int stackLimitSetting: controller
    ? Number(controller.stackLimit) : 7
  readonly property string readerStatus: controller
    ? String(controller.readerStatus) : "off"
  readonly property string readerDetail: controller
    ? String(controller.readerDetail) : ""

  property real previewScale: 1.0
  property real previewDuration: 3.0
  property int previewStackLimit: 7
  property bool scaleCommitPending: false
  property bool durationCommitPending: false
  property bool stackCommitPending: false
  property var monitorOptions: []

  readonly property string effectiveMonitorTarget: {
    if (monitorTargetSetting === "all") return "all"
    return monitorOptions.indexOf(monitorTargetSetting) !== -1
      ? monitorTargetSetting : "all"
  }

  Binding {
    target: root
    property: "previewScale"
    value: root.scaleSetting
    when: !sizeSlider.dragging && !root.scaleCommitPending
    restoreMode: Binding.RestoreNone
  }

  Binding {
    target: root
    property: "previewDuration"
    value: root.durationSetting
    when: !durationSlider.dragging && !root.durationCommitPending
    restoreMode: Binding.RestoreNone
  }

  Binding {
    target: root
    property: "previewStackLimit"
    value: root.stackLimitSetting
    when: !stackSlider.dragging && !root.stackCommitPending
    restoreMode: Binding.RestoreNone
  }

  readonly property string statusLabel: {
    if (!captureEnabled || readerStatus === "off") return "Off"
    if (readerStatus === "ready") return "On"
    if (readerStatus === "degraded") return "On with partial input access"
    if (readerStatus === "permission-denied") return "Global input access unavailable"
    if (readerStatus === "no-inputs" || readerStatus === "no-keyboards") return "No input device found"
    if (readerStatus === "starting") return "Starting…"
    return "Reader error"
  }

  function open() {
    opened = true
  }

  function close() { opened = false }
  function toggle() { opened ? close() : open() }

  function closeForPopoutSwitch() {
    popoutSwitchClosing = true
    close()
    Qt.callLater(function() { root.popoutSwitchClosing = false })
  }

  function setEnabled(value) {
    if (controller && typeof controller.setCaptureEnabled === "function")
      controller.setCaptureEnabled(!!value)
  }

  function setHotkeysOnly(value) {
    if (controller && typeof controller.setHotkeysOnly === "function")
      controller.setHotkeysOnly(!!value)
  }

  function refreshMonitors() {
    if (controller && typeof controller.monitorNames === "function")
      monitorOptions = controller.monitorNames()
    else {
      var names = []
      for (var i = 0; i < Quickshell.screens.length; i++)
        names.push(String(Quickshell.screens[i].name || ""))
      monitorOptions = names
    }
  }

  function setMonitorTarget(value) {
    if (controller && typeof controller.setMonitorTarget === "function")
      controller.setMonitorTarget(value)
  }

  function setPosition(value) {
    if (controller && typeof controller.setPosition === "function")
      controller.setPosition(value)
  }

  function setScale(value) {
    if (controller && typeof controller.setScale === "function")
      controller.setScale(value)
  }

  function setDuration(value) {
    if (controller && typeof controller.setDuration === "function")
      controller.setDuration(value)
  }

  function setStackLimit(value) {
    if (controller && typeof controller.setStackLimit === "function")
      controller.setStackLimit(value)
  }

  onOpenedChanged: if (opened) refreshMonitors()

  implicitWidth: iconButton.implicitWidth
  implicitHeight: iconButton.implicitHeight

  WidgetButton {
    id: iconButton
    anchors.fill: parent
    bar: root.bar
    text: " "
    labelVisible: false
    // Keep the badge inside the same fixed horizontal slot as ordinary bar
    // icons. The content-width fallback made text badges sit closer together
    // than OpticalGlyph-based widgets.
    fixedWidth: iconButton.vertical ? -1 : Math.max(
      Style.bar.iconSlot, iconBadge.width + Style.space(4))
    active: root.captureEnabled
    activeColor: Color.urgent
    dimmed: !root.captureEnabled
    tooltipText: "Screencast keys: " + root.statusLabel

    Rectangle {
      id: iconBadge
      anchors.centerIn: parent
      width: iconBadgeText.implicitWidth + Style.space(4)
      height: Math.max(Style.space(12), iconBadgeText.font.pixelSize + Style.space(3))
      color: "transparent"
      border.width: Math.max(1, Style.normalBorderWidth)
      border.color: iconButton.active && iconButton.useActiveColor
        ? iconButton.activeColor : iconButton.foreground
      radius: Style.cornerRadius

      Text {
        id: iconBadgeText
        anchors.centerIn: parent
        text: "SCK"
        color: iconButton.active && iconButton.useActiveColor
          ? iconButton.activeColor : iconButton.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Math.max(Style.space(6), Math.round(Style.font.caption * 0.62))
        renderType: Text.NativeRendering
      }
    }

    onPressed: function(button) {
      if (button === Qt.RightButton) root.setEnabled(!root.captureEnabled)
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: popup
    anchorItem: iconButton
    bar: root.bar
    owner: root
    open: root.opened
    contentWidth: Style.space(380)
    contentHeight: settingsColumn.implicitHeight + padding * 2

    Column {
      id: settingsColumn
      width: parent.width
      spacing: Style.space(14)

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: "Screencast Keys"
        color: root.bar ? root.bar.foreground : Color.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.heading
        font.bold: true
      }

      Toggle {
        width: parent.width
        label: "Show pressed keys"
        description: "Stops global keyboard and mouse capture when switched off"
        checked: root.captureEnabled
        foreground: root.bar ? root.bar.foreground : Color.foreground
        accent: Color.accent
        fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
        onClicked: root.setEnabled(!root.captureEnabled)
      }

      Toggle {
        width: parent.width
        label: "Hotkeys only"
        description: "Hide single keys and buttons; keep keyboard and mouse combinations"
        checked: root.hotkeysOnlySetting
        foreground: root.bar ? root.bar.foreground : Color.foreground
        accent: Color.accent
        fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
        onClicked: root.setHotkeysOnly(!root.hotkeysOnlySetting)
      }

      Rectangle {
        visible: root.monitorOptions.length > 1
        width: parent.width
        height: visible ? 1 : 0
        color: Util.alpha(root.bar ? root.bar.foreground : Color.foreground, 0.16)
      }

      Column {
        visible: root.monitorOptions.length > 1
        width: parent.width
        spacing: Style.space(8)

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: "MONITOR"
          color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.45)
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        Button {
          width: parent.width
          text: "All monitors"
          selected: root.effectiveMonitorTarget === "all"
          onClicked: root.setMonitorTarget("all")
        }

        GridLayout {
          width: parent.width
          columns: 2
          columnSpacing: Style.space(8)
          rowSpacing: Style.space(8)

          Repeater {
            model: root.monitorOptions

            Button {
              required property string modelData
              Layout.fillWidth: true
              text: modelData
              selected: root.effectiveMonitorTarget === modelData
              onClicked: root.setMonitorTarget(modelData)
            }
          }
        }
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: "POSITION"
        color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.45)
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
      }

      GridLayout {
        width: parent.width
        columns: 2
        columnSpacing: Style.space(8)
        rowSpacing: Style.space(8)

        Button {
          Layout.fillWidth: true
          text: "Top left"
          selected: root.positionSetting === "top-left"
          onClicked: root.setPosition("top-left")
        }
        Button {
          Layout.fillWidth: true
          text: "Top right"
          selected: root.positionSetting === "top-right"
          onClicked: root.setPosition("top-right")
        }
        Button {
          Layout.fillWidth: true
          text: "Bottom left"
          selected: root.positionSetting === "bottom-left"
          onClicked: root.setPosition("bottom-left")
        }
        Button {
          Layout.fillWidth: true
          text: "Bottom right"
          selected: root.positionSetting === "bottom-right"
          onClicked: root.setPosition("bottom-right")
        }
      }

      GridLayout {
        width: parent.width
        columns: 3
        columnSpacing: Style.space(12)
        rowSpacing: Style.space(10)

        Text {
          Layout.preferredWidth: Style.space(70)
          Layout.alignment: Qt.AlignVCenter
          textFormat: Text.PlainText
          text: "SIZE"
          color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.45)
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        PanelSlider {
          id: sizeSlider
          Layout.fillWidth: true
          Layout.alignment: Qt.AlignVCenter
          bar: root.bar
          minimum: 0.6
          maximum: 2.0
          step: 0.05
          value: root.previewScale
          onMoved: function(value) {
            root.scaleCommitPending = true
            root.previewScale = value
          }
          onReleased: function(value) {
            root.setScale(value)
            root.scaleCommitPending = false
          }
        }

        Text {
          Layout.preferredWidth: Style.space(40)
          Layout.alignment: Qt.AlignVCenter
          horizontalAlignment: Text.AlignRight
          textFormat: Text.PlainText
          text: Math.round(root.previewScale * 100) + "%"
          color: root.bar ? root.bar.foreground : Color.foreground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.body
        }

        Text {
          Layout.preferredWidth: Style.space(70)
          Layout.alignment: Qt.AlignVCenter
          textFormat: Text.PlainText
          text: "DURATION"
          color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.45)
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        PanelSlider {
          id: durationSlider
          Layout.fillWidth: true
          Layout.alignment: Qt.AlignVCenter
          bar: root.bar
          minimum: 1.0
          maximum: 10.0
          step: 0.5
          value: root.previewDuration
          onMoved: function(value) {
            root.durationCommitPending = true
            root.previewDuration = value
          }
          onReleased: function(value) {
            root.setDuration(value)
            root.durationCommitPending = false
          }
        }

        Text {
          Layout.preferredWidth: Style.space(40)
          Layout.alignment: Qt.AlignVCenter
          horizontalAlignment: Text.AlignRight
          textFormat: Text.PlainText
          text: root.previewDuration.toFixed(1) + "s"
          color: root.bar ? root.bar.foreground : Color.foreground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.body
        }

        Text {
          Layout.preferredWidth: Style.space(70)
          Layout.alignment: Qt.AlignVCenter
          textFormat: Text.PlainText
          text: "VISIBLE KEYS"
          color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.45)
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        PanelSlider {
          id: stackSlider
          Layout.fillWidth: true
          Layout.alignment: Qt.AlignVCenter
          bar: root.bar
          minimum: 1
          maximum: 15
          step: 1
          value: root.previewStackLimit
          onMoved: function(value) {
            root.stackCommitPending = true
            root.previewStackLimit = Math.round(value)
          }
          onReleased: function(value) {
            root.setStackLimit(value)
            root.stackCommitPending = false
          }
        }

        Text {
          Layout.preferredWidth: Style.space(40)
          Layout.alignment: Qt.AlignVCenter
          horizontalAlignment: Text.AlignRight
          textFormat: Text.PlainText
          text: root.previewStackLimit.toString()
          color: root.bar ? root.bar.foreground : Color.foreground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.body
        }
      }

      Rectangle {
        width: parent.width
        height: 1
        color: Util.alpha(root.bar ? root.bar.foreground : Color.foreground, 0.16)
      }

      Row {
        width: parent.width
        spacing: Style.space(10)

        Text {
          width: parent.width
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: root.readerDetail !== "" && root.readerStatus !== "ready"
            ? root.statusLabel + " — " + root.readerDetail : root.statusLabel
          color: root.readerStatus === "permission-denied" || root.readerStatus === "degraded"
            ? Color.urgent
            : Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.35)
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

      }

      Text {
        visible: root.captureEnabled
        width: parent.width
        textFormat: Text.PlainText
        text: "Keys and mouse buttons are observed globally, including in password fields. Turn this off when you are not recording."
        color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.55)
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }
    }
  }
}
