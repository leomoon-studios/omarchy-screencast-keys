import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root

  moduleName: "leomoon-studios.omarchy-screencast-keys"

  readonly property string pluginId: moduleName
  readonly property string home: Quickshell.env("HOME")
  readonly property string configPath: home + "/.config/" + pluginId + "/settings.json"

  property bool opened: false
  property bool popoutSwitchClosing: false
  property bool captureEnabled: true
  property string positionSetting: "bottom-right"
  property real scaleSetting: 1.0
  property real previewScale: scaleSetting
  property real durationSetting: 3.0
  property real previewDuration: durationSetting
  property string readerStatus: "starting"
  property string readerDetail: ""

  readonly property bool accessProblem: readerStatus === "permission-denied"
  readonly property string statusLabel: {
    if (!captureEnabled || readerStatus === "off") return "Off"
    if (readerStatus === "ready") return "On"
    if (readerStatus === "permission-denied") return "Input access required"
    if (readerStatus === "no-inputs" || readerStatus === "no-keyboards") return "No input device found"
    if (readerStatus === "starting") return "Starting…"
    return "Reader error"
  }

  function open() {
    opened = true
    refreshState()
    configFile.reload()
  }

  function close() { opened = false }
  function toggle() { opened ? close() : open() }

  function closeForPopoutSwitch() {
    popoutSwitchClosing = true
    close()
    Qt.callLater(function() { root.popoutSwitchClosing = false })
  }

  function send(method, value) {
    var command = ["omarchy-shell", "-q", pluginId, method]
    if (value !== undefined) command.push(String(value))
    Quickshell.execDetached(command)
  }

  function setEnabled(value) {
    captureEnabled = !!value
    readerStatus = captureEnabled ? "starting" : "off"
    send("setEnabled", captureEnabled ? "true" : "false")
  }

  function setPosition(value) {
    positionSetting = value
    send("setPosition", value)
  }

  function setScale(value) {
    var next = Math.max(0.6, Math.min(2.0, Math.round(Number(value) * 20) / 20))
    scaleSetting = next
    previewScale = next
    send("setScale", next)
  }

  function setDuration(value) {
    var next = Math.max(1.0, Math.min(10.0, Math.round(Number(value) * 2) / 2))
    durationSetting = next
    previewDuration = next
    send("setDuration", next)
  }

  function loadState(raw) {
    var text = String(raw || "").trim()
    if (text === "") return
    try {
      var state = JSON.parse(text)
      if (state.enabled !== undefined) captureEnabled = !!state.enabled
      if (state.position) positionSetting = String(state.position)
      if (state.scale !== undefined) {
        scaleSetting = Number(state.scale)
        if (!sizeSlider.dragging) previewScale = scaleSetting
      }
      if (state.duration !== undefined) {
        durationSetting = Number(state.duration)
        if (!durationSlider.dragging) previewDuration = durationSetting
      }
      readerStatus = String(state.readerStatus || readerStatus)
      readerDetail = String(state.readerDetail || "")
    } catch (error) {}
  }

  function loadSettings(raw) {
    var text = String(raw || "").trim()
    if (text === "") return
    try {
      var settings = JSON.parse(text)
      if (settings.enabled !== undefined) captureEnabled = !!settings.enabled
      if (settings.position) positionSetting = String(settings.position)
      if (settings.scale !== undefined) {
        scaleSetting = Number(settings.scale)
        if (!sizeSlider.dragging) previewScale = scaleSetting
      }
      if (settings.duration !== undefined) {
        durationSetting = Number(settings.duration)
        if (!durationSlider.dragging) previewDuration = durationSetting
      }
    } catch (error) {}
  }

  function refreshState() {
    if (!stateProbe.running) stateProbe.running = true
  }

  implicitWidth: iconButton.implicitWidth
  implicitHeight: iconButton.implicitHeight

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    printErrors: false
    onLoaded: root.loadSettings(text())
    onFileChanged: reload()
  }

  Process {
    id: stateProbe
    // The state call must not use -q: quiet mode deliberately suppresses the
    // JSON response, which would leave this widget displaying "Starting…".
    command: ["omarchy-shell", root.pluginId, "state"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.loadState(text)
    }
  }

  Timer {
    interval: root.opened ? 1000 : 5000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refreshState()
  }

  WidgetButton {
    id: iconButton
    anchors.fill: parent
    bar: root.bar
    text: " "
    labelVisible: false
    fixedWidth: iconBadge.width + Style.space(4)
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
        description: "Stops global key capture when switched off"
        checked: root.captureEnabled
        foreground: root.bar ? root.bar.foreground : Color.foreground
        accent: Color.accent
        fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
        onClicked: root.setEnabled(!root.captureEnabled)
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
          onMoved: function(value) { root.previewScale = value }
          onReleased: function(value) { root.setScale(value) }
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
          onMoved: function(value) { root.previewDuration = value }
          onReleased: function(value) { root.setDuration(value) }
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
          width: parent.width - (grantButton.visible ? grantButton.width + parent.spacing : 0)
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: root.readerDetail !== "" && root.readerStatus !== "ready"
            ? root.statusLabel + " — " + root.readerDetail : root.statusLabel
          color: root.accessProblem ? Color.urgent
            : Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.35)
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Button {
          id: grantButton
          visible: root.accessProblem
          anchors.verticalCenter: parent.verticalCenter
          text: "Grant input access"
          onClicked: root.send("grantInputAccess")
        }
      }

      Text {
        visible: root.captureEnabled
        width: parent.width
        textFormat: Text.PlainText
        text: "Keys are observed globally, including in password fields. Turn this off when you are not recording."
        color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.55)
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }
    }
  }
}
