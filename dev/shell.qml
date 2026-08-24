import QtQuick
import Quickshell

ShellRoot {
  Omatris {
    id: game
    shell: QtObject {
      function hide(pluginId) { Qt.quit() }
    }
    Component.onCompleted: game.open("{}")
  }
}
