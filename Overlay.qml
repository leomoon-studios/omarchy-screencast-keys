import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Item {
  id: root

  readonly property string pluginId: "leomoon-studios.omarchy-screencast-keys"
  readonly property string home: Quickshell.env("HOME")
  readonly property string configDir: home + "/.config/" + pluginId
  readonly property string configPath: configDir + "/settings.json"

  property var shell: null
  property var manifest: null
  readonly property string pluginDir: manifest && manifest.__sourceDir
    ? String(manifest.__sourceDir) : ""
  readonly property string readerPath: pluginDir === "" ? "" : pluginDir + "/scripts/key-reader.py"
  readonly property string accessHelperPath: pluginDir === "" ? "" : pluginDir + "/scripts/input-access.sh"

  property bool captureEnabled: true
  property string position: "bottom-right"
  property real scaleFactor: 1.0
  property string readerStatus: captureEnabled ? "starting" : "off"
  property string readerDetail: ""
  property bool directoryReady: false
  property bool settingsReady: false
  property bool hydrating: false
  property bool stoppingReader: false
  property double nowMs: Date.now()

  property alias entries: keyEntries
  ListModel { id: keyEntries }

  function validPosition(value) {
    var candidate = String(value || "")
    return candidate === "top-left" || candidate === "top-right"
      || candidate === "bottom-left" || candidate === "bottom-right"
  }

  function normalizedScale(value) {
    var number = Number(value)
    if (!isFinite(number)) number = 1.0
    return Math.max(0.6, Math.min(2.0, Math.round(number * 20) / 20))
  }

  function boolValue(value, fallback) {
    if (value === true || String(value).toLowerCase() === "true" || String(value) === "1") return true
    if (value === false || String(value).toLowerCase() === "false" || String(value) === "0") return false
    return fallback
  }

  function loadSettings(raw) {
    if (!directoryReady) return

    var parsed = null
    var text = String(raw || "").trim()
    if (text !== "") {
      try { parsed = JSON.parse(text) }
      catch (error) { console.warn(pluginId + ": settings parse failed; using defaults") }
    }

    hydrating = true
    captureEnabled = parsed && parsed.enabled !== undefined
      ? boolValue(parsed.enabled, true) : true
    position = parsed && validPosition(parsed.position)
      ? String(parsed.position) : "bottom-right"
    scaleFactor = parsed && parsed.scale !== undefined
      ? normalizedScale(parsed.scale) : 1.0
    hydrating = false
    settingsReady = true

    if (!parsed || parsed.version !== 1) scheduleSave()
    reconcileReader()
  }

  function scheduleSave() {
    if (!settingsReady || hydrating) return
    settingsSaveTimer.restart()
  }

  function saveSettings() {
    var payload = {
      version: 1,
      enabled: captureEnabled,
      position: position,
      scale: scaleFactor
    }
    settingsFile.setText(JSON.stringify(payload, null, 2) + "\n")
  }

  function setCaptureEnabled(value) {
    var next = boolValue(value, captureEnabled)
    if (captureEnabled === next) return
    captureEnabled = next
    scheduleSave()
    reconcileReader()
  }

  function setPosition(value) {
    if (!validPosition(value) || position === String(value)) return
    position = String(value)
    scheduleSave()
  }

  function setScale(value) {
    var next = normalizedScale(value)
    if (Math.abs(scaleFactor - next) < 0.001) return
    scaleFactor = next
    scheduleSave()
  }

  function clearEntries() {
    keyEntries.clear()
  }

  function addKeys(keys) {
    if (!captureEnabled || !Array.isArray(keys) || keys.length === 0) return

    var clean = []
    for (var i = 0; i < keys.length; i++) {
      var label = String(keys[i] || "").trim()
      if (label !== "") clean.push(label)
    }
    if (clean.length === 0) return

    var stamp = Date.now()
    keyEntries.insert(0, {
      // ListModel turns array-valued roles into nested item models. Passing
      // that role to a second Repeater exposes QQmlDMAbstractItemModelData
      // wrappers instead of strings. Keep the role scalar and split it only
      // in the visual delegate.
      keyText: clean.join("\u001f"),
      createdAt: stamp,
      expiresAt: stamp + 2000
    })
    while (keyEntries.count > 7) keyEntries.remove(keyEntries.count - 1)
  }

  function handleReaderLine(rawLine) {
    var line = String(rawLine || "").trim()
    if (line === "") return

    try {
      var message = JSON.parse(line)
      if (message.type === "key") {
        addKeys(message.keys)
      } else if (message.type === "status") {
        readerStatus = String(message.state || "error")
        readerDetail = String(message.detail || "")
      }
    } catch (error) {
      readerStatus = "error"
      readerDetail = "Invalid input-reader response"
    }
  }

  function reconcileReader() {
    if (!settingsReady || pluginDir === "") return

    if (!captureEnabled) {
      restartTimer.stop()
      stoppingReader = readerProcess.running
      readerProcess.running = false
      readerStatus = "off"
      readerDetail = ""
      clearEntries()
      return
    }

    stoppingReader = false
    if (!readerProcess.running) {
      readerStatus = "starting"
      readerDetail = ""
      readerProcess.command = ["python3", readerPath]
      readerProcess.running = true
    }
  }

  function requestInputAccess() {
    if (accessHelperPath === "") return
    Quickshell.execDetached(["pkexec", accessHelperPath, "install"])
  }

  function stateObject() {
    return {
      enabled: captureEnabled,
      position: position,
      scale: scaleFactor,
      readerStatus: readerStatus,
      readerDetail: readerDetail
    }
  }

  onPluginDirChanged: reconcileReader()

  Process {
    id: ensureConfigDir
    command: ["mkdir", "-p", root.configDir]
    running: true
    onExited: function(exitCode) {
      root.directoryReady = exitCode === 0
      if (root.directoryReady) settingsFile.reload()
      else {
        root.readerStatus = "error"
        root.readerDetail = "Could not create the configuration directory"
      }
    }
  }

  FileView {
    id: settingsFile
    path: root.configPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadSettings(text())
    onLoadFailed: root.loadSettings("")
    onFileChanged: reload()
  }

  Timer {
    id: settingsSaveTimer
    interval: 150
    repeat: false
    onTriggered: root.saveSettings()
  }

  Process {
    id: readerProcess
    stdout: SplitParser {
      onRead: function(line) { root.handleReaderLine(line) }
    }
    stderr: SplitParser {
      onRead: function(line) {
        var detail = String(line || "").trim()
        if (detail !== "") root.readerDetail = detail
      }
    }
    onExited: function(exitCode) {
      if (root.stoppingReader || !root.captureEnabled) {
        root.stoppingReader = false
        root.readerStatus = "off"
        return
      }
      root.readerStatus = "error"
      root.readerDetail = "Input reader exited (" + exitCode + ")"
      restartTimer.restart()
    }
  }

  Timer {
    id: restartTimer
    interval: 2000
    repeat: false
    onTriggered: root.reconcileReader()
  }

  Timer {
    interval: 50
    repeat: true
    running: keyEntries.count > 0
    onTriggered: {
      root.nowMs = Date.now()
      for (var i = keyEntries.count - 1; i >= 0; i--) {
        if (Number(keyEntries.get(i).expiresAt) <= root.nowMs)
          keyEntries.remove(i)
      }
    }
  }

  IpcHandler {
    target: root.pluginId

    function state(): string {
      return JSON.stringify(root.stateObject())
    }

    function setEnabled(value: string): string {
      root.setCaptureEnabled(value)
      return JSON.stringify(root.stateObject())
    }

    function toggle(): string {
      root.setCaptureEnabled(!root.captureEnabled)
      return JSON.stringify(root.stateObject())
    }

    function setPosition(value: string): string {
      root.setPosition(value)
      return JSON.stringify(root.stateObject())
    }

    function setScale(value: string): string {
      root.setScale(value)
      return JSON.stringify(root.stateObject())
    }

    function reload(): string {
      settingsFile.reload()
      return "ok"
    }

    function grantInputAccess(): string {
      root.requestInputAccess()
      return "requested"
    }

    function demo(): string {
      root.addKeys(["SUPER", "L"])
      root.addKeys(["CTRL", "SHIFT", "P"])
      root.addKeys(["SPACE"])
      return "ok"
    }
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      required property var modelData
      screen: modelData
      visible: root.captureEnabled && keyEntries.count > 0
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "leomoon-screencast-keys"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      mask: Region {}

      KeyStack {
        anchors.fill: parent
        entries: root.entries
        position: root.position
        scaleFactor: root.scaleFactor
        nowMs: root.nowMs
      }
    }
  }
}
