import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import "../../../shared"

Item {
  id: root
  property string size: "sm"
  property bool showWhenIdle: true

  readonly property var device: UPower.displayDevice
  readonly property real pct: {
    const d = root.device
    if (!d)
      return -1
    const p = Number(d.percentage)
    if (isNaN(p))
      return -1
    return Math.max(0, Math.min(1, p))
  }
  readonly property bool charging: {
    const d = root.device
    if (!d)
      return false
    const s = String(d.state)
    return s.indexOf("Charging") >= 0 || s.indexOf("Fully") >= 0
  }

  implicitWidth: card.implicitWidth
  implicitHeight: card.implicitHeight
  width: parent ? Math.min(parent.width, size === "lg" ? 280 : (size === "md" ? 200 : 140)) : 140
  height: implicitHeight

  Rectangle {
    id: card
    anchors.left: parent.left
    anchors.right: parent.right
    implicitHeight: body.implicitHeight + 20
    radius: 16
    color: Qt.rgba(28 / 255, 28 / 255, 30 / 255, 0.72)
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.1)

    ColumnLayout {
      id: body
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: 12
      spacing: 6

      Text {
        text: "Battery"
        color: Qt.rgba(1, 1, 1, 0.55)
        font.family: Theme.fontFamily
        font.pixelSize: 11
      }

      Text {
        text: root.pct < 0
            ? (UPower.onBattery ? "…" : "AC power")
            : (Math.round(root.pct * 100) + "%" + (root.charging ? " ⚡" : ""))
        color: "#f5f5f7"
        font.family: Theme.fontFamily
        font.pixelSize: root.size === "sm" ? 18 : 22
        font.weight: Font.Medium
      }

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 6
        radius: 3
        color: Qt.rgba(1, 1, 1, 0.12)
        visible: root.pct >= 0
        Rectangle {
          width: parent.width * Math.max(0, root.pct)
          height: parent.height
          radius: 3
          color: root.pct < 0.2 ? "#ff453a" : Theme.accent
        }
      }
    }
  }
}
