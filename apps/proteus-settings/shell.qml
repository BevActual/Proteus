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

    // Show the window shell immediately; build the heavy UI off the first frame.
    Loader {
      id: settingsLoader
      anchors.fill: parent
      asynchronous: true
      source: "Settings.qml"
      onLoaded: {
        if (item) {
          item.anchors.fill = settingsLoader
        }
      }
    }
  }
}
