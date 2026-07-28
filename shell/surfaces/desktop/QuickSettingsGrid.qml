import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../shared"

ColumnLayout {
  id: root
  spacing: Theme.spaceSm

  property int volume: 50
  property bool muted: false
  property string netSummary: "Network"
  property string batteryText: "—"

  signal volumeChangedByUser(int pct)
  signal muteToggled()
  signal networkClicked()
  signal dndToggled()
  signal settingsClicked()

  function refreshAudio() {
    Audio.getVolume(v => {
      root.volume = Math.max(0, Math.min(150, Math.round(v)))
    })
    Audio.getMute(m => {
      root.muted = !!m
    })
  }

  function refreshNetwork() {
    netProc.running = false
    netProc.running = true
  }

  Timer {
    interval: 1200
    running: visible
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      root.refreshAudio()
      root.refreshNetwork()
    }
  }

  Process {
    id: netProc
    command: ["nmcli", "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "dev", "status"]
    stdout: StdioCollector {
      onStreamFinished: {
        const lines = String(text).trim().split("\n").filter(l => l.length)
        let best = "No connection"
        for (let i = 0; i < lines.length; i++) {
          const p = lines[i].split(":")
          if (p.length < 3)
            continue
          const type = p[1]
          const state = p[2]
          const conn = p.length > 3 ? p.slice(3).join(":") : ""
          if (state.indexOf("connected") >= 0 && state.indexOf("disconnected") < 0) {
            if (type === "wifi") {
              best = conn.length ? conn : "Wi‑Fi"
              break
            }
            if (type === "ethernet")
              best = conn.length ? conn : "Ethernet"
            else if (best === "No connection")
              best = conn.length ? conn : type
          }
        }
        root.netSummary = best
      }
    }
  }

  // Volume row
  Rectangle {
    Layout.fillWidth: true
    Layout.preferredHeight: 52
    radius: Theme.radiusLg
    color: Theme.bgHover

    RowLayout {
      anchors.fill: parent
      anchors.margins: Theme.spaceSm
      spacing: Theme.spaceSm

      Rectangle {
        Layout.preferredWidth: 36
        Layout.preferredHeight: 36
        radius: 10
        color: root.muted ? Theme.chromeAccentSoft : Theme.elevatedFill
        Text {
          anchors.centerIn: parent
          text: root.muted ? "🔇" : "🔊"
          font.pixelSize: 14
        }
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            root.muteToggled()
            root.muted = !root.muted
            Audio.setMute(root.muted)
          }
        }
      }

      Slider {
        id: volSlider
        Layout.fillWidth: true
        from: 0
        to: 100
        value: Math.min(100, root.volume)
        onMoved: {
          root.volume = Math.round(value)
          root.volumeChangedByUser(root.volume)
          Audio.setVolume(root.volume)
          if (root.muted) {
            root.muted = false
            Audio.setMute(false)
          }
        }
      }

      Text {
        text: root.muted ? "Mute" : (Math.min(100, root.volume) + "%")
        color: Theme.textDim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSm
        Layout.preferredWidth: 40
        horizontalAlignment: Text.AlignRight
      }
    }
  }

  // Tile grid
  GridLayout {
    Layout.fillWidth: true
    columns: 2
    rowSpacing: Theme.spaceSm
    columnSpacing: Theme.spaceSm

    Repeater {
      model: [
        {
          id: "net",
          title: "Network",
          subtitle: root.netSummary,
          accent: root.netSummary !== "No connection"
        },
        {
          id: "bat",
          title: "Battery",
          subtitle: root.batteryText,
          accent: false
        },
        {
          id: "dnd",
          title: "Do Not Disturb",
          subtitle: Config.notificationsDnd ? "On" : "Off",
          accent: Config.notificationsDnd
        },
        {
          id: "settings",
          title: "Settings",
          subtitle: "Sound · Network",
          accent: false
        }
      ]

      Rectangle {
        required property var modelData
        Layout.fillWidth: true
        Layout.preferredHeight: 72
        radius: Theme.radiusLg
        color: modelData.accent ? Theme.chromeAccentSoft : Theme.bgHover
        border.width: modelData.accent ? 1 : 0
        border.color: Theme.accent

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: Theme.spaceMd
          spacing: 2
          Text {
            text: modelData.title
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: 13
            font.weight: Font.Medium
          }
          Text {
            text: modelData.subtitle
            color: Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: 11
            elide: Text.ElideRight
            Layout.fillWidth: true
          }
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (modelData.id === "net")
              root.networkClicked()
            else if (modelData.id === "dnd")
              root.dndToggled()
            else if (modelData.id === "settings")
              root.settingsClicked()
          }
        }
      }
    }
  }
}
