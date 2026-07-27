import Quickshell
import QtQuick
import QtQuick.Layouts
import "../shared"

ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: 10

  Text {
    text: "Proteus desktop environment\nBevington Systems"
    color: Theme.text
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSize
  }
  Text {
    text: "Arch Linux guest · Hyprland · Quickshell"
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 12
  }

  Rectangle {
    Layout.fillWidth: true
    Layout.topMargin: 4
    Layout.preferredHeight: hwCol.implicitHeight + 24
    radius: Theme.radiusMd
    color: Theme.bgPanel
    border.width: 1
    border.color: Theme.border

    ColumnLayout {
      id: hwCol
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Theme.spaceMd
      spacing: Theme.spaceSm

      RowLayout {
        Layout.fillWidth: true
        Text {
          Layout.fillWidth: true
          text: "This machine"
          color: Theme.text
          font.family: Theme.fontFamily
          font.bold: true
        }
        Rectangle {
          Layout.preferredHeight: 28
          Layout.preferredWidth: refreshLab.implicitWidth + Theme.spaceLg
          radius: Theme.radius
          color: refreshMa.containsMouse ? Theme.bgHover : Theme.bgElevated
          border.width: 1
          border.color: Theme.border
          Text {
            id: refreshLab
            anchors.centerIn: parent
            text: Hardware.probing ? "Probing…" : "Refresh"
            color: Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: 11
          }
          MouseArea {
            id: refreshMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            enabled: !Hardware.probing
            onClicked: Hardware.refresh()
          }
        }
      }

      Text {
        Layout.fillWidth: true
        text: Hardware.ready
            ? ("Class: " + Hardware.deviceClass
               + (Hardware.chassis ? " · chassis " + Hardware.chassis : "")
               + " · posture hint: " + Hardware.postureHint)
            : (Hardware.probing ? "Detecting hardware…" : "Hardware probe not ready")
        color: Theme.textDim
        font.family: Theme.fontFamily
        font.pixelSize: 12
        wrapMode: Text.WordWrap
      }

      Text {
        visible: Hardware.error.length > 0
        Layout.fillWidth: true
        text: Hardware.error
        color: Theme.danger
        font.family: Theme.fontFamily
        font.pixelSize: 11
        wrapMode: Text.WordWrap
      }

      Flow {
        Layout.fillWidth: true
        spacing: 6
        visible: Hardware.capabilityList.length > 0
        Repeater {
          model: Hardware.capabilityList
          Rectangle {
            required property var modelData
            height: 24
            width: capLab.implicitWidth + 14
            radius: 6
            color: Theme.accentSoft
            border.width: 1
            border.color: Theme.accent
            Text {
              id: capLab
              anchors.centerIn: parent
              text: modelData
              color: Theme.text
              font.family: Theme.fontFamily
              font.pixelSize: 11
            }
          }
        }
      }

      Text {
        visible: Hardware.ready
        Layout.fillWidth: true
        text: "Cache: ~/.config/proteus/hw-probe.json"
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: 10
      }
    }
  }

  GridLayout {
    Layout.fillWidth: true
    Layout.topMargin: Theme.spaceSm
    columns: 2
    rowSpacing: Theme.spaceSm
    columnSpacing: Theme.spaceSm
    Repeater {
      model: [
        {
          label: "Lock",
          action: "lock"
        },
        {
          label: "Log out",
          action: "logout"
        },
        {
          label: "Reboot",
          action: "reboot"
        },
        {
          label: "Shut down",
          action: "shutdown"
        }
      ]
      Rectangle {
        required property var modelData
        Layout.fillWidth: true
        Layout.preferredHeight: 42
        radius: Theme.radiusMd
        color: modelData.action === "shutdown" || modelData.action === "reboot" ? Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.15) : Theme.bgPanel
        border.width: 1
        border.color: modelData.action === "shutdown" || modelData.action === "reboot" ? Theme.danger : Theme.border
        Text {
          anchors.centerIn: parent
          text: modelData.label
          color: Theme.text
          font.family: Theme.fontFamily
        }
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: Config.session(modelData.action)
        }
      }
    }
  }
}
