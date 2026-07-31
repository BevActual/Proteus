import Quickshell
import Quickshell.Services.UPower
import QtQuick
import QtQuick.Window
import "../../shared"

// Menu bar — thin glass strip (macOS Tahoe-adjacent).
Item {
  id: root
  anchors.fill: parent

  readonly property real dpr: Math.max(1, Screen.devicePixelRatio || 1)
  readonly property int controlH: Math.max(20, Theme.barHeight - 10)
  readonly property int sidePad: 14

  readonly property string batteryHint: {
    const d = UPower.displayDevice
    if (!d)
      return ""
    const p = Number(d.percentage)
    if (isNaN(p))
      return ""
    return Math.round(Math.max(0, Math.min(1, p)) * 100) + "%"
  }

  // Glass plate
  Rectangle {
    anchors.fill: parent
    color: Theme.menuBarFill
    border.width: 0

    Behavior on color {
      ColorAnimation {
        duration: 180
        easing.type: Easing.OutCubic
      }
    }
  }

  // Bottom hairline (hidden when fully clear)
  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: 1
    color: Theme.chromeHairline
    opacity: Theme.chromeClear || Theme.menuBarAlpha < 0.08 ? 0 : Math.min(1, Theme.menuBarAlpha + 0.15)

    Behavior on opacity {
      NumberAnimation {
        duration: 160
        easing.type: Easing.OutCubic
      }
    }
  }

  // Soft text outline when the plate is thin (wallpaper-first legibility floor)
  readonly property int barTextStyle: Theme.menuBarNeedsLegibility ? Text.Outline : Text.Normal
  readonly property color barTextStyleColor: Theme.light
      ? Qt.rgba(1, 1, 1, 0.72)
      : Qt.rgba(0, 0, 0, 0.55)

  Item {
    anchors.fill: parent
    anchors.leftMargin: root.sidePad
    anchors.rightMargin: root.sidePad

    // Left: mark · app name · workspaces (Mac puts app identity on the left)
    Row {
      id: leftRow
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      spacing: 10
      z: 2

      Rectangle {
        width: root.controlH
        height: root.controlH
        radius: width / 2
        color: launchMa.containsMouse || ShellState.launcherOpen
            ? Theme.chromeAccentSoft
            : "transparent"

        Text {
          anchors.centerIn: parent
          text: "P"
          color: ShellState.launcherOpen || launchMa.containsMouse ? Theme.accent : Theme.text
          font.family: Theme.fontFamily
          font.pixelSize: 12
          font.weight: Font.DemiBold
          style: root.barTextStyle
          styleColor: root.barTextStyleColor
        }

        MouseArea {
          id: launchMa
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: ShellState.toggleLauncher()
        }
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, Math.max(80, root.width * 0.28))
        text: ActiveWindow.text
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        font.weight: Font.DemiBold
        elide: Text.ElideRight
        opacity: text.length ? 0.92 : 0
        visible: text.length > 0
        style: root.barTextStyle
        styleColor: root.barTextStyleColor
      }

      Workspaces {
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    // Right: status items — calm, not a heavy chip
    Rectangle {
      id: statusCluster
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      height: root.controlH
      width: statusRow.implicitWidth + 14
      radius: height / 2
      z: 2
      color: statusMa.containsMouse || ShellState.controlCenterOpen
          ? (Theme.light ? Qt.rgba(0, 0, 0, 0.06) : Qt.rgba(1, 1, 1, 0.1))
          : "transparent"

      Row {
        id: statusRow
        anchors.centerIn: parent
        spacing: 10

        Rectangle {
          // Unread clears when Control Center opens (Notifications.markAllRead).
          visible: Notifications.unreadCount > 0 && !ShellState.controlCenterOpen
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
          text: "DND"
          color: Theme.accent
          font.family: Theme.fontFamily
          font.pixelSize: 10
          font.weight: Font.DemiBold
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          visible: KeepAwake.active
          text: KeepAwake.mode === "indefinite" ? "Awake" : ("Awake " + KeepAwake.remainingLabel)
          color: Theme.accent
          font.family: Theme.fontFamily
          font.pixelSize: 10
          font.weight: Font.DemiBold
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          visible: root.batteryHint.length > 0
          text: root.batteryHint
          color: Theme.textDim
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSizeSm
          style: root.barTextStyle
          styleColor: root.barTextStyleColor
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: Time.text
          color: Theme.text
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSizeSm
          font.weight: Font.Medium
          style: root.barTextStyle
          styleColor: root.barTextStyleColor
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
