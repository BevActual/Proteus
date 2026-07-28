import Quickshell
import Quickshell.Wayland
import QtQuick

ShellRoot {
  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: win
      required property var modelData
      screen: modelData

      exclusionMode: ExclusionMode.Ignore
      exclusiveZone: 0
      color: "transparent"

      anchors {
        top: true
        left: true
        right: true
        bottom: true
      }

      Component.onCompleted: {
        if (win.WlrLayershell != null) {
          win.WlrLayershell.layer = WlrLayer.Background
          win.WlrLayershell.namespace = "proteus-bg"
        }
      }

      WallpaperSurface {
        anchors.fill: parent
      }
    }
  }
}
