import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../shared"

// Network: device status + hand-off to the NetworkManager editor.
// Bluetooth / VPN land here later (SETTINGS-IA § 2).
ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: Theme.spaceMd

  property bool active: false
  // [{ device, type, state, connection }, ...]
  property var devices: []
  property string status: "Checking network…"

  function stateHint(dev) {
    const parts = [dev.type, dev.state]
    if (dev.connection && dev.connection.length)
      parts.push(dev.connection)
    return parts.filter(p => p && p.length).join(" · ")
  }

  function isUp(dev) {
    return String(dev.state || "").toLowerCase() === "connected"
  }

  Text {
    Layout.fillWidth: true
    Layout.maximumWidth: 480
    visible: !root.devices.length
    text: root.status
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 12
    wrapMode: Text.WordWrap
  }

  SettingsGroup {
    visible: root.devices.length > 0
    title: "Devices"

    Repeater {
      model: root.devices

      SettingsFormRow {
        required property var modelData
        required property int index
        label: modelData.device
        hint: root.stateHint(modelData)
        showSeparator: index < root.devices.length - 1
        Text {
          text: root.isUp(modelData) ? "Connected" : ""
          color: Theme.accent
          font.family: Theme.fontFamily
          font.pixelSize: 12
        }
      }
    }
  }

  SettingsGroup {
    SettingsFormRow {
      label: "Open network settings"
      hint: "NetworkManager editor, or nmtui in a terminal"
      showSeparator: false
      interactive: true
      onActivated: Config.openNetworkEditor()
      Text {
        text: "›"
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
      }
    }
  }

  Text {
    Layout.fillWidth: true
    Layout.maximumWidth: 480
    text: "Fact: nmcli dev status · nm-connection-editor / nmtui."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 11
    wrapMode: Text.WordWrap
  }

  Process {
    command: ["nmcli", "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "dev", "status"]
    running: root.active
    stdout: StdioCollector {
      onStreamFinished: {
        const lines = text.trim().split("\n").filter(l => l.length)
        if (!lines.length) {
          root.devices = []
          root.status = "No NetworkManager devices found."
          return
        }
        root.devices = lines.map(l => {
          const p = l.split(":")
          return {
            device: p[0] || "?",
            type: p[1] || "",
            state: p[2] || "",
            connection: p[3] || ""
          }
        })
        root.status = ""
      }
    }
  }
}
