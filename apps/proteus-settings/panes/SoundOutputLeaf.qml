import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../shared"
import "../kit"

// Leaf UI for SoundPane — Output (SettingsFormRow honesty).
ColumnLayout {
  id: root
  property Item host
  width: parent ? parent.width : implicitWidth
  spacing: Theme.spaceMd

  SettingsGroup {
    title: "Output"

    SettingsFormRow {
      label: "Volume"
      hint: !host ? ""
          : (host.muted ? (host.volume + "% · muted")
              : (host.volume + "% · audible"))
      showSeparator: true
      ThemeSlider {
        Layout.preferredWidth: 160
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
      ThemeSwitch {
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
      hint: "Short tone on the default output"
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
    visible: host && host.sinks.length > 0

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

  SettingsGroup {
    title: "Status"
    visible: host && (host.status.length > 0 || host.nullSinkHint.length > 0)

    SettingsFormRow {
      visible: host && host.status.length > 0
      label: "Devices"
      hint: host ? host.status : ""
      showSeparator: host && host.nullSinkHint.length > 0
    }

    SettingsFormRow {
      visible: host && host.nullSinkHint.length > 0
      label: "Default sink"
      hint: host ? host.nullSinkHint : ""
      showSeparator: false
    }
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
