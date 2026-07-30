import Quickshell
import QtQuick
import QtQuick.Layouts
import "../shared"
import "../kit"

// Leaf UI for NetworkPane — Wi‑Fi (SettingsFormRow honesty).
ColumnLayout {
  id: root
  property Item host
  width: parent ? parent.width : implicitWidth
  spacing: Theme.spaceMd

  function wifiHint(net) {
    if (!net)
      return ""
    const bits = []
    if (net.active)
      bits.push("Connected")
    if (net.signal)
      bits.push(net.signal + "%")
    if (net.security && String(net.security).length)
      bits.push(net.security)
    else if (!net.active)
      bits.push("Open / unknown")
    return bits.join(" · ")
  }

  SettingsGroup {
    title: "Wi‑Fi"

    SettingsFormRow {
      visible: host && !host.wifiNetworks.length && !(host && host.wifiError.length)
      label: "Networks"
      hint: host && host.wifiBusy
          ? "Scanning…"
          : (host && host.wifiStatus.length ? host.wifiStatus : "No networks — try Rescan")
      showSeparator: true
    }

    SettingsFormRow {
      visible: host && host.wifiError.length > 0
      label: "Status"
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
        hint: root.wifiHint(modelData)
        showSeparator: true
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
          text: {
            if (host && host.wifiBusy)
              return "…"
            return modelData.active ? "Disconnect" : "Connect"
          }
          color: {
            if (host && host.wifiBusy)
              return Theme.textMute
            return modelData.active ? Theme.danger : Theme.accent
          }
          font.family: Theme.fontFamily
          font.pixelSize: 12
        }
      }
    }

    SettingsFormRow {
      label: "Rescan"
      hint: {
        if (!host)
          return ""
        if (host.wifiBusy)
          return "Working…"
        if (host.wifiDevice.length)
          return "Interface " + host.wifiDevice + " · nmcli device wifi"
        return "Needs a Wi‑Fi device"
      }
      showSeparator: false
      interactive: host && !host.wifiBusy && host.wifiDevice.length > 0
      onActivated: {
        if (!host)
          return
        host.wifiBusy = true
        host.kick(host.wifiProc)
        host.wifiRefresh.restart()
      }
      Text {
        text: host && host.wifiBusy ? "…" : "↻"
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
      }
    }
  }

  Text {
    Layout.fillWidth: true
    Layout.maximumWidth: 480
    text: "Fact: nmcli device wifi · password Wi‑Fi → NetworkManager escape on VPN leaf."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 11
    wrapMode: Text.WordWrap
  }
}
