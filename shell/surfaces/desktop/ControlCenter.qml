import Quickshell
import Quickshell.Services.UPower
import QtQuick
import QtQuick.Layouts
import "../../shared"

// Combined notifications + quick settings (macOS-style Control Center).
Item {
  id: root
  anchors.fill: parent

  readonly property real panelW: Math.min(360, parent.width - 24)

  Rectangle {
    anchors.fill: parent
    color: Theme.scrimFill
    MouseArea {
      anchors.fill: parent
      onClicked: ShellState.closeControlCenter()
    }
  }

  Rectangle {
    id: panel
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.topMargin: Theme.barHeight + 10
    anchors.rightMargin: 12
    width: root.panelW
    height: Math.min(parent.height - Theme.barHeight - 24, contentCol.implicitHeight + 28)
    radius: Theme.radiusXl
    color: Theme.elevatedFill
    border.width: 1
    border.color: Theme.chromeBorder
    clip: true

    // Absorb clicks so scrim doesn't close when interacting
    MouseArea {
      anchors.fill: parent
      onClicked: {}
    }

    ColumnLayout {
      id: contentCol
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Theme.spaceMd
      spacing: Theme.spaceMd
      width: parent.width - Theme.spaceMd * 2

      NotificationList {
        Layout.fillWidth: true
        Layout.maximumHeight: 300
      }

      Rectangle {
        Layout.fillWidth: true
        height: 1
        color: Theme.separator
      }

      Text {
        text: "Quick Settings"
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: 14
        font.weight: Font.Medium
      }

      QuickSettingsGrid {
        id: qsGrid
        Layout.fillWidth: true
        batteryText: {
          const d = UPower.displayDevice
          if (!d)
            return "—"
          const p = Number(d.percentage)
          if (isNaN(p))
            return UPower.onBattery ? "On battery" : "AC power"
          const pct = Math.round(Math.max(0, Math.min(1, p)) * 100)
          const s = String(d.state || "")
          const charging = s.indexOf("Charging") >= 0 || s.indexOf("Fully") >= 0
          if (charging)
            return pct + "% · Charging"
          if (UPower.onBattery)
            return pct + "%"
          return pct + "% · AC"
        }
        onNetworkClicked: {
          Config.openNetworkEditor()
          ShellState.closeControlCenter()
        }
        onDndToggled: Notifications.toggleDnd()
        onSettingsClicked: ShellState.openSettings()
      }

      Text {
        Layout.fillWidth: true
        text: "Deep Sound / Network / Power live in Settings"
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: 11
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
      }
    }
  }

  Keys.onEscapePressed: ShellState.closeControlCenter()
  focus: true
  Component.onCompleted: forceActiveFocus()
}
