import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../shared"

ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: Theme.spaceMd

  property bool active: false

  Text {
    id: netStatus
    Layout.fillWidth: true
    text: "Checking network…"
    color: Theme.text
    font.family: Theme.fontFamily
    wrapMode: Text.WordWrap
  }

  Rectangle {
    Layout.fillWidth: true
    Layout.preferredHeight: 44
    radius: Theme.radiusMd
    color: Theme.accentSoft
    border.width: 1
    border.color: Theme.accent
    Text {
      anchors.centerIn: parent
      text: "Open network settings"
      color: Theme.text
      font.family: Theme.fontFamily
      font.bold: true
    }
    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: Config.openNetworkEditor()
    }
  }

  Process {
    command: ["nmcli", "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "dev", "status"]
    running: root.active
    stdout: StdioCollector {
      onStreamFinished: {
        const lines = text.trim().split("\n").filter(l => l.length)
        if (!lines.length) {
          netStatus.text = "No NetworkManager devices found."
          return
        }
        netStatus.text = lines.map(l => {
          const p = l.split(":")
          return p[0] + " · " + p[1] + " · " + p[2] + (p[3] ? " · " + p[3] : "")
        }).join("\n")
      }
    }
  }
}
