import QtQuick
import QtQuick.Layouts
import QtCore
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import "Game.js" as Game
import "SettingsNavigation.js" as SettingsNavigation

Item {
  id: root

  property var shell: null
  property bool closingFromHost: false
  property var game: null
  property int revision: 0
  property string view: "menu"
  property string blockStyle: "solid"
  property bool leftHeld: false
  property bool rightHeld: false
  property bool downHeld: false
  property int horizontalDirection: 0
  property bool rotateLeftHeld: false
  property bool rotateRightHeld: false
  property int rotationDirection: 0
  property bool overlayActive: false
  property var overlayTarget: null
  property string overlayTargetAddress: ""
  property var overlayCandidates: []
  property string overlayNotice: ""
  property int overlayPickerIndex: 0
  property int menuIndex: 0
  property int resultIndex: 0
  property int settingsFocus: 0
  property string editingVolume: ""
  property string rebindingAction: ""
  property int rebindingSlot: 0
  property string settingsNotice: ""
  property bool capturingGlobalHotkey: false
  property string globalHotkey: ""
  property string hotkeyOperation: ""
  property bool hotkeyBusy: false
  property bool hotkeyError: false
  property bool hotkeyCaptureRequested: false
  readonly property int minimumUsableWidth: 600
  readonly property int minimumUsableHeight: 440
  readonly property bool windowTooSmall: window.visible
      && (window.width < minimumUsableWidth || window.height < minimumUsableHeight)

  onSettingsFocusChanged: {
    if ((capturingGlobalHotkey || hotkeyCaptureRequested)
        && settingsFocus !== SettingsNavigation.hotkeyFocus(controlDefinitions().length))
      stopGlobalHotkeyCapture("Global shortcut unchanged")
    else if (!capturingGlobalHotkey
             && settingsFocus !== SettingsNavigation.hotkeyFocus(controlDefinitions().length))
      hotkeyError = false
  }

  onWindowTooSmallChanged: {
    if (windowTooSmall) {
      resetHeldInputs()
      stopGlobalHotkeyCapture("")
    } else if (window.visible) {
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    }
  }

  Settings {
    id: highScores
    location: StandardPaths.writableLocation(StandardPaths.GenericConfigLocation) + "/omatris.ini"
    category: "highScores"
    property int classic: 0
    property int endless: 0
    property int overlay: 0
  }

  Process {
    id: hotkeyProcess
    running: false

    stdout: StdioCollector {
      id: hotkeyStdout
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: hotkeyStderr
      waitForEnd: true
    }
    onExited: function(exitCode) {
      root.handleHotkeyResult(exitCode, hotkeyStdout.text, hotkeyStderr.text)
    }
  }

  Settings {
    id: audioSettings
    location: StandardPaths.writableLocation(StandardPaths.GenericConfigLocation) + "/omatris.ini"
    category: "audio"
    property real musicVolume: 0.35
    property real effectsVolume: 0.7
    property bool muted: false
  }

  Settings {
    id: controlSettings
    location: StandardPaths.writableLocation(StandardPaths.GenericConfigLocation) + "/omatris.ini"
    category: "controls"
    property int leftPrimary: Qt.Key_Left
    property int leftSecondary: Qt.Key_A
    property int rightPrimary: Qt.Key_Right
    property int rightSecondary: Qt.Key_D
    property int downPrimary: Qt.Key_Down
    property int downSecondary: Qt.Key_S
    property int rotateLeftPrimary: Qt.Key_Z
    property int rotateLeftSecondary: 0
    property int rotateRightPrimary: Qt.Key_X
    property int rotateRightSecondary: Qt.Key_Up
    property int dropPrimary: Qt.Key_Space
    property int dropSecondary: 0
    property int holdPrimary: Qt.Key_C
    property int holdSecondary: Qt.Key_Shift
    property int pausePrimary: Qt.Key_P
    property int pauseSecondary: 0
    property int restartPrimary: Qt.Key_R
    property int restartSecondary: 0
    property int blockStylePrimary: Qt.Key_B
    property int blockStyleSecondary: 0
    property int mutePrimary: Qt.Key_M
    property int muteSecondary: 0
  }

  AudioController {
    id: audioController
    musicVolume: audioSettings.musicVolume
    effectsVolume: audioSettings.effectsVolume
    muted: audioSettings.muted
    active: window.visible || root.overlayActive
    gamePaused: root.game ? root.game.paused || root.windowTooSmall : false
  }

  readonly property var overlayScreen: screenForMonitor(overlayTarget ? overlayTarget.monitor : null)
  property bool overlayTestingNoFocus: false

  readonly property color background: Color.background
  readonly property color foreground: Color.foreground
  readonly property color accent: Color.accent
  readonly property color urgent: Color.urgent
  readonly property color muted: Color.muted
  readonly property color surface: Color.popups.background
  readonly property color subtle: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.08)
  readonly property color outline: Qt.rgba(accent.r, accent.g, accent.b, 0.38)
  readonly property color blockInterior: "#08090b"

  function open(payloadJson) {
    // Omarchy already owns one panel object per plugin ID. Treat a repeated
    // summon as a request for that active session instead of resetting it.
    // This keeps bar, hotkey, and CLI launches safe without privileging one
    // launch origin that the host does not otherwise need to expose.
    if (window.visible || overlayActive) {
      if (window.visible) Qt.callLater(function() { keyCatcher.forceActiveFocus() })
      return
    }

    closingFromHost = false
    overlayActive = false
    overlayTarget = null
    overlayTargetAddress = ""
    window.visible = true
    var requestedMode = ""
    var requestedOverlay = false
    if (payloadJson) {
      try {
        var payload = JSON.parse(String(payloadJson))
        if (payload && ["classic", "endless", "practice"].indexOf(payload.mode) >= 0)
          requestedMode = payload.mode
        else if (payload && payload.mode === "overlay")
          requestedOverlay = true
      } catch (error) { /* Ignore malformed optional payloads. */ }
    }
    if (requestedMode) startGame(requestedMode)
    else if (requestedOverlay) showOverlayPicker()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    stopGlobalHotkeyCapture("")
    overlayActive = false
    overlayTarget = null
    overlayTargetAddress = ""
    resetHeldInputs()
    closingFromHost = true
    window.visible = false
    closingFromHost = false
  }

  function requestClose() {
    stopGlobalHotkeyCapture("")
    if (overlayActive) {
      stopOverlay("")
      return
    }
    if (shell && typeof shell.hide === "function") shell.hide("com.80kv.omatris")
    else window.visible = false
  }

  function startGame(mode) {
    var previousPracticeSpeed = game && game.mode === "practice" ? game.practiceSpeed : 1.0
    resetHeldInputs()
    game = Game.newGame(mode)
    audioController.watchGame(game)
    if (mode === "practice") game.practiceSpeed = previousPracticeSpeed
    resultIndex = 0
    view = "game"
    revision += 1
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function screenForMonitor(monitor) {
    if (!monitor) return null
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++) {
      if (screens[i] && screens[i].name === monitor.name) return screens[i]
      var candidateMonitor = Hyprland.monitorFor(screens[i])
      if (candidateMonitor && candidateMonitor.id === monitor.id) return screens[i]
    }
    return null
  }

  function rebuildOverlayCandidates() {
    var candidates = []
    var values = Hyprland.toplevels && Hyprland.toplevels.values ? Hyprland.toplevels.values : []
    for (var i = 0; i < values.length; i++) {
      var toplevel = values[i]
      var ipc = toplevel ? toplevel.lastIpcObject : null
      if (!toplevel || !ipc || !toplevel.workspace || !toplevel.workspace.active) continue
      if (ipc.mapped === false || ipc.hidden === true) continue
      if (String(ipc.class || "") === "org.quickshell") continue
      if (!ipc.at || !ipc.size || ipc.size[0] < 220 || ipc.size[1] < 320) continue
      candidates.push({
        toplevel: toplevel,
        title: String(toplevel.title || ipc.title || ipc.class || "Untitled window"),
        appClass: String(ipc.class || "Application"),
        width: ipc.size[0],
        height: ipc.size[1],
        floating: ipc.floating === true
      })
    }
    overlayCandidates = candidates
    // The two positions after the windows are Refresh and Back. Keeping them
    // in one index makes the entire picker reachable with the same keys.
    overlayPickerIndex = Math.max(0, Math.min(overlayPickerIndex, candidates.length + 1))
    if (candidates.length === 0)
      overlayNotice = "No suitable windows found on this workspace."
    else if (overlayNotice === "No suitable windows found on this workspace.")
      overlayNotice = ""
  }

  function normalizedAddress(address) {
    return String(address || "").toLowerCase().replace(/^0x/, "")
  }

  function overlayIdentity(toplevel) {
    if (!toplevel) return ""
    var ipc = toplevel.lastIpcObject
    if (ipc && ipc.stableId) return "stable:" + String(ipc.stableId)
    return "address:" + normalizedAddress(toplevel.address)
  }

  function showOverlayPicker() {
    resetHeldInputs()
    overlayNotice = ""
    overlayPickerIndex = 0
    view = "overlayPicker"
    Hyprland.refreshToplevels()
    Qt.callLater(rebuildOverlayCandidates)
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function startOverlay(toplevel) {
    if (!toplevel || !toplevel.lastIpcObject) return
    var ipc = toplevel.lastIpcObject
    if (!ipc.size || ipc.size[0] < 220 || ipc.size[1] < 320) {
      overlayNotice = "That window is too small for a readable playfield."
      return
    }
    if (!screenForMonitor(toplevel.monitor)) {
      overlayNotice = "Could not match that window to a display."
      return
    }

    resetHeldInputs()
    game = Game.newGame("overlay")
    audioController.watchGame(game)
    resultIndex = 0
    overlayTarget = toplevel
    overlayTargetAddress = overlayIdentity(toplevel)
    overlayActive = true
    view = "game"
    revision += 1

    closingFromHost = true
    window.visible = false
    closingFromHost = false
  }

  function stopOverlay(message) {
    overlayActive = false
    overlayTarget = null
    overlayTargetAddress = ""
    resetHeldInputs()
    overlayNotice = message || ""
    view = "overlayPicker"
    window.visible = true
    Hyprland.refreshToplevels()
    Qt.callLater(rebuildOverlayCandidates)
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function syncOverlayTarget() {
    if (!overlayActive || !overlayTargetAddress) return
    var values = Hyprland.toplevels && Hyprland.toplevels.values ? Hyprland.toplevels.values : []
    for (var i = 0; i < values.length; i++) {
      var candidate = values[i]
      if (candidate && overlayIdentity(candidate) === overlayTargetAddress) {
        var ipc = candidate.lastIpcObject
        if (!candidate.workspace || !candidate.workspace.active || !ipc || ipc.hidden === true) {
          stopOverlay("The selected window is no longer visible here.")
          return
        }
        overlayTarget = candidate
        return
      }
    }
    stopOverlay("The selected window was closed.")
  }

  function refresh() {
    recordHighScoreIfFinished()
    audioController.syncGame(game)
    revision += 1
  }

  function highScoreForMode(mode) {
    if (mode === "classic") return highScores.classic
    if (mode === "endless") return highScores.endless
    if (mode === "overlay") return highScores.overlay
    return 0
  }

  function recordHighScoreIfFinished() {
    if (!game || game.status === "playing" || game.mode === "practice" || game.highScoreRecorded) return
    var previous = highScoreForMode(game.mode)
    game.isNewHighScore = game.score > previous
    if (game.mode === "classic" && game.score > highScores.classic) highScores.classic = game.score
    else if (game.mode === "endless" && game.score > highScores.endless) highScores.endless = game.score
    else if (game.mode === "overlay" && game.score > highScores.overlay) highScores.overlay = game.score
    game.highScoreRecorded = true
  }

  function finishIfLocalBest() {
    if (!game || !Game.qualifiesForLocalBest(game, highScoreForMode(game.mode))) return false
    resetHeldInputs()
    Game.endRun(game)
    resultIndex = 0
    refresh()
    return true
  }

  function toggleBlockStyle() {
    blockStyle = blockStyle === "solid" ? "outline" : "solid"
    refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function resetHeldInputs() {
    leftHeld = false
    rightHeld = false
    downHeld = false
    horizontalDirection = 0
    rotateLeftHeld = false
    rotateRightHeld = false
    rotationDirection = 0
    horizontalRepeat.stop()
    softDropRepeat.stop()
    rotationRepeat.stop()
  }

  function returnToMenu() {
    resetHeldInputs()
    rebindingAction = ""
    editingVolume = ""
    stopGlobalHotkeyCapture("")
    view = "menu"
    refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function pressHorizontal(direction) {
    if (direction < 0) leftHeld = true
    else rightHeld = true
    horizontalDirection = direction
    perform(direction < 0 ? "left" : "right")
    horizontalRepeat.interval = 150
    horizontalRepeat.repeat = false
    horizontalRepeat.restart()
  }

  function releaseHorizontal(direction) {
    if (direction < 0) leftHeld = false
    else rightHeld = false

    if (horizontalDirection !== direction) return
    horizontalDirection = leftHeld ? -1 : rightHeld ? 1 : 0
    horizontalRepeat.stop()
    if (horizontalDirection !== 0) {
      perform(horizontalDirection < 0 ? "left" : "right")
      horizontalRepeat.interval = 150
      horizontalRepeat.repeat = false
      horizontalRepeat.restart()
    }
  }

  function pressRotation(direction) {
    if (direction < 0) rotateLeftHeld = true
    else rotateRightHeld = true
    rotationDirection = direction
    perform(direction < 0 ? "rotateLeft" : "rotateRight")
    rotationRepeat.interval = 320
    rotationRepeat.repeat = false
    rotationRepeat.restart()
  }

  function releaseRotation(direction) {
    if (direction < 0) rotateLeftHeld = false
    else rotateRightHeld = false

    if (rotationDirection !== direction) return
    rotationDirection = rotateLeftHeld ? -1 : rotateRightHeld ? 1 : 0
    rotationRepeat.stop()
    if (rotationDirection !== 0) {
      pressRotation(rotationDirection)
    }
  }

  function setPracticeSpeed(speed) {
    if (!game || game.mode !== "practice") return
    game.practiceSpeed = Math.max(0, Math.min(1.5, Math.round(speed * 10) / 10))
    refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function cellToken(row, column) {
    if (!game || row < 0 || row >= Game.HEIGHT || column < 0 || column >= Game.WIDTH) return ""
    var active = Game.activeCell(game, row, column)
    if (active) return "active:" + active
    var locked = game.board[row][column]
    if (locked) return "locked:" + locked
    if (Game.ghostCell(game, row, column)) return "ghost:" + game.current.kind
    return ""
  }

  function tokenKind(token) {
    var separator = token.indexOf(":")
    return separator >= 0 ? token.slice(separator + 1) : ""
  }

  function shouldDrawEdge(token, neighborToken) {
    if (!token) return false
    if (token.indexOf("locked:") === 0)
      return neighborToken.indexOf("locked:") !== 0
    return neighborToken !== token
  }

  function pieceColor(kind) {
    switch (kind) {
      case "I": return accent
      case "O": return foreground
      case "T": return Qt.tint(accent, Qt.rgba(urgent.r, urgent.g, urgent.b, 0.34))
      case "S": return Qt.tint(accent, Qt.rgba(muted.r, muted.g, muted.b, 0.42))
      case "Z": return urgent
      case "J": return Qt.darker(accent, 1.35)
      case "L": return Qt.tint(foreground, Qt.rgba(urgent.r, urgent.g, urgent.b, 0.30))
      default: return "transparent"
    }
  }

  function controlDefinitions() {
    return [
      { action: "left", label: "MOVE LEFT" },
      { action: "right", label: "MOVE RIGHT" },
      { action: "down", label: "SOFT DROP" },
      { action: "rotateLeft", label: "ROTATE LEFT" },
      { action: "rotateRight", label: "ROTATE RIGHT" },
      { action: "drop", label: "HARD DROP" },
      { action: "hold", label: "HOLD" },
      { action: "pause", label: "PAUSE" },
      { action: "restart", label: "RESTART" },
      { action: "blockStyle", label: "BLOCK STYLE" },
      { action: "mute", label: "MUTE AUDIO" }
    ]
  }

  function bindingProperty(action, slot) {
    return action + (slot === 0 ? "Primary" : "Secondary")
  }

  function bindingValue(action, slot) {
    return controlSettings[bindingProperty(action, slot)] || 0
  }

  function matchesBinding(action, key) {
    return key === bindingValue(action, 0) || key === bindingValue(action, 1)
  }

  function setBinding(action, slot, key) {
    if (key !== 0) {
      var definitions = controlDefinitions()
      for (var index = 0; index < definitions.length; index++) {
        for (var candidateSlot = 0; candidateSlot < 2; candidateSlot++) {
          if (definitions[index].action === action && candidateSlot === slot) continue
          var propertyName = bindingProperty(definitions[index].action, candidateSlot)
          if (controlSettings[propertyName] === key) controlSettings[propertyName] = 0
        }
      }
    }
    controlSettings[bindingProperty(action, slot)] = key
    settingsNotice = key === 0 ? "Binding cleared" : actionLabel(action) + " set to " + keyName(key)
    rebindingAction = ""
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function actionLabel(action) {
    var definitions = controlDefinitions()
    for (var index = 0; index < definitions.length; index++)
      if (definitions[index].action === action) return definitions[index].label
    return action
  }

  function bindingSummary(action) {
    var primary = keyName(bindingValue(action, 0))
    var secondaryValue = bindingValue(action, 1)
    return secondaryValue ? primary + " / " + keyName(secondaryValue) : primary
  }

  function beginRebind(action, slot) {
    editingVolume = ""
    stopGlobalHotkeyCapture("")
    rebindingAction = action
    rebindingSlot = slot
    settingsNotice = "Press a key · Esc cancels · Backspace clears"
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function keyName(key) {
    if (!key) return "—"
    if (key >= Qt.Key_A && key <= Qt.Key_Z) return String.fromCharCode(key)
    if (key >= Qt.Key_0 && key <= Qt.Key_9) return String.fromCharCode(key)
    switch (key) {
      case Qt.Key_Left: return "LEFT"
      case Qt.Key_Right: return "RIGHT"
      case Qt.Key_Up: return "UP"
      case Qt.Key_Down: return "DOWN"
      case Qt.Key_Space: return "SPACE"
      case Qt.Key_Shift: return "SHIFT"
      case Qt.Key_Control: return "CTRL"
      case Qt.Key_Alt: return "ALT"
      case Qt.Key_Tab: return "TAB"
      case Qt.Key_Return: return "ENTER"
      case Qt.Key_Enter: return "ENTER"
      case Qt.Key_Backspace: return "BACKSPACE"
      case Qt.Key_Delete: return "DELETE"
      case Qt.Key_Home: return "HOME"
      case Qt.Key_End: return "END"
      case Qt.Key_PageUp: return "PAGE UP"
      case Qt.Key_PageDown: return "PAGE DOWN"
      default: return "KEY " + key
    }
  }

  function resetControlBindings() {
    controlSettings.leftPrimary = Qt.Key_Left; controlSettings.leftSecondary = Qt.Key_A
    controlSettings.rightPrimary = Qt.Key_Right; controlSettings.rightSecondary = Qt.Key_D
    controlSettings.downPrimary = Qt.Key_Down; controlSettings.downSecondary = Qt.Key_S
    controlSettings.rotateLeftPrimary = Qt.Key_Z; controlSettings.rotateLeftSecondary = 0
    controlSettings.rotateRightPrimary = Qt.Key_X; controlSettings.rotateRightSecondary = Qt.Key_Up
    controlSettings.dropPrimary = Qt.Key_Space; controlSettings.dropSecondary = 0
    controlSettings.holdPrimary = Qt.Key_C; controlSettings.holdSecondary = Qt.Key_Shift
    controlSettings.pausePrimary = Qt.Key_P; controlSettings.pauseSecondary = 0
    controlSettings.restartPrimary = Qt.Key_R; controlSettings.restartSecondary = 0
    controlSettings.blockStylePrimary = Qt.Key_B; controlSettings.blockStyleSecondary = 0
    controlSettings.mutePrimary = Qt.Key_M; controlSettings.muteSecondary = 0
    settingsNotice = "Default controls restored"
    refresh()
  }

  function setVolume(kind, value) {
    var normalized = Math.max(0, Math.min(1, Math.round(value * 20) / 20))
    if (kind === "music") audioSettings.musicVolume = normalized
    else {
      audioSettings.effectsVolume = normalized
      audioController.previewEffect()
    }
  }

  function hotkeyHelperPath() {
    var url = String(Qt.resolvedUrl("scripts/omatris-hotkey"))
    return decodeURIComponent(url.replace(/^file:\/\//, ""))
  }

  function runHotkeyOperation(operation, shortcut) {
    if (hotkeyProcess.running) return
    hotkeyOperation = operation
    hotkeyBusy = true
    hotkeyError = false
    settingsNotice = operation === "get" ? "Checking global shortcut…"
      : operation === "capture-on" ? "Preparing protected shortcut capture…"
      : "Checking Hyprland bindings…"
    var command = ["bash", hotkeyHelperPath(), operation]
    if (shortcut) command.push(shortcut)
    hotkeyProcess.command = command
    hotkeyProcess.running = true
  }

  function handleHotkeyResult(exitCode, output, errorOutput) {
    hotkeyBusy = false
    var completedOperation = hotkeyOperation
    var result = null
    try { result = JSON.parse(String(output || "").trim()) }
    catch (error) { /* The fallback below reports malformed helper output. */ }

    if (result) {
      if (result.status === "ok") globalHotkey = result.shortcut || ""
      hotkeyError = result.status !== "ok"
      settingsNotice = result.message || (completedOperation === "get"
        ? (result.shortcut ? "Global shortcut active" : "No global shortcut set")
        : result.status === "ok" ? "Global shortcut updated" : "Could not update shortcut")
    } else {
      hotkeyError = true
      settingsNotice = String(errorOutput || "").trim() || "Could not update the global shortcut"
    }
    capturingGlobalHotkey = completedOperation === "capture-on" && result && result.status === "ok"
      && hotkeyCaptureRequested && view === "settings" && window.visible
    if (completedOperation === "capture-on" && !capturingGlobalHotkey)
      resetHyprlandSubmap()
    if (completedOperation !== "capture-on" || !capturingGlobalHotkey)
      hotkeyCaptureRequested = false
    hotkeyOperation = ""
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function beginGlobalHotkeyCapture() {
    if (hotkeyBusy) return
    editingVolume = ""
    rebindingAction = ""
    capturingGlobalHotkey = false
    hotkeyCaptureRequested = true
    hotkeyError = false
    runHotkeyOperation("capture-on", "")
  }

  function resetHyprlandSubmap() {
    Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.submap(\"reset\")"])
  }

  function stopGlobalHotkeyCapture(message) {
    if (capturingGlobalHotkey || hotkeyCaptureRequested) resetHyprlandSubmap()
    capturingGlobalHotkey = false
    hotkeyCaptureRequested = false
    if (message !== undefined && message !== "") settingsNotice = message
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function isModifierKey(key) {
    return key === Qt.Key_Shift || key === Qt.Key_Control || key === Qt.Key_Alt
      || key === Qt.Key_Meta || key === Qt.Key_Super_L || key === Qt.Key_Super_R
  }

  function globalHotkeyKeyName(key) {
    if (key >= Qt.Key_A && key <= Qt.Key_Z) return String.fromCharCode(key)
    if (key >= Qt.Key_0 && key <= Qt.Key_9) return String.fromCharCode(key)
    if (key >= Qt.Key_F1 && key <= Qt.Key_F12) return "F" + (key - Qt.Key_F1 + 1)
    switch (key) {
      case Qt.Key_Left: return "LEFT"
      case Qt.Key_Right: return "RIGHT"
      case Qt.Key_Up: return "UP"
      case Qt.Key_Down: return "DOWN"
      case Qt.Key_Space: return "SPACE"
      case Qt.Key_Tab: return "TAB"
      case Qt.Key_Return: return "RETURN"
      case Qt.Key_Enter: return "ENTER"
      case Qt.Key_Home: return "HOME"
      case Qt.Key_End: return "END"
      case Qt.Key_PageUp: return "PAGEUP"
      case Qt.Key_PageDown: return "PAGEDOWN"
      case Qt.Key_Insert: return "INSERT"
      case Qt.Key_Delete: return "DELETE"
      default: return ""
    }
  }

  function globalHotkeyForEvent(event) {
    var key = globalHotkeyKeyName(event.key)
    if (!key) return ""
    var parts = []
    if ((event.modifiers & Qt.MetaModifier) !== 0) parts.push("SUPER")
    if ((event.modifiers & Qt.ControlModifier) !== 0) parts.push("CTRL")
    if ((event.modifiers & Qt.AltModifier) !== 0) parts.push("ALT")
    if ((event.modifiers & Qt.ShiftModifier) !== 0) parts.push("SHIFT")
    if (parts.indexOf("SUPER") < 0 && parts.indexOf("CTRL") < 0 && parts.indexOf("ALT") < 0) return ""
    parts.push(key)
    return parts.join(" + ")
  }

  function currentSettingsTarget() {
    return SettingsNavigation.targetAt(settingsFocus, controlDefinitions().length)
  }

  function controlSlotFocused(controlIndex, slot) {
    var target = currentSettingsTarget()
    return target.kind === "control" && target.controlIndex === controlIndex && target.slot === slot
  }

  function modeTitle(mode) {
    if (mode === "classic") return "CLASSIC · 40 LINES"
    if (mode === "endless") return "ENDLESS"
    if (mode === "overlay") return "OVERLAY"
    return "PRACTICE"
  }

  function scaleToFit(availableWidth, availableHeight, contentWidth, contentHeight) {
    if (availableWidth <= 0 || availableHeight <= 0 || contentWidth <= 0 || contentHeight <= 0) return 1
    return Math.max(0.1, Math.min(1, availableWidth / contentWidth, availableHeight / contentHeight))
  }

  function activateMenuSelection() {
    var modes = ["classic", "endless", "practice", "overlay", "settings"]
    var mode = modes[Math.max(0, Math.min(menuIndex, modes.length - 1))]
    if (mode === "settings") {
      settingsFocus = 0
      editingVolume = ""
      rebindingAction = ""
      capturingGlobalHotkey = false
      settingsNotice = ""
      view = "settings"
      refresh()
      runHotkeyOperation("get", "")
    } else if (mode === "overlay") showOverlayPicker()
    else startGame(mode)
  }

  function activateOverlayPickerSelection() {
    var candidateCount = overlayCandidates.length
    if (overlayPickerIndex < candidateCount) {
      startOverlay(overlayCandidates[overlayPickerIndex].toplevel)
    } else if (overlayPickerIndex === candidateCount) {
      Hyprland.refreshToplevels()
      Qt.callLater(rebuildOverlayCandidates)
    } else {
      returnToMenu()
    }
  }

  function activateResultSelection() {
    if (resultIndex === 0) {
      if (overlayActive) {
        game = Game.newGame("overlay")
        audioController.watchGame(game)
        resetHeldInputs()
        refresh()
      } else {
        startGame(game.mode)
      }
    } else if (overlayActive) {
      stopOverlay("")
    } else {
      returnToMenu()
    }
  }

  function perform(action) {
    if (!game) return
    var succeeded = false
    if (action === "left") succeeded = Game.move(game, -1, 0)
    else if (action === "right") succeeded = Game.move(game, 1, 0)
    else if (action === "down") succeeded = Game.move(game, 0, 1)
    else if (action === "rotateRight") succeeded = Game.rotate(game, 1)
    else if (action === "rotateLeft") succeeded = Game.rotate(game, -1)
    else if (action === "drop") succeeded = Game.hardDrop(game)
    else if (action === "hold") succeeded = Game.hold(game)
    if (succeeded) audioController.playAction(action)
    refresh()
  }

  function handleGameKeyPressed(event, fromOverlay) {
    if (windowTooSmall && !fromOverlay) {
      event.accepted = true
      return
    }

    if (view === "settings" && capturingGlobalHotkey) {
      if (event.isAutoRepeat || isModifierKey(event.key)) {
        event.accepted = true
        return
      }
      if (event.key === Qt.Key_Escape) {
        stopGlobalHotkeyCapture("Global shortcut unchanged")
      } else if (event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete) {
        stopGlobalHotkeyCapture("")
        runHotkeyOperation("clear", "")
      } else {
        var shortcut = globalHotkeyForEvent(event)
        if (shortcut === "") {
          stopGlobalHotkeyCapture("")
          hotkeyError = true
          settingsNotice = "Use Super, Ctrl, or Alt together with one supported key"
        } else {
          stopGlobalHotkeyCapture("")
          runHotkeyOperation("set", shortcut)
        }
      }
      event.accepted = true
      return
    }

    if (view === "settings" && rebindingAction !== "") {
      if (event.isAutoRepeat) { event.accepted = true; return }
      if (event.key === Qt.Key_Escape) {
        rebindingAction = ""
        settingsNotice = "Binding unchanged"
      } else if (event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete) {
        setBinding(rebindingAction, rebindingSlot, 0)
      } else {
        setBinding(rebindingAction, rebindingSlot, event.key)
      }
      event.accepted = true
      return
    }

    if (view === "settings" && editingVolume !== "") {
      if (event.key === Qt.Key_Left || event.key === Qt.Key_Right) {
        var volumeDirection = event.key === Qt.Key_Left ? -1 : 1
        var currentVolume = editingVolume === "music" ? audioSettings.musicVolume : audioSettings.effectsVolume
        setVolume(editingVolume, currentVolume + volumeDirection * 0.05)
      } else if (!event.isAutoRepeat && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Escape)) {
        settingsNotice = editingVolume === "music" ? "Music volume set" : "Effects volume set"
        editingVolume = ""
      } else {
        event.accepted = true
        return
      }
      event.accepted = true
      return
    }

    if (event.key === Qt.Key_Escape) {
      if (view === "game" && game && game.status === "playing" && finishIfLocalBest()) {
        // Keep the completed run visible so the player sees and can act on the local best.
      } else if (fromOverlay || overlayActive) stopOverlay("")
      else if (view === "game" || view === "overlayPicker" || view === "settings") returnToMenu()
      else requestClose()
      event.accepted = true
      return
    }

    if (view === "menu") {
      if (!event.isAutoRepeat && (event.key === Qt.Key_Up || event.key === Qt.Key_Left)) {
        menuIndex = (menuIndex + 4) % 5
        event.accepted = true
      } else if (!event.isAutoRepeat && (event.key === Qt.Key_Down || event.key === Qt.Key_Right)) {
        menuIndex = (menuIndex + 1) % 5
        event.accepted = true
      } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
        activateMenuSelection()
        event.accepted = true
      } else if (event.key === Qt.Key_O) {
        showOverlayPicker()
        event.accepted = true
      }
      return
    }

    if (view === "settings") {
      var controls = controlDefinitions()
      if (!event.isAutoRepeat && event.key === Qt.Key_Tab) {
        settingsFocus = SettingsNavigation.tab(settingsFocus, (event.modifiers & Qt.ShiftModifier) !== 0, controls.length)
        settingsNotice = ""
      } else if (event.key === Qt.Key_Left) {
        settingsFocus = SettingsNavigation.move(settingsFocus, -1, 0, controls.length)
        settingsNotice = ""
      } else if (event.key === Qt.Key_Right) {
        settingsFocus = SettingsNavigation.move(settingsFocus, 1, 0, controls.length)
        settingsNotice = ""
      } else if (event.key === Qt.Key_Up) {
        settingsFocus = SettingsNavigation.move(settingsFocus, 0, -1, controls.length)
        settingsNotice = ""
      } else if (event.key === Qt.Key_Down) {
        settingsFocus = SettingsNavigation.move(settingsFocus, 0, 1, controls.length)
        settingsNotice = ""
      } else if (!event.isAutoRepeat && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)) {
        var target = currentSettingsTarget()
        if (target.kind === "volume") {
          editingVolume = target.id
          settingsNotice = "Use ← → to adjust · Enter or Esc finishes"
        } else if (target.kind === "control") {
          beginRebind(controls[target.controlIndex].action, target.slot)
        } else if (target.kind === "hotkey") {
          beginGlobalHotkeyCapture()
        } else if (target.id === "reset") {
          resetControlBindings()
        } else if (target.id === "mute") {
          audioSettings.muted = !audioSettings.muted
          settingsNotice = audioSettings.muted ? "Audio muted" : "Audio unmuted"
        } else if (target.id === "back") {
          returnToMenu()
        }
      } else return
      event.accepted = true
      return
    }

    if (view === "overlayPicker") {
      if (event.key === Qt.Key_R) {
        Hyprland.refreshToplevels()
        Qt.callLater(rebuildOverlayCandidates)
        event.accepted = true
      } else if (!event.isAutoRepeat && (event.key === Qt.Key_Up || event.key === Qt.Key_Left || event.key === Qt.Key_K)) {
        overlayPickerIndex = (overlayPickerIndex + overlayCandidates.length + 1) % (overlayCandidates.length + 2)
        event.accepted = true
      } else if (!event.isAutoRepeat && (event.key === Qt.Key_Down || event.key === Qt.Key_Right || event.key === Qt.Key_J)) {
        overlayPickerIndex = (overlayPickerIndex + 1) % (overlayCandidates.length + 2)
        event.accepted = true
      } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
        activateOverlayPickerSelection()
        event.accepted = true
      }
      return
    }

    if (view !== "game" || !game) return
    if (game.status !== "playing") {
      if (!event.isAutoRepeat && (event.key === Qt.Key_Left || event.key === Qt.Key_Up)) {
        resultIndex = 0
      } else if (!event.isAutoRepeat && (event.key === Qt.Key_Right || event.key === Qt.Key_Down)) {
        resultIndex = 1
      } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
        activateResultSelection()
      } else if (matchesBinding("restart", event.key)) {
        resultIndex = 0
        activateResultSelection()
      } else return
      event.accepted = true
      return
    }

    if (matchesBinding("left", event.key)) {
      if (!event.isAutoRepeat) pressHorizontal(-1)
    } else if (matchesBinding("right", event.key)) {
      if (!event.isAutoRepeat) pressHorizontal(1)
    } else if (matchesBinding("down", event.key)) {
      if (!event.isAutoRepeat) {
        downHeld = true
        perform("down")
        softDropRepeat.interval = 100
        softDropRepeat.repeat = false
        softDropRepeat.restart()
      }
    } else if (matchesBinding("rotateRight", event.key)) {
      if (!event.isAutoRepeat) pressRotation(1)
    } else if (matchesBinding("rotateLeft", event.key)) {
      if (!event.isAutoRepeat) pressRotation(-1)
    } else if (matchesBinding("drop", event.key)) { if (!event.isAutoRepeat) perform("drop") }
    else if (matchesBinding("hold", event.key)) { if (!event.isAutoRepeat) perform("hold") }
    else if (matchesBinding("blockStyle", event.key)) { if (!event.isAutoRepeat) toggleBlockStyle() }
    else if (matchesBinding("pause", event.key)) {
      if (!event.isAutoRepeat) { game.paused = !game.paused; refresh() }
    } else if (matchesBinding("mute", event.key)) {
      if (!event.isAutoRepeat) audioSettings.muted = !audioSettings.muted
    } else if (matchesBinding("restart", event.key)) {
      if (event.isAutoRepeat) { event.accepted = true; return }
      if (finishIfLocalBest()) {
        // A second Restart from the results screen starts the next run.
      } else if (overlayActive) {
        game = Game.newGame("overlay")
        audioController.watchGame(game)
        resetHeldInputs()
        refresh()
      } else startGame(game.mode)
    } else return
    event.accepted = true
  }

  function handleGameKeyReleased(event) {
    if (windowTooSmall) {
      event.accepted = true
      return
    }
    if (event.isAutoRepeat) return
    if (matchesBinding("left", event.key)) {
      releaseHorizontal(-1)
      event.accepted = true
    } else if (matchesBinding("right", event.key)) {
      releaseHorizontal(1)
      event.accepted = true
    } else if (matchesBinding("down", event.key)) {
      downHeld = false
      softDropRepeat.stop()
      event.accepted = true
    } else if (matchesBinding("rotateRight", event.key)) {
      releaseRotation(1)
      event.accepted = true
    } else if (matchesBinding("rotateLeft", event.key)) {
      releaseRotation(-1)
      event.accepted = true
    }
  }

  FloatingWindow {
    id: window
    title: "Omatris"
    color: root.background
    implicitWidth: 1040
    implicitHeight: 780
    minimumSize: Qt.size(root.minimumUsableWidth, root.minimumUsableHeight)

    onVisibleChanged: {
      if (!visible) root.stopGlobalHotkeyCapture("")
      if (!visible && !root.overlayActive && !root.closingFromHost
          && root.shell && typeof root.shell.hide === "function")
        root.shell.hide("com.80kv.omatris")
    }

    FocusScope {
      id: keyCatcher
      anchors.fill: parent
      focus: true

      Keys.onPressed: function(event) { root.handleGameKeyPressed(event, false) }
      Keys.onReleased: function(event) { root.handleGameKeyReleased(event) }

      Rectangle {
        anchors.fill: parent
        color: root.background

        Rectangle {
          anchors.fill: parent
          anchors.margins: Math.max(12, Math.min(38, parent.width * 0.04, parent.height * 0.04))
          radius: Math.max(0, Style.cornerRadius)
          color: root.surface
          border.width: 1
          border.color: root.outline

          Item {
            anchors.fill: parent
            anchors.margins: Math.max(12, Math.min(28, parent.width * 0.03, parent.height * 0.03))

            Column {
              id: menuView
              property bool carousel: parent.height < 590
              visible: root.view === "menu"
              anchors.centerIn: parent
              width: Math.min(660, parent.width)
              spacing: carousel ? 16 : 22

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "OMATRIS"
                color: root.foreground
                font.family: Style.fontFamily
                font.pixelSize: 32
                font.weight: Font.DemiBold
                font.letterSpacing: 2
              }

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Pick a mode. The blocks follow your current theme."
                color: root.muted
                font.family: Style.fontFamily
                font.pixelSize: 14
              }

              Column {
                width: parent.width
                spacing: 10

                Repeater {
                  model: [
                    { mode: "classic", title: "CLASSIC", detail: "Clear 40 lines · local best " + root.highScoreForMode("classic") },
                    { mode: "endless", title: "ENDLESS", detail: "Play until top-out · local best " + root.highScoreForMode("endless") },
                    { mode: "practice", title: "PRACTICE", detail: "Adjustable gravity · the board resets instead of ending" },
                    { mode: "overlay", title: "OVERLAY  ·  EXPERIMENTAL", detail: "Play over a window · local best " + root.highScoreForMode("overlay") },
                    { mode: "settings", title: "SETTINGS", detail: "Audio levels · fully customizable controls" }
                  ]

                  delegate: Rectangle {
                    required property int index
                    required property var modelData
                    property bool selected: index === root.menuIndex
                    visible: !menuView.carousel || selected
                    width: parent.width
                    height: 72
                    radius: Math.max(0, Style.cornerRadius * 0.65)
                    color: selected ? root.subtle : "transparent"
                    border.width: 1
                    border.color: selected ? root.accent : root.subtle

                    Row {
                      anchors.fill: parent
                      anchors.margins: 18
                      spacing: 18

                      Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 9
                        height: 36
                        radius: 2
                        color: modelData.mode === "classic" ? root.accent
                          : modelData.mode === "endless" ? root.urgent
                          : modelData.mode === "overlay" ? root.foreground
                          : modelData.mode === "settings" ? root.accent : root.muted
                      }

                      Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 5

                        Text {
                          text: modelData.title
                          color: root.foreground
                          font.family: Style.fontFamily
                          font.pixelSize: 17
                          font.weight: Font.DemiBold
                          font.letterSpacing: 1
                        }
                        Text {
                          text: modelData.detail
                          color: root.muted
                          font.family: Style.fontFamily
                          font.pixelSize: 12
                        }
                      }
                    }

                    MouseArea {
                      id: modeMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onEntered: root.menuIndex = index
                      onClicked: {
                        root.menuIndex = index
                        root.activateMenuSelection()
                      }
                    }
                  }
                }
              }

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: menuView.carousel
                  ? "↑ ↓ cycle modes  ·  Enter select  ·  O overlay"
                  : "↑ ↓ choose  ·  Enter select  ·  O overlay"
                color: root.muted
                font.family: Style.fontFamily
                font.pixelSize: 12
              }
            }

            Column {
              id: settingsView
              property real responsiveScale: root.scaleToFit(parent.width, parent.height, 760, implicitHeight)
              visible: root.view === "settings"
              anchors.centerIn: parent
              width: 760
              scale: responsiveScale
              spacing: 13

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "SETTINGS"
                color: root.foreground
                font.family: Style.fontFamily
                font.pixelSize: 27
                font.weight: Font.DemiBold
                font.letterSpacing: 2
              }

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "AUDIO"
                color: root.accent
                font.family: Style.fontFamily
                font.pixelSize: 11
                font.weight: Font.DemiBold
                font.letterSpacing: 1.4
              }

              Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 14

                VolumeSetting {
                  label: "MUSIC"
                  value: audioSettings.musicVolume
                  selected: root.settingsFocus === 0
                  editing: root.editingVolume === "music"
                  onHovered: root.settingsFocus = 0
                  onVolumeSelected: function(value) { root.setVolume("music", value) }
                }

                VolumeSetting {
                  label: "EFFECTS"
                  value: audioSettings.effectsVolume
                  selected: root.settingsFocus === 1
                  editing: root.editingVolume === "effects"
                  onHovered: root.settingsFocus = 1
                  onVolumeSelected: function(value) { root.setVolume("effects", value) }
                }
              }

              Row {
                width: parent.width

                Text {
                  text: "CONTROLS"
                  color: root.accent
                  font.family: Style.fontFamily
                  font.pixelSize: 11
                  font.weight: Font.DemiBold
                  font.letterSpacing: 1.4
                }

                Item { width: parent.width - 181; height: 1 }

                Text {
                  text: "PRIMARY    SECONDARY"
                  color: root.muted
                  font.family: Style.fontFamily
                  font.pixelSize: 9
                  font.letterSpacing: 0.6
                }
              }

              Grid {
                anchors.horizontalCenter: parent.horizontalCenter
                columns: 2
                columnSpacing: 10
                rowSpacing: 7

                Repeater {
                  model: root.controlDefinitions()

                  delegate: Rectangle {
                    required property int index
                    required property var modelData
                    property bool selected: root.controlSlotFocused(index, 0) || root.controlSlotFocused(index, 1)
                    width: 375
                    height: 42
                    radius: Math.max(0, Style.cornerRadius * 0.4)
                    color: selected ? root.subtle : "transparent"
                    border.width: 1
                    border.color: selected ? root.outline : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.07)

                    Text {
                      anchors.left: parent.left
                      anchors.leftMargin: 13
                      anchors.verticalCenter: parent.verticalCenter
                      text: modelData.label
                      color: root.foreground
                      font.family: Style.fontFamily
                      font.pixelSize: 10
                      font.weight: Font.DemiBold
                      font.letterSpacing: 0.5
                    }

                    Row {
                      anchors.right: parent.right
                      anchors.rightMargin: 7
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: 6

                      BindingButton {
                        label: root.keyName(root.bindingValue(modelData.action, 0))
                        selected: root.controlSlotFocused(index, 0)
                        listening: root.rebindingAction === modelData.action && root.rebindingSlot === 0
                        onClicked: {
                          root.settingsFocus = SettingsNavigation.controlFocus(index, 0)
                          root.beginRebind(modelData.action, 0)
                        }
                      }
                      BindingButton {
                        label: root.keyName(root.bindingValue(modelData.action, 1))
                        selected: root.controlSlotFocused(index, 1)
                        listening: root.rebindingAction === modelData.action && root.rebindingSlot === 1
                        onClicked: {
                          root.settingsFocus = SettingsNavigation.controlFocus(index, 1)
                          root.beginRebind(modelData.action, 1)
                        }
                      }
                    }

                    MouseArea {
                      anchors.fill: parent
                      z: -1
                      hoverEnabled: true
                      onEntered: root.settingsFocus = SettingsNavigation.controlFocus(index, 0)
                    }
                  }
                }
              }

              Row {
                width: parent.width

                Text {
                  text: "GLOBAL SHORTCUT"
                  color: root.accent
                  font.family: Style.fontFamily
                  font.pixelSize: 11
                  font.weight: Font.DemiBold
                  font.letterSpacing: 1.4
                }

                Item { width: parent.width - 221; height: 1 }

                Text {
                  text: "DELETE TO REMOVE"
                  color: root.muted
                  font.family: Style.fontFamily
                  font.pixelSize: 9
                  font.letterSpacing: 0.6
                }
              }

              Rectangle {
                id: globalHotkeyBox
                property bool selected: root.settingsFocus === SettingsNavigation.hotkeyFocus(root.controlDefinitions().length)
                width: parent.width
                height: 44
                radius: Math.max(0, Style.cornerRadius * 0.4)
                color: selected ? root.subtle : "transparent"
                border.width: root.capturingGlobalHotkey ? 2 : 1
                border.color: root.hotkeyError ? root.urgent : selected ? root.accent : root.outline

                Text {
                  anchors.left: parent.left
                  anchors.leftMargin: 13
                  anchors.verticalCenter: parent.verticalCenter
                  text: "OPEN OMATRIS"
                  color: root.foreground
                  font.family: Style.fontFamily
                  font.pixelSize: 10
                  font.weight: Font.DemiBold
                  font.letterSpacing: 0.5
                }

                Text {
                  anchors.right: parent.right
                  anchors.rightMargin: 13
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.hotkeyBusy ? "CHECKING…"
                    : root.capturingGlobalHotkey ? "PRESS SHORTCUT"
                    : root.globalHotkey || "NOT SET"
                  color: root.hotkeyError ? root.urgent : root.capturingGlobalHotkey ? root.accent : root.muted
                  font.family: Style.fontFamily
                  font.pixelSize: 10
                  font.weight: Font.DemiBold
                  font.letterSpacing: 0.5
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onEntered: root.settingsFocus = SettingsNavigation.hotkeyFocus(root.controlDefinitions().length)
                  onClicked: {
                    root.settingsFocus = SettingsNavigation.hotkeyFocus(root.controlDefinitions().length)
                    root.beginGlobalHotkeyCapture()
                  }
                }
              }

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.settingsNotice || "Select a key slot, then press the replacement key"
                color: root.hotkeyError ? root.urgent
                  : root.rebindingAction || root.capturingGlobalHotkey || root.hotkeyBusy ? root.accent : root.muted
                font.family: Style.fontFamily
                font.pixelSize: 10
              }

              Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 10

                ActionButton {
                  label: "RESET CONTROLS"
                  selected: root.settingsFocus === SettingsNavigation.actionFocus(root.controlDefinitions().length, 0)
                  onHovered: root.settingsFocus = SettingsNavigation.actionFocus(root.controlDefinitions().length, 0)
                  onClicked: root.resetControlBindings()
                }
                ActionButton {
                  label: audioSettings.muted ? "UNMUTE" : "MUTE AUDIO"
                  selected: root.settingsFocus === SettingsNavigation.actionFocus(root.controlDefinitions().length, 1)
                  onHovered: root.settingsFocus = SettingsNavigation.actionFocus(root.controlDefinitions().length, 1)
                  onClicked: audioSettings.muted = !audioSettings.muted
                }
                ActionButton {
                  label: "BACK"
                  selected: root.settingsFocus === SettingsNavigation.actionFocus(root.controlDefinitions().length, 2)
                  onHovered: root.settingsFocus = SettingsNavigation.actionFocus(root.controlDefinitions().length, 2)
                  onClicked: root.returnToMenu()
                }
              }

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "ARROWS move  ·  TAB / SHIFT+TAB cycle  ·  ENTER edit/select  ·  ESC back"
                color: root.muted
                font.family: Style.fontFamily
                font.pixelSize: 10
              }
            }

            Column {
              id: overlayPickerView
              property real responsiveScale: root.scaleToFit(parent.width, parent.height, 720, implicitHeight)
              visible: root.view === "overlayPicker"
              anchors.centerIn: parent
              width: 720
              scale: responsiveScale
              spacing: 16

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "CHOOSE AN OVERLAY WINDOW"
                color: root.foreground
                font.family: Style.fontFamily
                font.pixelSize: 23
                font.weight: Font.DemiBold
                font.letterSpacing: 1.5
              }

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Omatris will appear above the selected window and temporarily use the keyboard."
                color: root.muted
                font.family: Style.fontFamily
                font.pixelSize: 12
              }

              Column {
                width: parent.width
                spacing: 8

                Repeater {
                  model: root.overlayCandidates

                  delegate: Rectangle {
                    required property int index
                    required property var modelData
                    property bool selected: index === root.overlayPickerIndex
                    width: parent.width
                    height: 62
                    radius: Math.max(0, Style.cornerRadius * 0.5)
                    color: selected ? root.subtle : "transparent"
                    border.width: 1
                    border.color: selected ? root.accent : root.subtle

                    Row {
                      anchors.fill: parent
                      anchors.margins: 14
                      spacing: 14

                      Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 8
                        height: 30
                        radius: 2
                        color: root.accent
                      }

                      Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 150
                        spacing: 4
                        Text {
                          width: parent.width
                          text: modelData.title
                          elide: Text.ElideRight
                          color: root.foreground
                          font.family: Style.fontFamily
                          font.pixelSize: 14
                          font.weight: Font.DemiBold
                        }
                        Text {
                          width: parent.width
                          text: modelData.appClass
                          elide: Text.ElideRight
                          color: root.muted
                          font.family: Style.fontFamily
                          font.pixelSize: 10
                        }
                      }

                      Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.width + "×" + modelData.height + (modelData.floating ? "  FLOAT" : "  TILE")
                        color: root.muted
                        font.family: Style.fontFamily
                        font.pixelSize: 10
                      }
                    }

                    MouseArea {
                      id: targetMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onEntered: root.overlayPickerIndex = index
                      onClicked: {
                        root.overlayPickerIndex = index
                        root.startOverlay(modelData.toplevel)
                      }
                    }
                  }
                }
              }

              Text {
                visible: root.overlayNotice !== ""
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.overlayNotice
                color: root.urgent
                font.family: Style.fontFamily
                font.pixelSize: 11
              }

              Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 10
                ActionButton {
                  label: "REFRESH"
                  selected: root.overlayPickerIndex === root.overlayCandidates.length
                  onHovered: root.overlayPickerIndex = root.overlayCandidates.length
                  onClicked: {
                    root.overlayPickerIndex = root.overlayCandidates.length
                    Hyprland.refreshToplevels()
                    Qt.callLater(root.rebuildOverlayCandidates)
                    keyCatcher.forceActiveFocus()
                  }
                }
                ActionButton {
                  label: "BACK"
                  selected: root.overlayPickerIndex === root.overlayCandidates.length + 1
                  onHovered: root.overlayPickerIndex = root.overlayCandidates.length + 1
                  onClicked: {
                    root.overlayPickerIndex = root.overlayCandidates.length + 1
                    root.returnToMenu()
                  }
                }
              }

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Arrow keys choose  ·  Enter select  ·  R refresh  ·  Esc back"
                color: root.muted
                font.family: Style.fontFamily
                font.pixelSize: 10
              }
            }

            RowLayout {
              id: gameView
              property bool narrow: width < 700
              property bool short: height < 520
              visible: root.view === "game" && root.game !== null
              anchors.fill: parent
              spacing: narrow ? 12 : 24

              ColumnLayout {
                Layout.minimumWidth: gameView.narrow ? 105 : 140
                Layout.preferredWidth: gameView.narrow ? 115 : 150
                Layout.maximumWidth: 170
                Layout.fillHeight: true
                spacing: gameView.short ? 8 : 18

                Text {
                  text: root.game ? root.modeTitle(root.game.mode) : ""
                  color: root.accent
                  font.family: Style.fontFamily
                  font.pixelSize: 14
                  font.weight: Font.DemiBold
                  font.letterSpacing: 1
                }

                StatBlock { label: "SCORE"; value: { root.revision; return root.game ? String(root.game.score).padStart(7, "0") : "0000000" } }
                StatBlock { label: "BEST"; value: { root.revision; return root.game && root.game.mode !== "practice" ? String(root.highScoreForMode(root.game.mode)).padStart(7, "0") : "—" } }
                StatBlock { label: "LINES"; value: { root.revision; return root.game ? String(root.game.lines) : "0" } }
                StatBlock { label: "LEVEL"; value: { root.revision; return root.game ? String(root.game.level) : "1" } }

                Item { Layout.fillHeight: true }

                Text {
                  Layout.fillWidth: true
                  text: { root.revision; return root.game && root.game.lastEvent ? root.game.lastEvent : " " }
                  wrapMode: Text.WordWrap
                  color: root.muted
                  font.family: Style.fontFamily
                  font.pixelSize: 12
                }

                Text {
                  text: gameView.narrow ? "ESC · R" : "ESC modes  ·  R restart"
                  color: root.muted
                  font.family: Style.fontFamily
                  font.pixelSize: 11
                }
              }

              Item {
                Layout.minimumWidth: gameView.narrow ? 160 : 300
                Layout.preferredWidth: 360
                Layout.maximumWidth: 440
                Layout.fillWidth: true
                Layout.fillHeight: true

                Rectangle {
                  id: boardFrame
                  anchors.centerIn: parent
                  width: Math.min(parent.width, parent.height * 0.5)
                  height: width * 2
                  color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.72)
                  border.width: 1
                  border.color: root.outline
                  radius: Math.max(0, Style.cornerRadius * 0.45)

                  Grid {
                    anchors.fill: parent
                    anchors.margins: 5
                    columns: Game.WIDTH
                    rows: Game.HEIGHT
                    spacing: 0

                    Repeater {
                      model: Game.WIDTH * Game.HEIGHT

                      delegate: Rectangle {
                        required property int index
                        property int renderToken: root.revision
                        property int cellRow: Math.floor(index / Game.WIDTH)
                        property int cellColumn: index % Game.WIDTH
                        property string token: { renderToken; return root.cellToken(cellRow, cellColumn) }
                        property string kind: root.tokenKind(token)
                        property bool ghost: token.indexOf("ghost:") === 0
                        property bool edgeMode: kind !== "" && (root.blockStyle === "outline" || ghost)
                        property color edgeColor: {
                          if (ghost)
                            return Qt.rgba(root.pieceColor(kind).r, root.pieceColor(kind).g, root.pieceColor(kind).b, 0.55)
                          if (token.indexOf("locked:") === 0) return root.foreground
                          return root.pieceColor(kind)
                        }
                        width: (boardFrame.width - 10) / Game.WIDTH
                        height: (boardFrame.height - 10) / Game.HEIGHT
                        radius: 0
                        color: {
                          if (!kind) return root.subtle
                          if (ghost) return "transparent"
                          return root.blockStyle === "outline" ? root.blockInterior : root.pieceColor(kind)
                        }
                        border.width: kind ? 0 : 1
                        border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.035)

                        Rectangle {
                          visible: {
                            parent.renderToken
                            return parent.edgeMode && root.shouldDrawEdge(parent.token, root.cellToken(parent.cellRow - 1, parent.cellColumn))
                          }
                          anchors.left: parent.left
                          anchors.right: parent.right
                          anchors.top: parent.top
                          height: 2
                          color: parent.edgeColor
                        }

                        Rectangle {
                          visible: {
                            parent.renderToken
                            return parent.edgeMode && root.shouldDrawEdge(parent.token, root.cellToken(parent.cellRow + 1, parent.cellColumn))
                          }
                          anchors.left: parent.left
                          anchors.right: parent.right
                          anchors.bottom: parent.bottom
                          height: 2
                          color: parent.edgeColor
                        }

                        Rectangle {
                          visible: {
                            parent.renderToken
                            return parent.edgeMode && root.shouldDrawEdge(parent.token, root.cellToken(parent.cellRow, parent.cellColumn - 1))
                          }
                          anchors.left: parent.left
                          anchors.top: parent.top
                          anchors.bottom: parent.bottom
                          width: 2
                          color: parent.edgeColor
                        }

                        Rectangle {
                          visible: {
                            parent.renderToken
                            return parent.edgeMode && root.shouldDrawEdge(parent.token, root.cellToken(parent.cellRow, parent.cellColumn + 1))
                          }
                          anchors.right: parent.right
                          anchors.top: parent.top
                          anchors.bottom: parent.bottom
                          width: 2
                          color: parent.edgeColor
                        }
                      }
                    }
                  }

                  BoardEffects {
                    anchors.fill: parent
                    anchors.margins: 5
                    controller: root
                    game: root.game
                    revision: root.revision
                  }

                  Rectangle {
                    visible: { root.revision; return root.game && root.game.paused && root.game.status === "playing" }
                    anchors.fill: parent
                    radius: parent.radius
                    color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.88)

                    Column {
                      anchors.centerIn: parent
                      spacing: 14

                      Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "PAUSED"
                        color: root.foreground
                        font.family: Style.fontFamily
                        font.pixelSize: 26
                        font.weight: Font.DemiBold
                        font.letterSpacing: 2
                      }
                      Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Press P to continue"
                        color: root.muted
                        font.family: Style.fontFamily
                        font.pixelSize: 12
                      }
                    }
                  }
                }
              }

              ColumnLayout {
                visible: !gameView.narrow
                Layout.minimumWidth: 150
                Layout.preferredWidth: 160
                Layout.maximumWidth: 170
                Layout.fillHeight: true
                spacing: gameView.short ? 8 : 18

                PreviewBlock {
                  title: "NEXT"
                  piece: { root.revision; return root.game && root.game.queue.length ? root.game.queue[0] : "" }
                }

                PreviewBlock {
                  title: "HOLD"
                  piece: { root.revision; return root.game ? root.game.hold : "" }
                }

                Column {
                  spacing: 8

                  Text {
                    text: "BLOCK STYLE"
                    color: root.muted
                    font.family: Style.fontFamily
                    font.pixelSize: 10
                    font.letterSpacing: 1
                  }

                  Row {
                    spacing: 6
                    BlockStyleButton { label: "SOLID"; selected: root.blockStyle === "solid"; onClicked: { root.blockStyle = "solid"; root.refresh(); keyCatcher.forceActiveFocus() } }
                    BlockStyleButton { label: "OUTLINE"; selected: root.blockStyle === "outline"; onClicked: { root.blockStyle = "outline"; root.refresh(); keyCatcher.forceActiveFocus() } }
                  }
                }

                PracticeSpeedControl {
                  visible: root.game && root.game.mode === "practice"
                  value: { root.revision; return root.game && root.game.mode === "practice" ? root.game.practiceSpeed : 1.0 }
                  onSpeedSelected: function(speed) { root.setPracticeSpeed(speed) }
                }

                Item { Layout.fillHeight: true }

                Column {
                  visible: !gameView.short
                  spacing: 7
                  Text { text: "CONTROLS"; color: root.foreground; font.family: Style.fontFamily; font.pixelSize: 12; font.weight: Font.DemiBold }
                  Text { text: root.bindingSummary("left") + " / " + root.bindingSummary("right") + "  MOVE"; color: root.muted; font.family: Style.fontFamily; font.pixelSize: 10 }
                  Text { text: root.bindingSummary("down") + "  SOFT DROP"; color: root.muted; font.family: Style.fontFamily; font.pixelSize: 10 }
                  Text { text: root.bindingSummary("rotateLeft") + " / " + root.bindingSummary("rotateRight") + "  ROTATE"; color: root.muted; font.family: Style.fontFamily; font.pixelSize: 10 }
                  Text { text: root.bindingSummary("drop") + "  HARD DROP"; color: root.muted; font.family: Style.fontFamily; font.pixelSize: 10 }
                  Text { text: root.bindingSummary("hold") + "  HOLD"; color: root.muted; font.family: Style.fontFamily; font.pixelSize: 10 }
                  Text { text: root.bindingSummary("mute") + "  MUTE"; color: root.muted; font.family: Style.fontFamily; font.pixelSize: 10 }
                }
              }
            }

            Rectangle {
              id: resultView
              visible: {
                root.revision
                return root.view === "game" && root.game && root.game.status !== "playing"
              }
              anchors.fill: parent
              z: 10
              radius: Math.max(0, Style.cornerRadius * 0.65)
              color: Qt.rgba(root.surface.r, root.surface.g, root.surface.b, 0.97)
              border.width: 1
              border.color: root.outline

              Column {
                id: resultContent
                property real responsiveScale: root.scaleToFit(parent.width - 24, parent.height - 24, 430, implicitHeight)
                anchors.centerIn: parent
                width: 430
                scale: responsiveScale
                spacing: 20

                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: {
                    root.revision
                    return root.game && root.game.status === "won" ? "40 LINES COMPLETE" : "GAME OVER"
                  }
                  color: root.foreground
                  font.family: Style.fontFamily
                  font.pixelSize: 28
                  font.weight: Font.DemiBold
                  font.letterSpacing: 2
                }

                Row {
                  anchors.horizontalCenter: parent.horizontalCenter
                  spacing: 38
                  ResultStat { label: "SCORE"; value: { root.revision; return root.game ? String(root.game.score) : "0" } }
                  ResultStat { label: "LINES"; value: { root.revision; return root.game ? String(root.game.lines) : "0" } }
                  ResultStat { label: "LEVEL"; value: { root.revision; return root.game ? String(root.game.level) : "1" } }
                }

                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: root.game ? root.modeTitle(root.game.mode) : ""
                  color: root.muted
                  font.family: Style.fontFamily
                  font.pixelSize: 12
                  font.letterSpacing: 1
                }

                Text {
                  visible: { root.revision; return root.game && root.game.isNewHighScore }
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: "NEW LOCAL BEST"
                  color: root.accent
                  font.family: Style.fontFamily
                  font.pixelSize: 13
                  font.weight: Font.DemiBold
                  font.letterSpacing: 1.5
                }

                Row {
                  anchors.horizontalCenter: parent.horizontalCenter
                  spacing: 10
                  ActionButton {
                    label: "RESTART"
                    selected: root.resultIndex === 0
                    onHovered: root.resultIndex = 0
                    onClicked: { root.resultIndex = 0; root.activateResultSelection() }
                  }
                  ActionButton {
                    label: "MODES"
                    selected: root.resultIndex === 1
                    onHovered: root.resultIndex = 1
                    onClicked: { root.resultIndex = 1; root.activateResultSelection() }
                  }
                }

                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: "← → choose  ·  Enter select  ·  R restart  ·  Esc modes"
                  color: root.muted
                  font.family: Style.fontFamily
                  font.pixelSize: 11
                }
              }
            }

            Rectangle {
              id: tooSmallView
              visible: root.windowTooSmall
              anchors.fill: parent
              z: 100
              radius: Math.max(0, Style.cornerRadius * 0.65)
              color: root.surface
              border.width: 1
              border.color: root.urgent

              Column {
                anchors.centerIn: parent
                width: Math.max(1, Math.min(430, parent.width - 24))
                spacing: 12

                Text {
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  wrapMode: Text.WordWrap
                  text: "WINDOW TOO SMALL"
                  color: root.urgent
                  font.family: Style.fontFamily
                  font.pixelSize: 24
                  font.weight: Font.DemiBold
                  font.letterSpacing: 1.5
                }

                Text {
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  wrapMode: Text.WordWrap
                  text: "Resize Omatris to at least " + root.minimumUsableWidth
                    + " × " + root.minimumUsableHeight + " to continue."
                  color: root.foreground
                  font.family: Style.fontFamily
                  font.pixelSize: 14
                }

                Text {
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  text: Math.round(window.width) + " × " + Math.round(window.height) + " right now"
                  color: root.muted
                  font.family: Style.fontFamily
                  font.pixelSize: 12
                }
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
              }
            }
          }
        }
      }
    }
  }

  OverlayWindow {
    id: overlayWindow
    controller: root
  }

  Connections {
    target: Hyprland.toplevels
    function onValuesChanged() {
      if (root.overlayActive) Qt.callLater(root.syncOverlayTarget)
      else if (root.view === "overlayPicker") Qt.callLater(root.rebuildOverlayCandidates)
    }
  }

  Timer {
    interval: 140
    repeat: true
    running: root.overlayActive
    onTriggered: {
      Hyprland.refreshToplevels()
      Qt.callLater(root.syncOverlayTarget)
    }
  }

  Timer {
    interval: { root.revision; return root.game ? Game.dropInterval(root.game) : 700 }
    running: {
      root.revision
      return (window.visible || root.overlayActive) && root.view === "game" && root.game
          && root.game.status === "playing" && !root.game.paused && !root.windowTooSmall
          && (root.game.mode !== "practice" || root.game.practiceSpeed > 0)
    }
    repeat: true
    onTriggered: {
      Game.tick(root.game)
      root.refresh()
    }
  }

  Timer {
    interval: 50
    running: {
      root.revision
      return (window.visible || root.overlayActive) && root.view === "game" && root.game
          && root.game.status === "playing" && !root.game.paused && !root.windowTooSmall
          && root.game.grounded
    }
    repeat: true
    onTriggered: {
      Game.advanceLockDelay(root.game, interval)
      root.refresh()
    }
  }

  Timer {
    id: rotationRepeat
    onTriggered: {
      if (!root.game || root.game.status !== "playing" || root.game.paused
          || root.windowTooSmall || root.rotationDirection === 0) {
        stop()
        return
      }
      root.perform(root.rotationDirection < 0 ? "rotateLeft" : "rotateRight")
      interval = 280
      repeat = true
      restart()
    }
  }

  Timer {
    id: horizontalRepeat
    onTriggered: {
      if (!root.game || root.game.status !== "playing" || root.game.paused
          || root.windowTooSmall || root.horizontalDirection === 0) {
        stop()
        return
      }
      root.perform(root.horizontalDirection < 0 ? "left" : "right")
      interval = 45
      repeat = true
      restart()
    }
  }

  Timer {
    id: softDropRepeat
    onTriggered: {
      if (!root.game || root.game.status !== "playing" || root.game.paused
          || root.windowTooSmall || !root.downHeld) {
        stop()
        return
      }
      root.perform("down")
      interval = 45
      repeat = true
      restart()
    }
  }

  component StatBlock: Column {
    required property string label
    required property string value
    spacing: 4
    Text { text: parent.label; color: root.muted; font.family: Style.fontFamily; font.pixelSize: 10; font.letterSpacing: 1 }
    Text { text: parent.value; color: root.foreground; font.family: Style.fontFamily; font.pixelSize: 21; font.weight: Font.DemiBold }
  }

  component ResultStat: Column {
    required property string label
    required property string value
    spacing: 5
    Text { anchors.horizontalCenter: parent.horizontalCenter; text: parent.label; color: root.muted; font.family: Style.fontFamily; font.pixelSize: 10; font.letterSpacing: 1 }
    Text { anchors.horizontalCenter: parent.horizontalCenter; text: parent.value; color: root.accent; font.family: Style.fontFamily; font.pixelSize: 24; font.weight: Font.DemiBold }
  }

  component PracticeSpeedControl: Column {
    id: speedControl
    required property real value
    signal speedSelected(real speed)
    width: 150
    spacing: 8

    Row {
      width: parent.width

      Text {
        text: "DROP SPEED"
        color: root.muted
        font.family: Style.fontFamily
        font.pixelSize: 10
        font.letterSpacing: 1
      }

      Item { width: parent.width - 98; height: 1 }

      Text {
        text: speedControl.value === 0 ? "OFF" : speedControl.value.toFixed(1) + "×"
        color: root.accent
        font.family: Style.fontFamily
        font.pixelSize: 10
        font.weight: Font.DemiBold
      }
    }

    Item {
      width: parent.width
      height: 20

      Rectangle {
        id: speedTrack
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: 3
        radius: 2
        color: root.subtle

        Rectangle {
          width: parent.width * Math.max(0, Math.min(1, speedControl.value / 1.5))
          height: parent.height
          radius: parent.radius
          color: root.accent
        }

        Rectangle {
          width: 12
          height: 12
          radius: 6
          x: (speedTrack.width - width) * Math.max(0, Math.min(1, speedControl.value / 1.5))
          anchors.verticalCenter: parent.verticalCenter
          color: root.foreground
          border.width: 2
          border.color: root.accent
        }
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor

        function selectAt(mouseX) {
          var ratio = Math.max(0, Math.min(1, mouseX / width))
          speedControl.speedSelected(Math.round(ratio * 15) / 10)
        }

        onPressed: function(mouse) { selectAt(mouse.x) }
        onPositionChanged: function(mouse) { if (pressed) selectAt(mouse.x) }
        onReleased: keyCatcher.forceActiveFocus()
      }
    }

    Row {
      width: parent.width
      Text { text: "OFF"; color: root.muted; font.family: Style.fontFamily; font.pixelSize: 9 }
      Item { width: parent.width - 50; height: 1 }
      Text { text: "1.5×"; color: root.muted; font.family: Style.fontFamily; font.pixelSize: 9 }
    }
  }

  component VolumeSetting: Rectangle {
    id: volumeSetting
    required property string label
    required property real value
    property bool selected: false
    property bool editing: false
    signal volumeSelected(real value)
    signal hovered

    width: 373
    height: 66
    radius: Math.max(0, Style.cornerRadius * 0.45)
    color: selected ? root.subtle : "transparent"
    border.width: editing ? 2 : 1
    border.color: selected ? root.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.09)

    Text {
      anchors.left: parent.left
      anchors.leftMargin: 13
      anchors.top: parent.top
      anchors.topMargin: 10
      text: volumeSetting.label
      color: root.foreground
      font.family: Style.fontFamily
      font.pixelSize: 10
      font.weight: Font.DemiBold
      font.letterSpacing: 0.8
    }

    Text {
      anchors.right: parent.right
      anchors.rightMargin: 13
      anchors.top: parent.top
      anchors.topMargin: 10
      text: (volumeSetting.editing ? "←  " : "") + Math.round(volumeSetting.value * 100) + "%" + (volumeSetting.editing ? "  →" : "")
      color: root.accent
      font.family: Style.fontFamily
      font.pixelSize: 10
      font.weight: Font.DemiBold
    }

    Item {
      id: volumeTrackArea
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.leftMargin: 13
      anchors.rightMargin: 13
      anchors.bottomMargin: 10
      height: 22

      Rectangle {
        id: volumeTrack
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: 5
        radius: height / 2
        color: root.subtle

        Rectangle {
          width: parent.width * volumeSetting.value
          height: parent.height
          radius: parent.radius
          color: root.accent
        }

        Rectangle {
          width: 14
          height: 14
          radius: 7
          antialiasing: true
          x: (volumeTrack.width - width) * volumeSetting.value
          anchors.verticalCenter: parent.verticalCenter
          color: root.foreground
          border.width: 2
          border.color: root.accent
        }
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: volumeSetting.hovered()

        function selectAt(mouseX) {
          volumeSetting.volumeSelected(Math.max(0, Math.min(1, mouseX / width)))
        }

        onPressed: function(mouse) { selectAt(mouse.x) }
        onPositionChanged: function(mouse) { if (pressed) selectAt(mouse.x) }
        onReleased: keyCatcher.forceActiveFocus()
      }
    }
  }

  component BindingButton: Rectangle {
    id: bindingButton
    required property string label
    property bool selected: false
    property bool listening: false
    signal clicked

    width: 78
    height: 28
    radius: Math.max(0, Style.cornerRadius * 0.32)
    color: listening ? root.accent : selected ? root.subtle : "transparent"
    border.width: 1
    border.color: listening || selected ? root.accent : root.outline

    Text {
      anchors.centerIn: parent
      text: bindingButton.listening ? "PRESS KEY" : bindingButton.label
      color: bindingButton.listening ? root.background : bindingButton.selected ? root.foreground : root.muted
      font.family: Style.fontFamily
      font.pixelSize: bindingButton.listening ? 8 : 9
      font.weight: Font.DemiBold
      elide: Text.ElideRight
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: bindingButton.clicked()
    }
  }

  component ActionButton: Rectangle {
    required property string label
    property bool selected: false
    signal clicked
    signal hovered
    width: 128
    height: 40
    radius: Math.max(0, Style.cornerRadius * 0.4)
    color: selected ? root.subtle : "transparent"
    border.width: 1
    border.color: selected ? root.accent : root.outline

    Text {
      anchors.centerIn: parent
      text: parent.label
      color: root.foreground
      font.family: Style.fontFamily
      font.pixelSize: 11
      font.weight: Font.DemiBold
      font.letterSpacing: 1
    }

    MouseArea {
      id: actionMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: parent.hovered()
      onClicked: parent.clicked()
    }
  }

  component PreviewBlock: Column {
    required property string title
    required property string piece
    spacing: 8

    Text {
      text: parent.title
      color: root.muted
      font.family: Style.fontFamily
      font.pixelSize: 10
      font.letterSpacing: 1
    }

    Rectangle {
      width: 150
      height: 112
      radius: Math.max(0, Style.cornerRadius * 0.45)
      color: root.subtle
      border.width: 1
      border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)

      Grid {
        anchors.centerIn: parent
        columns: 4
        rows: 4
        spacing: 0

        Repeater {
          model: 16
          delegate: Rectangle {
            required property int index
            property int previewRow: Math.floor(index / 4)
            property int previewColumn: index % 4
            property bool filled: Game.previewCell(piece, previewRow, previewColumn)
            property color previewColor: root.pieceColor(piece)
            width: 18
            height: 18
            radius: 0
            color: !filled ? "transparent" : root.blockStyle === "outline" ? root.blockInterior : previewColor

            Rectangle { visible: parent.filled && root.blockStyle === "outline" && !Game.previewCell(piece, parent.previewRow - 1, parent.previewColumn); anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; height: 2; color: parent.previewColor }
            Rectangle { visible: parent.filled && root.blockStyle === "outline" && !Game.previewCell(piece, parent.previewRow + 1, parent.previewColumn); anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 2; color: parent.previewColor }
            Rectangle { visible: parent.filled && root.blockStyle === "outline" && !Game.previewCell(piece, parent.previewRow, parent.previewColumn - 1); anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom; width: 2; color: parent.previewColor }
            Rectangle { visible: parent.filled && root.blockStyle === "outline" && !Game.previewCell(piece, parent.previewRow, parent.previewColumn + 1); anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom; width: 2; color: parent.previewColor }
          }
        }
      }
    }
  }

  component BlockStyleButton: Rectangle {
    required property string label
    required property bool selected
    signal clicked

    width: 72
    height: 28
    radius: Math.max(0, Style.cornerRadius * 0.35)
    color: selected ? root.subtle : "transparent"
    border.width: 1
    border.color: selected ? root.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)

    Text {
      anchors.centerIn: parent
      text: parent.label
      color: parent.selected ? root.accent : root.muted
      font.family: Style.fontFamily
      font.pixelSize: 9
      font.weight: Font.DemiBold
      font.letterSpacing: 0.5
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: parent.clicked()
    }
  }
}
