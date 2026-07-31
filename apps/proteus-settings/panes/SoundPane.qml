import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../shared"
import "../kit"

// Sound category hub → leaf loaders (Desktop/Appearance pattern).
// Page ids: sound · sound-output · sound-input · sound-apps · sound-matrix · sound-latency.
ColumnLayout {
  id: root
  Layout.fillWidth: true
  Layout.fillHeight: page === "sound-matrix"
  spacing: Theme.spaceMd

  property string page: "sound"
  signal requestGo(string id)

  readonly property bool active: page === "sound" || page.startsWith("sound-")

  property int volume: 50
  property bool muted: false
  property int inputVolume: 50
  property bool inputMuted: false
  property real inputPeak: 0
  property bool sourcePeaksSubscribed: false
  property var sinks: []
  property var sources: []
  property var apps: []
  property string status: ""
  property string clockSummary: ""
  property string nullSinkHint: ""
  // Resident dump+peaks while Apps/Mixer open; Python dump fallback if helper missing.
  property bool mixServeActive: false
  property bool mixFallbackPoll: false

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
      key: "sound-matrix",
      label: "Mixer"
    },
    {
      key: "sound-latency",
      label: "Latency & buffer"
    }
  ]

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

  function syncSourcePeaks() {
    const want = root.page === "sound-input" && root.sources.length > 0 && !root.inputMuted
    if (want && !root.sourcePeaksSubscribed) {
      Audio.subscribeSourcePeaks()
      root.sourcePeaksSubscribed = true
    } else if (!want && root.sourcePeaksSubscribed) {
      Audio.unsubscribeSourcePeaks()
      root.sourcePeaksSubscribed = false
      root.inputPeak = 0
    }
  }

  function refresh() {
    status = ""
    nullSinkHint = ""
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
      root.syncSourcePeaks()
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
        root.nullSinkHint = "Default output is Null (dummy). Pick a real device below."
      }
      root.status = ""
    })
    Audio.listSources(list => {
      root.sources = list || []
      root.syncSourcePeaks()
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

  Timer {
    id: peakDecayTimer
    interval: 80
    repeat: true
    running: root.page === "sound-input" && root.sourcePeaksSubscribed
    onTriggered: {
      const v = Audio.sourcePeak
      if (root.inputMuted || !root.sources.length) {
        root.inputPeak = Math.max(0, root.inputPeak * 0.6)
        return
      }
      if (v >= root.inputPeak)
        root.inputPeak = v
      else
        root.inputPeak = root.inputPeak * 0.72 + v * 0.28
    }
  }

  Timer {
    id: appsTimer
    interval: 1500
    repeat: true
    running: root.page === "sound-apps"
    onTriggered: root.refreshApps()
  }

  function syncMixServe() {
    const want = root.page === "sound-apps" || root.page === "sound-matrix"
    if (want && !root.mixServeActive) {
      Audio.startMixServe()
      root.mixServeActive = true
      root.mixFallbackPoll = false
      // If resolve finds no binary, start a light Python poll.
      Qt.callLater(() => {
        if (root.mixServeActive && !Audio.mixServeRunning && !Audio.mixHelperAvailable)
          root.mixFallbackPoll = true
      })
    } else if (!want && root.mixServeActive) {
      Audio.stopMixServe()
      root.mixServeActive = false
      root.mixFallbackPoll = false
    }
  }

  Timer {
    id: mixFallbackTimer
    interval: 4500
    repeat: true
    running: root.mixFallbackPoll && !Audio.mixServeRunning && !Audio.mixDragging
    triggeredOnStart: true
    onTriggered: Audio.refreshMix()
  }

  Timer {
    id: mixServeWatch
    interval: 800
    repeat: true
    running: root.mixServeActive && !Audio.mixServeRunning
    onTriggered: {
      if (Audio.mixServeRunning) {
        root.mixFallbackPoll = false
        return
      }
      if (!Audio.mixHelperAvailable)
        root.mixFallbackPoll = true
    }
  }

  onPageChanged: {
    root.syncSourcePeaks()
    root.syncMixServe()
  }

  Timer {
    id: refreshAppsSoon
    interval: 250
    repeat: false
    onTriggered: root.refreshApps()
  }

  SettingsHubList {
    visible: root.page === "sound"
    items: root.sections
    onActivated: key => root.requestGo(key)
  }

  StickyPaneLoader {
    want: root.page === "sound-output"
    source: "SoundOutputLeaf.qml"
    onLoaded: item.host = root
  }

  StickyPaneLoader {
    want: root.page === "sound-input"
    source: "SoundInputLeaf.qml"
    onLoaded: item.host = root
  }

  StickyPaneLoader {
    want: root.page === "sound-apps"
    source: "SoundAppsLeaf.qml"
    onLoaded: item.host = root
  }

  StickyPaneLoader {
    want: root.page === "sound-matrix"
    Layout.fillHeight: want
    Layout.minimumHeight: want ? 320 : 0
    source: "SoundMatrixLeaf.qml"
    onLoaded: item.host = root
  }

  StickyPaneLoader {
    want: root.page === "sound-latency"
    source: "SoundLatencyLeaf.qml"
    onLoaded: item.host = root
  }

  onActiveChanged: {
    if (active)
      refresh()
  }

  Component.onCompleted: {
    root.syncMixServe()
    if (active)
      refresh()
  }

  Component.onDestruction: {
    if (root.sourcePeaksSubscribed) {
      Audio.unsubscribeSourcePeaks()
      root.sourcePeaksSubscribed = false
    }
    if (root.mixServeActive) {
      Audio.stopMixServe()
      root.mixServeActive = false
    }
  }
}
