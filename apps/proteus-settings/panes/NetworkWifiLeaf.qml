import Quickshell
import QtQuick
import QtQuick.Layouts
import "../shared"
import "../kit"

// Leaf UI for NetworkPane — Wi‑Fi.
ColumnLayout {
  id: root
  property Item host
  width: parent ? parent.width : implicitWidth
  spacing: Theme.spaceMd

  SettingsGroup {
    title: "Wi‑Fi"

    SettingsFormRow {
      visible: host && !host.wifiNetworks.length
      label: "Networks"
      hint: host ? host.wifiStatus : ""
      showSeparator: true
    }

    SettingsFormRow {
      visible: host && host.wifiError.length > 0
      label: "Note"
      hint: host ? host.wifiError : ""
      showSeparator: true
      labelColor: Theme.danger
    }

    Repeater {
      model: host ? host.wifiNetworks : []

      SettingsFormRow {
        required property var modelData
        required property int index
        label: modelData.ssid || "(hidden)"
        hint: {
          const bits = []
          if (modelData.signal)
            bits.push(modelData.signal + "%")
          if (modelData.security)
            bits.push(modelData.security)
          if (modelData.active)
            bits.push("in use")
          return bits.join(" · ")
        }
        showSeparator: host && index < host.wifiNetworks.length - 1
        interactive: host && !host.wifiBusy && modelData.ssid && modelData.ssid.length > 0
        onActivated: {
          if (!host)
            return
          if (modelData.active)
            host.disconnectWifi()
          else
            host.connectWifi(modelData.ssid)
        }
        Text {
          text: modelData.active ? "Disconnect" : "Connect"
          color: modelData.active ? Theme.danger : Theme.accent
          font.family: Theme.fontFamily
          font.pixelSize: 12
        }
      }
    }

    SettingsFormRow {
      label: "Rescan Wi‑Fi"
      hint: host && host.wifiDevice.length ? ("Interface " + host.wifiDevice) : "Needs a Wi‑Fi device"
      showSeparator: false
      interactive: host && !host.wifiBusy
      onActivated: {
        if (!host)
          return
        host.wifiBusy = true
        host.kick(host.wifiProc)
        host.wifiRefresh.restart()
      }
      Text {
        text: "↻"
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
      }
    }
  }
}
