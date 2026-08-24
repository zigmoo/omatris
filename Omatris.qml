import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import "Game.js" as Game

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
    overlayActive = false
    overlayTarget = null
    overlayTargetAddress = ""
    resetHeldInputs()
    closingFromHost = true
    window.visible = false
    closingFromHost = false
  }

  function requestClose() {
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
    revision += 1
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

  function modeTitle(mode) {
    if (mode === "classic") return "CLASSIC · 40 LINES"
    if (mode === "endless") return "ENDLESS"
    if (mode === "overlay") return "OVERLAY"
    return "PRACTICE"
  }

  function activateMenuSelection() {
    var modes = ["classic", "endless", "practice", "overlay"]
    var mode = modes[Math.max(0, Math.min(menuIndex, modes.length - 1))]
    if (mode === "overlay") showOverlayPicker()
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
    if (action === "left") Game.move(game, -1, 0)
    else if (action === "right") Game.move(game, 1, 0)
    else if (action === "down") Game.move(game, 0, 1)
    else if (action === "rotateRight") Game.rotate(game, 1)
    else if (action === "rotateLeft") Game.rotate(game, -1)
    else if (action === "drop") Game.hardDrop(game)
    else if (action === "hold") Game.hold(game)
    refresh()
  }

  function handleGameKeyPressed(event, fromOverlay) {
    if (event.key === Qt.Key_Escape) {
      if (fromOverlay || overlayActive) stopOverlay("")
      else if (view === "game" || view === "overlayPicker") returnToMenu()
      else requestClose()
      event.accepted = true
      return
    }

    if (view === "menu") {
      if (!event.isAutoRepeat && (event.key === Qt.Key_Up || event.key === Qt.Key_Left)) {
        menuIndex = (menuIndex + 3) % 4
        event.accepted = true
      } else if (!event.isAutoRepeat && (event.key === Qt.Key_Down || event.key === Qt.Key_Right)) {
        menuIndex = (menuIndex + 1) % 4
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
      } else if (event.key === Qt.Key_R) {
        resultIndex = 0
        activateResultSelection()
      } else return
      event.accepted = true
      return
    }

    if (event.key === Qt.Key_Left || event.key === Qt.Key_A || event.key === Qt.Key_H) {
      if (!event.isAutoRepeat) pressHorizontal(-1)
    } else if (event.key === Qt.Key_Right || event.key === Qt.Key_D || event.key === Qt.Key_L) {
      if (!event.isAutoRepeat) pressHorizontal(1)
    } else if (event.key === Qt.Key_Down || event.key === Qt.Key_S || event.key === Qt.Key_J) {
      if (!event.isAutoRepeat) {
        downHeld = true
        perform("down")
        softDropRepeat.interval = 100
        softDropRepeat.repeat = false
        softDropRepeat.restart()
      }
    } else if (event.key === Qt.Key_X) {
      if (!event.isAutoRepeat) pressRotation(1)
    } else if (event.key === Qt.Key_Z) {
      if (!event.isAutoRepeat) pressRotation(-1)
    } else if (event.key === Qt.Key_Space) perform("drop")
    else if (event.key === Qt.Key_C || event.key === Qt.Key_Shift) perform("hold")
    else if (event.key === Qt.Key_B) toggleBlockStyle()
    else if (event.key === Qt.Key_P) { game.paused = !game.paused; refresh() }
    else if (event.key === Qt.Key_R) {
      if (overlayActive) {
        game = Game.newGame("overlay")
        resetHeldInputs()
        refresh()
      } else startGame(game.mode)
    } else return
    event.accepted = true
  }

  function handleGameKeyReleased(event) {
    if (event.isAutoRepeat) return
    if (event.key === Qt.Key_Left || event.key === Qt.Key_A || event.key === Qt.Key_H) {
      releaseHorizontal(-1)
      event.accepted = true
    } else if (event.key === Qt.Key_Right || event.key === Qt.Key_D || event.key === Qt.Key_L) {
      releaseHorizontal(1)
      event.accepted = true
    } else if (event.key === Qt.Key_Down || event.key === Qt.Key_S || event.key === Qt.Key_J) {
      downHeld = false
      softDropRepeat.stop()
      event.accepted = true
    } else if (event.key === Qt.Key_X) {
      releaseRotation(1)
      event.accepted = true
    } else if (event.key === Qt.Key_Z) {
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
    minimumSize: Qt.size(900, 680)

    onVisibleChanged: {
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
          anchors.margins: Math.max(18, Math.min(38, parent.width * 0.04))
          radius: Math.max(0, Style.cornerRadius)
          color: root.surface
          border.width: 1
          border.color: root.outline

          Item {
            anchors.fill: parent
            anchors.margins: 28

            Column {
              id: menuView
              visible: root.view === "menu"
              anchors.centerIn: parent
              width: Math.min(660, parent.width)
              spacing: 22

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
                    { mode: "classic", title: "CLASSIC", detail: "Clear 40 lines · speed increases every 10" },
                    { mode: "endless", title: "ENDLESS", detail: "Play until top-out · chase a high score" },
                    { mode: "practice", title: "PRACTICE", detail: "Adjustable gravity · the board resets instead of ending" },
                    { mode: "overlay", title: "OVERLAY  ·  EXPERIMENTAL", detail: "Play over a window on this workspace" }
                  ]

                  delegate: Rectangle {
                    required property int index
                    required property var modelData
                    property bool selected: index === root.menuIndex
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
                          : modelData.mode === "overlay" ? root.foreground : root.muted
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
                text: "↑ ↓ choose  ·  Enter select  ·  O overlay"
                color: root.muted
                font.family: Style.fontFamily
                font.pixelSize: 12
              }
            }

            Column {
              id: overlayPickerView
              visible: root.view === "overlayPicker"
              anchors.centerIn: parent
              width: Math.min(720, parent.width)
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
              visible: root.view === "game" && root.game !== null
              anchors.fill: parent
              spacing: 24

              ColumnLayout {
                Layout.minimumWidth: 140
                Layout.preferredWidth: 150
                Layout.maximumWidth: 170
                Layout.fillHeight: true
                spacing: 18

                Text {
                  text: root.game ? root.modeTitle(root.game.mode) : ""
                  color: root.accent
                  font.family: Style.fontFamily
                  font.pixelSize: 14
                  font.weight: Font.DemiBold
                  font.letterSpacing: 1
                }

                StatBlock { label: "SCORE"; value: { root.revision; return root.game ? String(root.game.score).padStart(7, "0") : "0000000" } }
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
                  text: "ESC modes  ·  R restart"
                  color: root.muted
                  font.family: Style.fontFamily
                  font.pixelSize: 11
                }
              }

              Item {
                Layout.minimumWidth: 300
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
                Layout.minimumWidth: 150
                Layout.preferredWidth: 160
                Layout.maximumWidth: 170
                Layout.fillHeight: true
                spacing: 18

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
                  spacing: 7
                  Text { text: "CONTROLS"; color: root.foreground; font.family: Style.fontFamily; font.pixelSize: 12; font.weight: Font.DemiBold }
                  Text { text: "← →  MOVE"; color: root.muted; font.family: Style.fontFamily; font.pixelSize: 11 }
                  Text { text: "↓     SOFT DROP"; color: root.muted; font.family: Style.fontFamily; font.pixelSize: 11 }
                  Text { text: "Z / X ROTATE"; color: root.muted; font.family: Style.fontFamily; font.pixelSize: 11 }
                  Text { text: "SPACE HARD DROP"; color: root.muted; font.family: Style.fontFamily; font.pixelSize: 11 }
                  Text { text: "C     HOLD"; color: root.muted; font.family: Style.fontFamily; font.pixelSize: 11 }
                  Text { text: "B     BLOCK STYLE"; color: root.muted; font.family: Style.fontFamily; font.pixelSize: 11 }
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
                anchors.centerIn: parent
                width: Math.min(430, parent.width - 48)
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
          && root.game.status === "playing" && !root.game.paused
          && (root.game.mode !== "practice" || root.game.practiceSpeed > 0)
    }
    repeat: true
    onTriggered: {
      Game.tick(root.game)
      root.refresh()
    }
  }

  Timer {
    id: rotationRepeat
    onTriggered: {
      if (!root.game || root.game.status !== "playing" || root.game.paused || root.rotationDirection === 0) {
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
      if (!root.game || root.game.status !== "playing" || root.game.paused || root.horizontalDirection === 0) {
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
      if (!root.game || root.game.status !== "playing" || root.game.paused || !root.downHeld) {
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
