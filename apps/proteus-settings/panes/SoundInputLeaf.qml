import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../shared"
import "../kit"

// Leaf UI for SoundPane — Input (SettingsFormRow honesty).
ColumnLayout {
  id: root
  property Item host
  width: parent ? parent.width : implicitWidth
  spacing: Theme.spaceMd

  SettingsGroup {
    title: "Microphone"
    visible: host && !host.sources.length

    SettingsFormRow {
      label: "Capture"
      hint: "No capture devices reported"
      showSeparator: false
    }
  }

  SettingsGroup {
    visible: host && host.sources.length > 0
    title: "Microphone"

    SettingsFormRow {
      label: "Level"
      hint: !host ? ""
          : (host.inputMuted ? (host.inputVolume + "% · muted")
              : (host.inputVolume + "% · live"))
      showSeparator: true
      Slider {
        Layout.preferredWidth: 160
        from: 0
        to: 100
        stepSize: 1
        value: host ? host.inputVolume : 0
        enabled: host && !host.inputMuted
        onMoved: {
          if (!host)
            return
          host.inputVolume = Math.round(value)
          Audio.setSourceVolume(host.inputVolume)
        }
      }
    }

    SettingsFormRow {
      label: "Mute input"
      hint: host && host.inputMuted ? "Muted" : "Live"
      showSeparator: true
      Switch {
        checked: host ? host.inputMuted : false
        onToggled: {
          if (!host)
            return
          host.inputMuted = checked
          Audio.setSourceMute(checked)
          if (checked)
            host.inputPeak = 0
        }
      }
    }

    SettingsFormRow {
      label: "Peak meter"
      hint: host && host.inputMuted ? "Paused while muted"
          : (Math.round(host ? host.inputPeak : 0) + "% peak · speak to test")
      showSeparator: false

      Rectangle {
        Layout.preferredWidth: 120
        Layout.preferredHeight: 10
        radius: 3
        color: Theme.bg
        border.width: 1
        border.color: Theme.border
        clip: true

        Rectangle {
          anchors.left: parent.left
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          width: parent.width * Math.max(0, Math.min(1, (host ? host.inputPeak : 0) / 100))
          color: host && host.inputMuted ? Theme.textMute
              : ((host && host.inputPeak > 90) ? Theme.danger : Theme.accent)
        }
      }
    }
  }

  SettingsGroup {
    visible: host && host.sources.length > 0
    title: "Device"

    Repeater {
      model: host ? host.sources : []

      SettingsFormRow {
        required property var modelData
        required property int index
        label: modelData.label
        hint: host ? host.deviceHint(modelData) : ""
        showSeparator: host && index < host.sources.length - 1
        interactive: !modelData.isDefault
        onActivated: {
          if (host)
            host.selectSource(modelData.name)
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
    text: "Fact: pactl for devices · streaming audio-peak.py for the meter."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 11
    wrapMode: Text.WordWrap
  }
}
