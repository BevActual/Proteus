import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../shared"
import "../kit"

// Leaf UI for SoundPane — Applications.
ColumnLayout {
  id: root
  property Item host
  width: parent ? parent.width : implicitWidth
  spacing: Theme.spaceMd

  Text {
    Layout.fillWidth: true
    Layout.maximumWidth: 480
    visible: host && !host.apps.length
    text: "No playing apps right now. Start audio elsewhere and this list fills in."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 12
    wrapMode: Text.WordWrap
  }

  SettingsGroup {
    visible: host && host.apps.length > 0
    title: "Playing now"

    Repeater {
      model: host ? host.apps : []

      SettingsFormRow {
        required property var modelData
        required property int index
        label: modelData.name
        hint: (modelData.detail && modelData.detail.length)
            ? (modelData.detail + " · " + modelData.volume + "%")
            : (modelData.volume + "%")
        showSeparator: host && index < host.apps.length - 1

        Slider {
          Layout.preferredWidth: 120
          from: 0
          to: 100
          stepSize: 1
          value: modelData.volume
          enabled: !modelData.muted
          onMoved: {
            if (!host)
              return
            const v = Math.round(value)
            Audio.setSinkInputVolume(modelData.id, v)
            host.patchApp(modelData.id, {
              volume: v
            })
          }
        }

        Switch {
          checked: !!modelData.muted
          onToggled: {
            if (!host)
              return
            Audio.setSinkInputMute(modelData.id, checked)
            host.patchApp(modelData.id, {
              muted: checked
            })
            host.refreshAppsSoon.restart()
          }
        }
      }
    }
  }

  Text {
    Layout.fillWidth: true
    Layout.maximumWidth: 480
    text: "Fact: pactl list sink-inputs · set-sink-input-volume / -mute."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 11
    wrapMode: Text.WordWrap
  }
}
