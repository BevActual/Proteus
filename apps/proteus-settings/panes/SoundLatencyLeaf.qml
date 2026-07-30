import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../shared"
import "../kit"

// Leaf UI for SoundPane — Latency & buffer (FormRow polish).
ColumnLayout {
  id: root
  property Item host
  width: parent ? parent.width : implicitWidth
  spacing: Theme.spaceMd

  readonly property var activeProfile: {
    const list = Audio.audioLatencyProfiles
    for (let i = 0; i < list.length; i++) {
      if (list[i].id === Config.audioLatency)
        return list[i]
    }
    return null
  }

  SettingsGroup {
    title: "Buffer size"

    SettingsFormRow {
      label: "Profile"
      hint: root.activeProfile
          ? (root.activeProfile.hint + " · higher smoother, lower snappier")
          : "Higher is smoother · lower is snappier"
      showSeparator: true
      SettingsSegmented {
        Layout.preferredWidth: 190
        options: Audio.audioLatencyProfiles
        selected: Config.audioLatency
        onActivated: id => {
          Audio.setAudioLatency(id)
          if (host)
            host.refreshTimer.restart()
        }
      }
    }

    SettingsFormRow {
      label: "Quantum"
      hint: "Frames per buffer at the graph rate"
      showSeparator: host ? host.clockSummary.length === 0 : true
      Text {
        text: root.activeProfile ? (root.activeProfile.quantum + " frames") : "—"
        color: Theme.textDim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
      }
    }

    SettingsFormRow {
      visible: host && host.clockSummary.length > 0
      label: "PipeWire"
      hint: host ? host.clockSummary : ""
      showSeparator: false
    }
  }

  Text {
    Layout.fillWidth: true
    Layout.maximumWidth: 480
    text: "Fact: pw-metadata -n settings 0 clock.force-quantum."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 11
    wrapMode: Text.WordWrap
  }
}
