import Quickshell
import Quickshell.Services.UPower
import QtQuick
import QtQuick.Window
import "../../shared"

// Matte menu bar — left chrome, centered title, status cluster → Control Center.
Item {
  id: root
  anchors.fill: parent

  readonly property real dpr: Math.max(1, Screen.devicePixelRatio || 1)
  readonly property int controlH: Math.max(22, Theme.barHeight - 8)
  readonly property int sidePad: 12

  readonly property string batteryHint: {
    const d = UPower.displayDevice
    if (!d)
      return ""
    const p = Number(d.percentage)
    if (isNaN(p))
      return ""
    return Math.round(Math.max(0, Math.min(1, p)) * 100) + "%"
  }

  Rectangle {
    anchors.fill: parent
    color: Theme.panelFill
    border.width: 0
  }

  Item {
    anchors.fill: parent
    anchors.leftMargin: root.sidePad
    anchors.rightMargin: root.sidePad

    Row {
      id: leftRow
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      spacing: Theme.spaceSm
      z: 2

      Rectangle {
        width: root.controlH + 4
        height: root.controlH
        radius: Theme.radiusPill
        color: launchMa.containsMouse || ShellState.launcherOpen
            ? Theme.chromeAccentSoft
            : (launchMa.containsMouse ? Theme.chromeHover : "transparent")

        Text {
          anchors.centerIn: parent
          text: "P"
          color: ShellState.launcherOpen || launchMa.containsMouse ? Theme.accent : Theme.text
          font.family: Theme.fontFamily
          font.pixelSize: 13
          font.weight: Font.DemiBold
        }

        MouseArea {
          id: launchMa
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: ShellState.toggleLauncher()
        }
      }

      Workspaces {
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    Text {
      id: titleLabel
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.verticalCenter: parent.verticalCenter
      width: Math.min(implicitWidth, parent.width * 0.42)
      text: ActiveWindow.text
      color: Theme.textDim
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSize
      font.weight: Font.Medium
      elide: Text.ElideMiddle
      horizontalAlignment: Text.AlignHCenter
      opacity: text.length ? 1 : 0
      z: 1
    }

    // Status cluster — opens Control Center (notifications + quick settings)
    Rectangle {
      id: statusChip
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      height: root.controlH
      width: statusRow.implicitWidth + 16
      radius: Theme.radiusPill
      z: 2
      color: statusMa.containsMouse || ShellState.controlCenterOpen
          ? Theme.chromeHover
          : "transparent"

      Row {
        id: statusRow
        anchors.centerIn: parent
        spacing: 8

        // Unread badge
        Rectangle {
          visible: Notifications.unreadCount > 0
          anchors.verticalCenter: parent.verticalCenter
          width: Math.max(16, badgeLabel.implicitWidth + 8)
          height: 16
          radius: 8
          color: Theme.accent
          Text {
            id: badgeLabel
            anchors.centerIn: parent
            text: Notifications.unreadCount > 9 ? "9+" : String(Notifications.unreadCount)
            color: "#fff"
            font.pixelSize: 10
            font.weight: Font.DemiBold
          }
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          visible: Config.notificationsDnd
          text: "☾"
          color: Theme.accent
          font.pixelSize: 12
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          visible: root.batteryHint.length > 0
          text: root.batteryHint
          color: Theme.textDim
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSizeSm
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: Time.text
          color: Theme.text
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSize
          font.weight: Font.Medium
        }
      }

      MouseArea {
        id: statusMa
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: ShellState.toggleControlCenter()
      }
    }
  }
}
