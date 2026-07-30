import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../shared"
import "../kit"

// Leaf UI for SoundPane — Output.
ColumnLayout {
  id: root
  property Item host
  width: parent ? parent.width : implicitWidth
  spacing: Theme.spaceMd

  SettingsGroup {
    title: "Output"

    SettingsFormRow {
      label: "Volume"
      hint: host ? (host.volume + "%") : ""
      showSeparator: true
      Slider {
        Layout.preferredWidth: 150
        from: 0
        to: 100
        stepSize: 1
        value: host ? host.volume : 0
        enabled: host && !host.muted
        onMoved: {
          if (!host)
            return
          host.volume = Math.round(value)
          Audio.setVolume(host.volume)
        }
      }
    }

    SettingsFormRow {
      label: "Mute output"
      hint: host && host.muted ? "Silenced" : "Audible"
      showSeparator: true
      Switch {
        checked: host ? host.muted : false
        onToggled: {
          if (!host)
            return
          host.muted = checked
          Audio.setMute(checked)
        }
      }
    }

    SettingsFormRow {
      label: "Test sound"
      hint: "Play a short tone on the default device"
      showSeparator: false
      interactive: true
      onActivated: Audio.playTestSound()
      Text {
        text: "Play"
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
      }
    }
  }

  SettingsGroup {
    title: "Device"

    Repeater {
      model: host ? host.sinks : []

      SettingsFormRow {
        required property var modelData
        required property int index
        label: modelData.label
        hint: host ? host.deviceHint(modelData) : ""
        showSeparator: host && index < host.sinks.length - 1
        interactive: !modelData.isDefault
        onActivated: {
          if (host)
            host.selectSink(modelData.name)
        }
        Text {
          visible: !!modelData.isDefault
          text: "Default"
          color: Theme.accent
          font.family: Theme.fontFamily
          font.pixelSize: 12
        }
      }
    }
  }

  Text {
    Layout.fillWidth: true
    Layout.maximumWidth: 480
    visible: host && host.status.length > 0
    text: host ? host.status : ""
    color: Theme.textDim
    font.family: Theme.fontFamily
    font.pixelSize: 12
    wrapMode: Text.WordWrap
  }

  Text {
    Layout.fillWidth: true
    Layout.maximumWidth: 480
    visible: host && host.nullSinkHint.length > 0
    text: host ? host.nullSinkHint : ""
    color: Theme.textDim
    font.family: Theme.fontFamily
    font.pixelSize: 12
    wrapMode: Text.WordWrap
  }

  Text {
    Layout.fillWidth: true
    Layout.maximumWidth: 480
    text: "Fact: pactl list short sinks · pactl set-sink-volume."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 11
    wrapMode: Text.WordWrap
  }
}
