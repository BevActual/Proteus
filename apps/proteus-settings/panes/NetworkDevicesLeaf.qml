import Quickshell
import QtQuick
import QtQuick.Layouts
import "../shared"
import "../kit"

// Leaf UI for NetworkPane — Devices (SettingsFormRow honesty).
ColumnLayout {
  id: root
  property Item host
  width: parent ? parent.width : implicitWidth
  spacing: Theme.spaceMd

  function deviceHint(dev) {
    if (!host || !dev)
      return ""
    const bits = []
    if (dev.type)
      bits.push(dev.type)
    if (dev.state)
      bits.push(dev.state)
    if (dev.connection && String(dev.connection).length)
      bits.push(dev.connection)
    return bits.join(" · ")
  }

  function deviceTrailing(dev) {
    if (!host || !dev)
      return ""
    if (host.isUp(dev))
      return "Connected"
    const s = String(dev.state || "").toLowerCase()
    if (s.indexOf("unavailable") >= 0)
      return "Unavailable"
    if (s.indexOf("disconnected") >= 0)
      return "Down"
    return ""
  }

  SettingsGroup {
    title: "Devices"
    visible: host && !host.devices.length

    SettingsFormRow {
      label: "Interfaces"
      hint: host && host.status.length ? host.status : "No NetworkManager devices found"
      showSeparator: false
    }
  }

  SettingsGroup {
    visible: host && host.devices.length > 0
    title: "Devices"

    Repeater {
      model: host ? host.devices : []

      SettingsFormRow {
        required property var modelData
        required property int index
        label: modelData.device
        hint: root.deviceHint(modelData)
        showSeparator: host && index < host.devices.length - 1
        Text {
          text: root.deviceTrailing(modelData)
          color: host && host.isUp(modelData) ? Theme.accent : Theme.textMute
          font.family: Theme.fontFamily
          font.pixelSize: 12
        }
      }
    }
  }

  Text {
    Layout.fillWidth: true
    Layout.maximumWidth: 480
    text: "Fact: nmcli -t -f DEVICE,TYPE,STATE,CONNECTION dev status."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 11
    wrapMode: Text.WordWrap
  }
}
