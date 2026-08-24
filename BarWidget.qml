import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root

  moduleName: "com.80kv.omatris"

  readonly property bool gameOpen: bar && bar.shell
    ? bar.shell.openPanelIds[moduleName] === true
    : false

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    active: root.gameOpen
    tooltipText: "Omatris"

    iconComponent: Component {
      Item {
        Repeater {
          model: [
            { column: 1, row: 0 },
            { column: 0, row: 1 },
            { column: 1, row: 1 },
            { column: 2, row: 1 }
          ]

          delegate: Rectangle {
            required property var modelData
            width: parent.width / 3 - 1
            height: parent.height / 3 - 1
            x: modelData.column * parent.width / 3
            y: modelData.row * parent.height / 3 + parent.height / 6
            radius: Math.max(1, Style.cornerRadius * 0.12)
            color: button.active ? button.activeColor : button.foreground
          }
        }
      }
    }

    onPressed: function(mouseButton) {
      if (mouseButton !== Qt.LeftButton || !root.bar || !root.bar.shell) return
      root.bar.shell.toggle(root.moduleName, "{}")
    }
  }
}
