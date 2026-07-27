import Quickshell
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts
import "../shared"
import "desktop"

Scope {
  id: root

  GlobalShortcut {
    appid: "proteus"
    name: "launcher"
    description: "Toggle Proteus app launcher"
    onPressed: ShellState.toggleLauncher()
  }

  GlobalShortcut {
    appid: "proteus"
    name: "settings"
    description: "Open Proteus Settings"
    onPressed: ShellState.openSettings()
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: bar
      required property var modelData
      screen: modelData

      anchors {
        top: true
        left: true
        right: true
      }

      implicitHeight: Theme.barHeight
      color: Theme.bgPanel
      exclusionMode: ExclusionMode.Auto

      Rectangle {
        anchors.fill: parent
        color: Theme.bgPanel

        Rectangle {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: 1
          color: Theme.border
        }

        // Zones: launcher | workspaces | title | clock + settings
        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: Theme.spaceMd
          anchors.rightMargin: Theme.spaceMd
          spacing: Theme.spaceMd

          // Left zone — launcher
          Rectangle {
            Layout.preferredWidth: 34
            Layout.preferredHeight: 28
            radius: Theme.radiusSm
            color: launchMa.containsMouse || ShellState.launcherOpen ? Theme.accentSoft : "transparent"
            border.width: 1
            border.color: ShellState.launcherOpen ? Theme.accent : Theme.border

            Text {
              anchors.centerIn: parent
              text: "P"
              color: Theme.accent
              font.family: Theme.fontFamily
              font.pixelSize: 14
              font.bold: true
            }

            MouseArea {
              id: launchMa
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: ShellState.toggleLauncher()
            }
          }

          Workspaces {}

          // Center zone — active window title
          Text {
            Layout.fillWidth: true
            text: ActiveWindow.text
            color: Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
          }

          // Right zone — clock + settings
          Text {
            text: Time.text
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            verticalAlignment: Text.AlignVCenter
          }

          Rectangle {
            Layout.preferredWidth: 28
            Layout.preferredHeight: 28
            radius: Theme.radiusSm
            color: settingsMa.containsMouse ? Theme.accentSoft : "transparent"
            border.width: 1
            border.color: settingsMa.containsMouse ? Theme.accent : Theme.border

            Text {
              anchors.centerIn: parent
              text: "⚙"
              color: Theme.textDim
              font.pixelSize: 14
            }

            MouseArea {
              id: settingsMa
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: ShellState.openSettings()
            }
          }
        }
      }
    }
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: dockWin
      required property var modelData
      screen: modelData
      visible: Config.dockEnabled

      anchors {
        left: true
        right: true
        bottom: true
      }

      implicitHeight: Config.dockEnabled ? 100 : 0
      exclusiveZone: Config.dockEnabled ? Theme.dockExclusive : 0
      exclusionMode: ExclusionMode.Auto
      color: "transparent"

      Dock {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.spaceSm
        visible: Config.dockEnabled
      }
    }
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: launcherWin
      required property var modelData
      screen: modelData

      readonly property bool isFocused: {
        const mon = Hyprland.monitorFor(modelData)
        return mon ? mon.focused : (modelData === Quickshell.screens[0])
      }

      visible: ShellState.launcherOpen && isFocused
      exclusionMode: ExclusionMode.Ignore
      color: "transparent"

      anchors {
        top: true
        left: true
        right: true
        bottom: true
      }

      Rectangle {
        anchors.fill: parent
        color: "#a00a0e12"
        MouseArea {
          anchors.fill: parent
          onClicked: ShellState.closeLauncher()
        }
      }

      Launcher {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Math.max(80, parent.height * 0.12)
        width: Math.min(520, parent.width - 48)
        height: Math.min(420, parent.height - 160)
      }
    }
  }
}
