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
    ? String(manifest.__sourceDir)
    : String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/$/, "")
  readonly property string readerPath: pluginDir === "" ? "" : pluginDir + "/scripts/key-reader.py"
  readonly property string pythonPath: "/usr/bin/python3"
  readonly property string mkdirPath: "/usr/bin/mkdir"
  readonly property int maxChordKeys: 8
  readonly property int maxLabelLength: 48
  readonly property int maxReaderLineLength: 4096
  readonly property int maxRestartAttempts: 5

  property bool captureEnabled: false
  property string position: "bottom-right"
  property real scaleFactor: 1.0
  property real durationSeconds: 3.0
  property int stackLimit: 7
  property string readerStatus: captureEnabled ? "starting" : "off"
  property string readerDetail: ""
  property bool directoryReady: false
  property bool settingsReady: false
  property bool hydrating: false
  property bool stoppingReader: false
  property bool restartPending: false
  property bool restartBlocked: false
  property int restartAttempts: 0
  property double nowMs: Date.now()

  property alias entries: keyEntries
  ListModel { id: keyEntries }

  // Plugins that declare both overlay and bar-widget kinds are summoned
  // through their overlay entry point. Bridge that shell-level lifecycle back
  // to the visible bar popup so SUPER+CTRL+<number> behaves like an icon click.
  function barPopupWidget() {
    return shell && shell.bar && typeof shell.bar.findPanelWidget === "function"
      ? shell.bar.findPanelWidget(pluginId) : null
  }

  readonly property bool opened: {
    var widget = barPopupWidget()
    return widget ? widget.opened === true : false
  }

  function open(payloadJson) {
    var widget = barPopupWidget()
    if (widget && typeof widget.open === "function") widget.open()
  }

  function close() {
    var widget = barPopupWidget()
    if (widget && typeof widget.close === "function") widget.close()
  }

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

  function normalizedDuration(value) {
    var number = Number(value)
    if (!isFinite(number)) number = 3.0
    return Math.max(1.0, Math.min(10.0, Math.round(number * 2) / 2))
  }

  function normalizedStackLimit(value) {
    var number = Number(value)
    if (!isFinite(number)) number = 7
    return Math.max(1, Math.min(15, Math.round(number)))
  }

  function boolValue(value, fallback) {
    if (value === true || String(value).toLowerCase() === "true" || String(value) === "1") return true
    if (value === false || String(value).toLowerCase() === "false" || String(value) === "0") return false
    return fallback
  }

  function loadSettings(raw) {
    var parsed = null
    var text = String(raw || "").trim()
    if (text !== "") {
      try { parsed = JSON.parse(text) }
      catch (error) { console.warn(pluginId + ": settings parse failed; using defaults") }
    }

    hydrating = true
    // Settings are security-sensitive: only a literal JSON boolean true may
    // enable global capture. Missing, malformed, and loosely typed values fail
    // closed. IPC still uses boolValue() for its string arguments.
    captureEnabled = !!(parsed && parsed.enabled === true)
    position = parsed && validPosition(parsed.position)
      ? String(parsed.position) : "bottom-right"
    scaleFactor = parsed && parsed.scale !== undefined
      ? normalizedScale(parsed.scale) : 1.0
    durationSeconds = parsed && parsed.duration !== undefined
      ? normalizedDuration(parsed.duration) : 3.0
    stackLimit = parsed && parsed.stackLimit !== undefined
      ? normalizedStackLimit(parsed.stackLimit) : 7
    hydrating = false
    settingsReady = true

    if (!parsed || parsed.version !== 1 || parsed.duration === undefined
        || parsed.stackLimit === undefined) scheduleSave()
    reconcileReader()
  }

  function scheduleSave() {
    if (!settingsReady || !directoryReady || hydrating) return
    settingsSaveTimer.restart()
  }

  function saveSettings() {
    var payload = {
      version: 1,
      enabled: captureEnabled,
      position: position,
      scale: scaleFactor,
      duration: durationSeconds,
      stackLimit: stackLimit
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

  function setDuration(value) {
    var next = normalizedDuration(value)
    if (Math.abs(durationSeconds - next) < 0.001) return
    durationSeconds = next
    scheduleSave()
  }

  function setStackLimit(value) {
    var next = normalizedStackLimit(value)
    if (stackLimit === next) return
    stackLimit = next
    while (keyEntries.count > stackLimit) keyEntries.remove(keyEntries.count - 1)
    scheduleSave()
  }

  function clearEntries() {
    keyEntries.clear()
  }

  function addKeys(keys) {
    if (!captureEnabled || !Array.isArray(keys) || keys.length === 0) return

    var clean = []
    for (var i = 0; i < Math.min(keys.length, maxChordKeys); i++) {
      var label = String(keys[i] || "").trim().slice(0, maxLabelLength)
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
      expiresAt: stamp + durationSeconds * 1000
    })
    while (keyEntries.count > stackLimit) keyEntries.remove(keyEntries.count - 1)
  }

  function handleReaderLine(rawLine) {
    var line = String(rawLine || "").trim()
    if (line === "") return
    if (line.length > maxReaderLineLength) {
      readerStatus = "error"
      readerDetail = "Oversized input-reader response"
      return
    }

    try {
      var message = JSON.parse(line)
      if (message.type === "key") {
        addKeys(message.keys)
      } else if (message.type === "status") {
        var state = String(message.state || "error")
        var allowed = ["ready", "permission-denied", "no-inputs", "error"]
        readerStatus = allowed.indexOf(state) !== -1 ? state : "error"
        readerDetail = String(message.detail || "").slice(0, 256)
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
      readerStabilityTimer.stop()
      restartPending = false
      restartBlocked = false
      restartAttempts = 0
      stoppingReader = readerProcess.running
      readerProcess.running = false
      readerStatus = "off"
      readerDetail = ""
      clearEntries()
      return
    }

    if (restartPending || restartBlocked) return

    stoppingReader = false
    if (!readerProcess.running) {
      readerStatus = "starting"
      readerDetail = ""
      readerProcess.command = [pythonPath, "-I", readerPath]
      readerProcess.running = true
      readerStabilityTimer.restart()
    }
  }

  function scheduleReaderRestart(exitCode) {
    if (restartAttempts >= maxRestartAttempts) {
      restartPending = false
      restartBlocked = true
      readerStatus = "error"
      readerDetail = "Input reader stopped after repeated failures"
      return
    }

    restartAttempts += 1
    restartPending = true
    var delay = Math.min(30000, 500 * Math.pow(2, restartAttempts - 1))
    restartTimer.interval = delay
    readerStatus = "error"
    readerDetail = "Input reader exited (" + exitCode + "); retrying in "
      + (delay / 1000).toFixed(1) + "s"
    restartTimer.restart()
  }

  function stateObject() {
    return {
      enabled: captureEnabled,
      position: position,
      scale: scaleFactor,
      duration: durationSeconds,
      stackLimit: stackLimit,
      readerStatus: readerStatus,
      readerDetail: readerDetail
    }
  }

  onPluginDirChanged: reconcileReader()

  Component.onCompleted: {
    // FileView and manifest injection can complete in either order. Loading
    // once here, in addition to the post-mkdir reload, makes startup robust
    // for both fresh installs and already-configured plugins.
    settingsFile.reload()
  }

  Process {
    id: ensureConfigDir
    command: [root.mkdirPath, "-p", root.configDir]
    running: true
    onExited: function(exitCode) {
      root.directoryReady = exitCode === 0
      if (root.directoryReady) {
        settingsFile.reload()
        if (root.settingsReady) {
          root.scheduleSave()
          root.reconcileReader()
        }
      }
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
        var raw = String(line || "")
        if (raw.length > root.maxReaderLineLength) {
          root.readerStatus = "error"
          root.readerDetail = "Oversized input-reader error"
          return
        }
        var detail = raw.trim().slice(0, 256)
        if (detail !== "") root.readerDetail = detail
      }
    }
    onExited: function(exitCode) {
      readerStabilityTimer.stop()
      if (root.stoppingReader || !root.captureEnabled) {
        root.stoppingReader = false
        root.readerStatus = "off"
        return
      }
      root.readerStatus = "error"
      root.scheduleReaderRestart(exitCode)
    }
  }

  Timer {
    id: restartTimer
    interval: 500
    repeat: false
    onTriggered: {
      root.restartPending = false
      root.reconcileReader()
    }
  }

  Timer {
    id: readerStabilityTimer
    interval: 30000
    repeat: false
    onTriggered: {
      if (readerProcess.running) root.restartAttempts = 0
    }
  }

  Timer {
    // One post-construction reconciliation covers FileView and manifest
    // ordering without creating an unbounded process restart loop.
    interval: 500
    repeat: false
    running: true
    onTriggered: {
      if (!root.settingsReady) settingsFile.reload()
      root.reconcileReader()
    }
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

    function setDuration(value: string): string {
      root.setDuration(value)
      return JSON.stringify(root.stateObject())
    }

    function setStackLimit(value: string): string {
      root.setStackLimit(value)
      return JSON.stringify(root.stateObject())
    }

    function reload(): string {
      settingsFile.reload()
      return "ok"
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
