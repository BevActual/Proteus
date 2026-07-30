import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../shared"
import "../kit"

// Leaf UI for SoundPane — Input.
ColumnLayout {
  id: root
  property Item host
  width: parent ? parent.width : implicitWidth
  spacing: Theme.spaceMd

  Text {
    Layout.fillWidth: true
    Layout.maximumWidth: 480
    visible: host && !host.sources.length
    text: "No capture devices reported."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 12
    wrapMode: Text.WordWrap
  }

  SettingsGroup {
    visible: host && host.sources.length > 0
    title: "Microphone"

    SettingsFormRow {
      label: "Level"
      hint: host ? (host.inputVolume + "%") : ""
      showSeparator: true
      Slider {
        Layout.preferredWidth: 150
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
      showSeparator: false
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
  }

  SettingsGroup {
    visible: host && host.sources.length > 0
    title: "Input level"

    Item {
      Layout.fillWidth: true
      Layout.preferredHeight: 56

      ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.spaceMd
        anchors.rightMargin: Theme.spaceMd
        anchors.topMargin: Theme.spaceSm
        anchors.bottomMargin: Theme.spaceSm
        spacing: Theme.spaceSm

        Rectangle {
          Layout.fillWidth: true
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

        Text {
          Layout.fillWidth: true
          text: host && host.inputMuted ? "Meter paused while muted"
              : (Math.round(host ? host.inputPeak : 0) + "% peak · speak to test")
          color: Theme.textMute
          font.family: Theme.fontFamily
          font.pixelSize: 11
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
        hint: modelData.name
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
