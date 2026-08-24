import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import "Game.js" as Game

PanelWindow {
  id: overlay

  required property var controller

  readonly property var game: controller ? controller.game : null
  readonly property int revision: controller ? controller.revision : 0
  readonly property var target: controller ? controller.overlayTarget : null
  readonly property var targetIpc: target ? target.lastIpcObject : null
  readonly property var targetMonitor: target ? target.monitor : null
  readonly property real targetX: targetIpc && targetIpc.at ? targetIpc.at[0] - (targetMonitor ? targetMonitor.x : 0) : 0
  readonly property real targetY: targetIpc && targetIpc.at ? targetIpc.at[1] - (targetMonitor ? targetMonitor.y : 0) : 0
  readonly property real targetWidth: targetIpc && targetIpc.size ? targetIpc.size[0] : 0
  readonly property real targetHeight: targetIpc && targetIpc.size ? targetIpc.size[1] : 0
  readonly property real boardWidth: Math.max(0, Math.min(targetWidth - 12, (targetHeight - 12) / 2))
  readonly property real boardHeight: boardWidth * 2

  visible: controller && controller.overlayActive
  screen: controller ? controller.overlayScreen : null
  color: "transparent"
  surfaceFormat.opaque: false
  exclusionMode: ExclusionMode.Ignore

  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }

  WlrLayershell.namespace: "omatris-overlay"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: visible && !controller.overlayTestingNoFocus
    ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

  // The selected application remains visible and receives pointer input.
  // Omatris temporarily owns keyboard focus until Escape ends the session.
  mask: Region {}

  onBackingWindowVisibleChanged: {
    if (backingWindowVisible) Qt.callLater(function() { overlayKeys.forceActiveFocus() })
  }

  FocusScope {
    id: overlayKeys
    anchors.fill: parent
    focus: true

    Keys.onPressed: function(event) { controller.handleGameKeyPressed(event, true) }
    Keys.onReleased: function(event) { controller.handleGameKeyReleased(event) }

    Rectangle {
      x: overlay.targetX
      y: overlay.targetY
      width: overlay.targetWidth
      height: overlay.targetHeight
      color: "transparent"
      border.width: 1
      border.color: Qt.rgba(controller.accent.r, controller.accent.g, controller.accent.b, 0.34)

      Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 2
        color: controller.accent
        opacity: 0.72
      }
    }

    Item {
      id: board
      x: overlay.targetX + (overlay.targetWidth - width) / 2
      y: overlay.targetY + overlay.targetHeight - height
      width: overlay.boardWidth
      height: overlay.boardHeight
      clip: true

      Grid {
        anchors.fill: parent
        columns: Game.WIDTH
        rows: Game.HEIGHT
        spacing: 0

        Repeater {
          model: Game.WIDTH * Game.HEIGHT

          delegate: Rectangle {
            required property int index
            property int renderToken: overlay.revision
            property int cellRow: Math.floor(index / Game.WIDTH)
            property int cellColumn: index % Game.WIDTH
            property string token: { renderToken; return controller.cellToken(cellRow, cellColumn) }
            property string kind: controller.tokenKind(token)
            property bool ghost: token.indexOf("ghost:") === 0
            property bool edgeMode: kind !== "" && (controller.blockStyle === "outline" || ghost)
            property color edgeColor: {
              if (ghost) {
                var ghostColor = controller.pieceColor(kind)
                return Qt.rgba(ghostColor.r, ghostColor.g, ghostColor.b, 0.72)
              }
              if (token.indexOf("locked:") === 0) return controller.foreground
              return controller.pieceColor(kind)
            }

            width: board.width / Game.WIDTH
            height: board.height / Game.HEIGHT
            color: {
              if (!kind || ghost) return "transparent"
              if (controller.blockStyle === "outline") return controller.blockInterior
              var piece = controller.pieceColor(kind)
              return Qt.rgba(piece.r, piece.g, piece.b, 0.88)
            }

            Rectangle {
              visible: {
                parent.renderToken
                return parent.edgeMode && controller.shouldDrawEdge(parent.token, controller.cellToken(parent.cellRow - 1, parent.cellColumn))
              }
              anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
              height: 2
              color: parent.edgeColor
            }
            Rectangle {
              visible: {
                parent.renderToken
                return parent.edgeMode && controller.shouldDrawEdge(parent.token, controller.cellToken(parent.cellRow + 1, parent.cellColumn))
              }
              anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
              height: 2
              color: parent.edgeColor
            }
            Rectangle {
              visible: {
                parent.renderToken
                return parent.edgeMode && controller.shouldDrawEdge(parent.token, controller.cellToken(parent.cellRow, parent.cellColumn - 1))
              }
              anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
              width: 2
              color: parent.edgeColor
            }
            Rectangle {
              visible: {
                parent.renderToken
                return parent.edgeMode && controller.shouldDrawEdge(parent.token, controller.cellToken(parent.cellRow, parent.cellColumn + 1))
              }
              anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom
              width: 2
              color: parent.edgeColor
            }
          }
        }
      }
    }

    Rectangle {
      x: overlay.targetX + 12
      y: overlay.targetY + 12
      width: Math.min(250, Math.max(170, overlay.targetWidth - 24))
      height: 58
      radius: Math.max(0, Style.cornerRadius * 0.45)
      color: Qt.rgba(controller.background.r, controller.background.g, controller.background.b, 0.82)
      border.width: 1
      border.color: Qt.rgba(controller.accent.r, controller.accent.g, controller.accent.b, 0.35)

      Column {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 5

        Text {
          text: {
            overlay.revision
            return game ? "OVERLAY  ·  " + String(game.score).padStart(7, "0") + "  ·  " + game.lines + " LINES" : "OVERLAY"
          }
          color: controller.foreground
          font.family: Style.fontFamily
          font.pixelSize: 11
          font.weight: Font.DemiBold
          font.letterSpacing: 0.7
        }
        Text {
          text: "ESC exit  ·  R restart  ·  C hold"
          color: controller.muted
          font.family: Style.fontFamily
          font.pixelSize: 9
        }
      }
    }

    Rectangle {
      visible: {
        overlay.revision
        return game && (game.paused || game.status !== "playing")
      }
      x: overlay.targetX + Math.max(12, (overlay.targetWidth - width) / 2)
      y: overlay.targetY + Math.max(12, (overlay.targetHeight - height) / 2)
      width: Math.min(360, overlay.targetWidth - 24)
      height: 190
      radius: Math.max(0, Style.cornerRadius * 0.65)
      color: Qt.rgba(controller.background.r, controller.background.g, controller.background.b, 0.94)
      border.width: 1
      border.color: controller.accent

      Column {
        anchors.centerIn: parent
        spacing: 12
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: {
            overlay.revision
            if (!game) return ""
            if (game.paused) return "PAUSED"
            return game.status === "won" ? "COMPLETE" : "GAME OVER"
          }
          color: controller.foreground
          font.family: Style.fontFamily
          font.pixelSize: 23
          font.weight: Font.DemiBold
          font.letterSpacing: 1.5
        }
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: {
            overlay.revision
            return game ? "SCORE " + game.score + "  ·  LINES " + game.lines : ""
          }
          color: controller.accent
          font.family: Style.fontFamily
          font.pixelSize: 14
          font.weight: Font.DemiBold
        }
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: game && game.paused ? "P continue  ·  Esc exit" : "R restart  ·  Esc exit"
          color: controller.muted
          font.family: Style.fontFamily
          font.pixelSize: 10
        }
      }
    }
  }
}
