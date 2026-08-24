import QtQuick
import Quickshell
import Quickshell.Hyprland

ShellRoot {
  readonly property bool overlaySmoke: Quickshell.env("OMATRIS_DEV_OVERLAY") === "1"

  Omatris {
    id: game
    overlayTestingNoFocus: Quickshell.env("OMATRIS_DEV_NO_FOCUS") === "1"
    shell: QtObject {
      function hide(pluginId) { Qt.quit() }
    }
    Component.onCompleted: {
      game.open("{}")
      if (overlaySmoke) game.showOverlayPicker()
    }
  }

  Timer {
    interval: 250
    repeat: true
    running: overlaySmoke
    onTriggered: {
      Hyprland.refreshToplevels()
      game.rebuildOverlayCandidates()
      if (game.overlayCandidates.length === 0) return
      stop()
      game.startOverlay(game.overlayCandidates[0].toplevel)
    }
  }
}
