import Quickshell
import QtQuick
import "shared"

ShellRoot {
  FloatingWindow {
    id: win
    title: "Proteus Settings"
    visible: true
    implicitWidth: 820
    implicitHeight: 560
    minimumSize: Qt.size(640, 420)
    color: Theme.bgElevated

    onClosed: Qt.quit()

    Settings {
      anchors.fill: parent
      anchors.margins: 0
    }
  }

  IdentifyFlash {}
}
