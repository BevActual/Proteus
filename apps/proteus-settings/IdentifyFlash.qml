import Quickshell
import Quickshell.Hyprland
import QtQuick
import "shared"

// Fullscreen border flash on the named Hyprland monitor (Settings → Displays → Identify).
Variants {
  model: Quickshell.screens

  PanelWindow {
    id: flashWin
    required property var modelData
    screen: modelData

    readonly property var hyprMon: Hyprland.monitorFor(modelData)
    readonly property bool isTarget: Config.identifyActive
        && !!hyprMon
        && hyprMon.name === Config.identifyTarget

    visible: isTarget
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    anchors {
      top: true
      left: true
      right: true
      bottom: true
    }

    Rectangle {
      id: veil
      anchors.fill: parent
      color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.2)
      border.width: Math.max(12, Math.round(Math.min(width, height) * 0.02))
      border.color: Theme.accent
      opacity: 0

      Text {
        anchors.centerIn: parent
        text: Config.identifyTarget
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: 28
        font.bold: true
        style: Text.Outline
        styleColor: "#000000"
      }

      SequentialAnimation {
        running: flashWin.isTarget
        loops: 2
        NumberAnimation {
          target: veil
          property: "opacity"
          from: 0.3
          to: 1
          duration: 300
        }
        NumberAnimation {
          target: veil
          property: "opacity"
          from: 1
          to: 0.4
          duration: 300
        }
      }
    }
  }
}
