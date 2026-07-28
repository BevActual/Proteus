import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../shared"

// Sound category: list of sub-settings → leaf, same drill-in as Appearance.
// Page ids: sound · sound-output · sound-input · sound-apps · sound-latency.
ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: 12

  property string page: "sound"
  signal requestGo(string id)

  readonly property bool active: page === "sound" || page.startsWith("sound-")

  property int volume: 50
  property bool muted: false
  property int inputVolume: 50
  property bool inputMuted: false
  property real inputPeak: 0
  property var sinks: []
  property var sources: []
  property var apps: []
  property string status: ""
  property string clockSummary: ""

  readonly property var sections: [
    {
      key: "sound-output",
      label: "Output"
    },
    {
      key: "sound-input",
      label: "Input"
    },
    {
      key: "sound-apps",
      label: "Applications"
    },
    {
      key: "sound-latency",
      label: "Latency & buffer"
    }
  ]

  readonly property var defaultSink: root.sinks.find(s => s.isDefault) || null
  readonly property var defaultSource: root.sources.find(s => s.isDefault) || null

  function formatState(state) {
    const s = state || "unknown"
    if (s === "SUSPENDED")
      return "Idle (starts on play)"
    return s
  }

  function deviceHint(dev) {
    if (!dev)
      return ""
    return root.formatState(dev.state) + (dev.sample ? (" · " + dev.sample) : "")
  }

  function refreshApps() {
    Audio.listSinkInputs(list => {
      root.apps = list || []
    })
  }

  function samplePeak() {
    if (root.inputMuted || !root.sources.length) {
      root.inputPeak = Math.max(0, root.inputPeak * 0.6)
      return
    }
    Audio.getSourcePeak(v => {
      if (v < 0)
        return
      // Soft decay so the bar doesn't flicker between samples.
      if (v >= root.inputPeak)
        root.inputPeak = v
      else
        root.inputPeak = root.inputPeak * 0.72 + v * 0.28
    })
  }

  function refresh() {
    status = ""
    Audio.getVolume(v => {
      root.volume = v
    })
    Audio.getMute(m => {
      root.muted = m
    })
    Audio.getSourceVolume(v => {
      root.inputVolume = v
    })
    Audio.getSourceMute(m => {
      root.inputMuted = m
    })
    Audio.listSinks(list => {
      root.sinks = list || []
      if (!root.sinks.length) {
        root.status = "No output devices (is PipeWire / Pulse running?)."
        return
      }
      const def = root.sinks.find(s => s.isDefault)
      const better = root.sinks.find(s => s.name && s.name.indexOf("null") < 0)
      if (def && def.name && def.name.indexOf("null") >= 0 && better) {
        Audio.setDefaultSink(better.name)
        refreshTimer.restart()
        return
      }
      root.status = ""
    })
    Audio.listSources(list => {
      root.sources = list || []
    })
    root.refreshApps()
    Audio.getPipeWireClock(info => {
      if (!info || (!info.rate && !info.forceQuantum && !info.quantum)) {
        root.clockSummary = ""
        return
      }
      const rate = info.rate ? (info.rate + " Hz") : "rate ?"
      const frames = info.forceQuantum > 0 ? info.forceQuantum : info.quantum
      const forced = info.forceQuantum > 0
      const buf = frames ? (frames + " frames" + (forced ? " forced" : "")) : ""
      root.clockSummary = buf.length ? (rate + " · " + buf) : rate
    })
    Audio.applyAudioLatency()
  }

  function selectSink(name) {
    if (!name || !String(name).length)
      return
    Audio.setDefaultSink(name)
    refreshTimer.restart()
  }

  function selectSource(name) {
    if (!name || !String(name).length)
      return
    Audio.setDefaultSource(name)
    refreshTimer.restart()
  }

  function patchApp(id, patch) {
    // Keep the local model responsive until the next poll.
    const next = root.apps.slice()
    const idx = next.findIndex(a => String(a.id) === String(id))
    if (idx >= 0) {
      next[idx] = Object.assign({}, next[idx], patch)
      root.apps = next
    }
  }

  Timer {
    id: refreshTimer
    interval: 200
    repeat: false
    onTriggered: root.refresh()
  }

  // Peak sampling spawns a parec pipeline per tick, so it runs only on the
  // Input leaf rather than the whole Sound category.
  Timer {
    id: peakTimer
    interval: 220
    repeat: true
    running: root.page === "sound-input" && root.sources.length > 0
    onTriggered: root.samplePeak()
  }

  Timer {
    id: appsTimer
    interval: 1500
    repeat: true
    running: root.page === "sound-apps"
    onTriggered: root.refreshApps()
  }

  Timer {
    id: refreshAppsSoon
    interval: 250
    repeat: false
    onTriggered: root.refreshApps()
  }

  // —— Category list ——
  SettingsHubList {
    visible: root.page === "sound"
    items: root.sections
    onActivated: key => root.requestGo(key)
  }

  // —— Output ——
  ColumnLayout {
    visible: root.page === "sound-output"
    Layout.fillWidth: true
    spacing: Theme.spaceMd

    SettingsGroup {
      title: "Output"

      SettingsFormRow {
        label: "Volume"
        hint: root.volume + "%"
        showSeparator: true
        Slider {
          Layout.preferredWidth: 150
          from: 0
          to: 100
          stepSize: 1
          value: root.volume
          enabled: !root.muted
          onMoved: {
            root.volume = Math.round(value)
            Audio.setVolume(root.volume)
          }
        }
      }

      SettingsFormRow {
        label: "Mute output"
        hint: root.muted ? "Silenced" : "Audible"
        showSeparator: true
        Switch {
          checked: root.muted
          onToggled: {
            root.muted = checked
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
        model: root.sinks

        SettingsFormRow {
          required property var modelData
          required property int index
          label: modelData.label
          hint: root.deviceHint(modelData)
          showSeparator: index < root.sinks.length - 1
          interactive: !modelData.isDefault
          onActivated: root.selectSink(modelData.name)
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
      visible: root.status.length > 0
      text: root.status
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

  // —— Input ——
  ColumnLayout {
    visible: root.page === "sound-input"
    Layout.fillWidth: true
    spacing: Theme.spaceMd

    Text {
      Layout.fillWidth: true
      Layout.maximumWidth: 480
      visible: !root.sources.length
      text: "No capture devices reported."
      color: Theme.textMute
      font.family: Theme.fontFamily
      font.pixelSize: 12
      wrapMode: Text.WordWrap
    }

    SettingsGroup {
      visible: root.sources.length > 0
      title: "Microphone"

      SettingsFormRow {
        label: "Level"
        hint: root.inputVolume + "%"
        showSeparator: true
        Slider {
          Layout.preferredWidth: 150
          from: 0
          to: 100
          stepSize: 1
          value: root.inputVolume
          enabled: !root.inputMuted
          onMoved: {
            root.inputVolume = Math.round(value)
            Audio.setSourceVolume(root.inputVolume)
          }
        }
      }

      SettingsFormRow {
        label: "Mute input"
        hint: root.inputMuted ? "Muted" : "Live"
        showSeparator: false
        Switch {
          checked: root.inputMuted
          onToggled: {
            root.inputMuted = checked
            Audio.setSourceMute(checked)
            if (checked)
              root.inputPeak = 0
          }
        }
      }
    }

    SettingsGroup {
      visible: root.sources.length > 0
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
              width: parent.width * Math.max(0, Math.min(1, root.inputPeak / 100))
              color: root.inputMuted ? Theme.textMute
                  : (root.inputPeak > 90 ? Theme.danger : Theme.accent)
            }
          }

          Text {
            Layout.fillWidth: true
            text: root.inputMuted ? "Meter paused while muted"
                : (Math.round(root.inputPeak) + "% peak · speak to test")
            color: Theme.textMute
            font.family: Theme.fontFamily
            font.pixelSize: 11
          }
        }
      }
    }

    SettingsGroup {
      visible: root.sources.length > 0
      title: "Device"

      Repeater {
        model: root.sources

        SettingsFormRow {
          required property var modelData
          required property int index
          label: modelData.label
          hint: modelData.name
          showSeparator: index < root.sources.length - 1
          interactive: !modelData.isDefault
          onActivated: root.selectSource(modelData.name)
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
      text: "Fact: pactl for devices · parec peak sample for the meter."
      color: Theme.textMute
      font.family: Theme.fontFamily
      font.pixelSize: 11
      wrapMode: Text.WordWrap
    }
  }

  // —— Applications ——
  ColumnLayout {
    visible: root.page === "sound-apps"
    Layout.fillWidth: true
    spacing: Theme.spaceMd

    Text {
      Layout.fillWidth: true
      Layout.maximumWidth: 480
      visible: !root.apps.length
      text: "No playing apps right now. Start audio elsewhere and this list fills in."
      color: Theme.textMute
      font.family: Theme.fontFamily
      font.pixelSize: 12
      wrapMode: Text.WordWrap
    }

    SettingsGroup {
      visible: root.apps.length > 0
      title: "Playing now"

      Repeater {
        model: root.apps

        SettingsFormRow {
          required property var modelData
          required property int index
          label: modelData.name
          hint: (modelData.detail && modelData.detail.length)
              ? (modelData.detail + " · " + modelData.volume + "%")
              : (modelData.volume + "%")
          showSeparator: index < root.apps.length - 1

          Slider {
            Layout.preferredWidth: 120
            from: 0
            to: 100
            stepSize: 1
            value: modelData.volume
            enabled: !modelData.muted
            onMoved: {
              const v = Math.round(value)
              Audio.setSinkInputVolume(modelData.id, v)
              root.patchApp(modelData.id, {
                volume: v
              })
            }
          }

          Switch {
            checked: !!modelData.muted
            onToggled: {
              Audio.setSinkInputMute(modelData.id, checked)
              root.patchApp(modelData.id, {
                muted: checked
              })
              refreshAppsSoon.restart()
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

  // —— Latency & buffer ——
  ColumnLayout {
    id: latencyLeaf
    visible: root.page === "sound-latency"
    Layout.fillWidth: true
    spacing: Theme.spaceMd

    readonly property var activeProfile: {
      const list = Audio.audioLatencyProfiles
      for (let i = 0; i < list.length; i++) {
        if (list[i].id === Config.audioLatency)
          return list[i]
      }
      return null
    }

    Text {
      Layout.fillWidth: true
      Layout.maximumWidth: 480
      text: "PipeWire quantum — higher is smoother, lower is snappier."
      color: Theme.textMute
      font.family: Theme.fontFamily
      font.pixelSize: 12
      wrapMode: Text.WordWrap
    }

    SettingsGroup {
      title: "Buffer size"

      SettingsFormRow {
        label: "Profile"
        hint: latencyLeaf.activeProfile ? latencyLeaf.activeProfile.hint : ""
        showSeparator: true
        SettingsSegmented {
          Layout.preferredWidth: 190
          options: Audio.audioLatencyProfiles
          selected: Config.audioLatency
          onActivated: id => {
            Audio.setAudioLatency(id)
            refreshTimer.restart()
          }
        }
      }

      SettingsFormRow {
        label: "Quantum"
        hint: "Frames per buffer at the graph rate"
        showSeparator: false
        Text {
          text: latencyLeaf.activeProfile ? String(latencyLeaf.activeProfile.quantum) : "—"
          color: Theme.textDim
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSize
        }
      }
    }

    SettingsGroup {
      visible: root.clockSummary.length > 0
      title: "Reported"

      SettingsFormRow {
        label: "PipeWire"
        hint: root.clockSummary
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

  onActiveChanged: {
    if (active)
      refresh()
  }

  Component.onCompleted: {
    if (active)
      refresh()
  }
}
