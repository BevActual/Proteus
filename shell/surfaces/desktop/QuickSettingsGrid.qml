import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../shared"

// Control Center Quick Settings — volume + tile chrome (no emoji clutter).
ColumnLayout {
  id: root
  spacing: Theme.spaceSm

  property int volume: 50
  property bool muted: false
  property string netSummary: "Checking…"
  property string batteryText: "—"

  signal volumeChangedByUser(int pct)
  signal muteToggled()
  signal networkClicked()
  signal dndToggled()
  signal settingsClicked()

  readonly property string volumeHint: {
    if (root.muted)
      return "Muted"
    return Math.min(100, root.volume) + "%"
  }

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
    color: Theme.elevatedFill
    border.width: 1
    border.color: Theme.chromeBorder

    RowLayout {
      anchors.fill: parent
      anchors.margins: Theme.spaceSm
      spacing: Theme.spaceSm

      Text {
        text: root.muted ? "Unmute" : "Mute"
        color: root.muted ? Theme.accent : Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: 12
        font.weight: Font.Medium
        Layout.preferredWidth: 52
        MouseArea {
          anchors.fill: parent
          anchors.margins: -6
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
        text: root.volumeHint
        color: root.muted ? Theme.textMute : Theme.textDim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSm
        Layout.preferredWidth: 44
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
          subtitle: root.netSummary === "No connection"
              ? "Open NetworkManager"
              : (root.netSummary + " · editor"),
          accent: root.netSummary !== "No connection" && root.netSummary !== "Checking…",
          interactive: true,
          trailing: "›"
        },
        {
          id: "bat",
          title: "Battery",
          subtitle: root.batteryText,
          accent: false,
          interactive: false,
          trailing: ""
        },
        {
          id: "dnd",
          title: "Do Not Disturb",
          subtitle: Config.notificationsDnd ? "On · toasts off" : "Off · toasts on",
          accent: Config.notificationsDnd,
          interactive: true,
          trailing: Config.notificationsDnd ? "On" : "Off"
        },
        {
          id: "settings",
          title: "Settings",
          subtitle: "Sound · Network · more",
          accent: false,
          interactive: true,
          trailing: "›"
        }
      ]

      Rectangle {
        required property var modelData
        Layout.fillWidth: true
        Layout.preferredHeight: 72
        radius: Theme.radiusLg
        color: modelData.accent ? Theme.chromeAccentSoft : Theme.elevatedFill
        border.width: 1
        border.color: modelData.accent ? Theme.accent : Theme.chromeBorder

        RowLayout {
          anchors.fill: parent
          anchors.margins: Theme.spaceMd
          spacing: Theme.spaceSm

          ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Text {
              text: modelData.title
              color: Theme.text
              font.family: Theme.fontFamily
              font.pixelSize: 13
              font.weight: Font.Medium
              elide: Text.ElideRight
              Layout.fillWidth: true
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

          Text {
            visible: modelData.trailing && String(modelData.trailing).length > 0
            text: modelData.trailing || ""
            color: modelData.accent ? Theme.accent : Theme.textMute
            font.family: Theme.fontFamily
            font.pixelSize: 12
          }
        }

        MouseArea {
          anchors.fill: parent
          enabled: modelData.interactive
          cursorShape: modelData.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
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
