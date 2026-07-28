pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Proteus audio control — thin wrapper over pactl / pw-metadata.
//
// Extracted from Config.qml, which had grown to own prefs, wallpaper, packages,
// displays and audio at once. Persisted state still lives in Config (one
// FileView owns settings.json); this singleton is behaviour only, and reads
// Config.audioLatency rather than keeping its own copy.
Singleton {
  id: root

  readonly property var audioLatencyProfiles: [
    {
      id: "low",
      label: "Low",
      hint: "~5 ms · snappier, may crackle",
      quantum: 256
    },
    {
      id: "balanced",
      label: "Balanced",
      hint: "~11 ms · general use",
      quantum: 512
    },
    {
      id: "high",
      label: "High",
      hint: "~21 ms · smoother playback",
      quantum: 1024
    }
  ]

  // ── Output ────────────────────────────────────────────────────────────────

  function setVolume(pct) {
    const v = Math.max(0, Math.min(150, Math.round(pct)))
    Quickshell.execDetached({
      command: ["pactl", "set-sink-volume", "@DEFAULT_SINK@", v + "%"]
    })
  }

  function getVolume(callback) {
    volumeProc.callback = callback
    volumeProc.running = false
    volumeProc.running = true
  }

  function setMute(muted) {
    Quickshell.execDetached({
      command: ["pactl", "set-sink-mute", "@DEFAULT_SINK@", muted ? "1" : "0"]
    })
  }

  function getMute(callback) {
    muteProc.callback = callback
    muteProc.running = false
    muteProc.running = true
  }

  function listSinks(callback) {
    sinksProc.callback = callback
    // Resolve default sink name, then list
    defaultSinkProc.callback = name => {
      sinksProc.defaultName = name || ""
      sinksProc.running = false
      sinksProc.running = true
    }
    defaultSinkProc.running = false
    defaultSinkProc.running = true
  }

  function setDefaultSink(nameOrId) {
    if (!nameOrId || !String(nameOrId).length)
      return
    Quickshell.execDetached({
      command: ["pactl", "set-default-sink", String(nameOrId)]
    })
  }

  function formatAudioDeviceName(name) {
    if (!name || !String(name).length)
      return "Unknown"
    const n = String(name)
    if (n.indexOf("null") >= 0)
      return "Null (dummy)"
    if (n.indexOf(".monitor") >= 0)
      return "Monitor"
    const tail = n.split(".").pop() || n
    return tail.replace(/-/g, " ").replace(/\b\w/g, c => c.toUpperCase())
  }

  function playTestSound() {
    Quickshell.execDetached({
      command: [
        "bash",
        "-lc",
        "if command -v paplay >/dev/null; then "
            + "for f in /usr/share/sounds/freedesktop/stereo/bell.oga "
            + "/usr/share/sounds/freedesktop/stereo/complete.oga; do "
            + "[ -f \"$f\" ] && paplay \"$f\" && exit 0; done; fi; "
            + "if command -v speaker-test >/dev/null; then "
            + "timeout 1 speaker-test -t sine -f 880 -l 1 -c 2 >/dev/null; fi"
      ]
    })
  }

  // Brief peak sample of the default sink monitor (0–100). Needs parec.
  // NOTE: still spawn-per-sample; callers poll this while a meter is visible.
  // See shell/scripts/audio-peak.py for the streaming form used by the
  // wallpaper pulse effect — worth moving these two over as a follow-up.
  function getSinkPeak(callback) {
    if (sinkPeakProc.running) {
      if (callback)
        callback(-1)
      return
    }
    sinkPeakProc.callback = callback
    sinkPeakProc.running = false
    sinkPeakProc.running = true
  }

  // ── Input ─────────────────────────────────────────────────────────────────

  function setSourceVolume(pct) {
    const v = Math.max(0, Math.min(150, Math.round(pct)))
    Quickshell.execDetached({
      command: ["pactl", "set-source-volume", "@DEFAULT_SOURCE@", v + "%"]
    })
  }

  function getSourceVolume(callback) {
    sourceVolumeProc.callback = callback
    sourceVolumeProc.running = false
    sourceVolumeProc.running = true
  }

  function setSourceMute(muted) {
    Quickshell.execDetached({
      command: ["pactl", "set-source-mute", "@DEFAULT_SOURCE@", muted ? "1" : "0"]
    })
  }

  function getSourceMute(callback) {
    sourceMuteProc.callback = callback
    sourceMuteProc.running = false
    sourceMuteProc.running = true
  }

  function listSources(callback) {
    sourcesProc.callback = callback
    defaultSourceProc.callback = name => {
      sourcesProc.defaultName = name || ""
      sourcesProc.running = false
      sourcesProc.running = true
    }
    defaultSourceProc.running = false
    defaultSourceProc.running = true
  }

  function setDefaultSource(nameOrId) {
    if (!nameOrId || !String(nameOrId).length)
      return
    Quickshell.execDetached({
      command: ["pactl", "set-default-source", String(nameOrId)]
    })
  }

  // Brief peak sample of @DEFAULT_SOURCE@ (0–100). Needs parec; returns 0 if unavailable.
  function getSourcePeak(callback) {
    if (sourcePeakProc.running) {
      if (callback)
        callback(-1)
      return
    }
    sourcePeakProc.callback = callback
    sourcePeakProc.running = false
    sourcePeakProc.running = true
  }

  // ── Per-app streams ───────────────────────────────────────────────────────

  function listSinkInputs(callback) {
    sinkInputsProc.callback = callback
    sinkInputsProc.running = false
    sinkInputsProc.running = true
  }

  function setSinkInputVolume(id, pct) {
    if (id === undefined || id === null || !String(id).length)
      return
    const v = Math.max(0, Math.min(150, Math.round(pct)))
    Quickshell.execDetached({
      command: ["pactl", "set-sink-input-volume", String(id), v + "%"]
    })
  }

  function setSinkInputMute(id, muted) {
    if (id === undefined || id === null || !String(id).length)
      return
    Quickshell.execDetached({
      command: ["pactl", "set-sink-input-mute", String(id), muted ? "1" : "0"]
    })
  }

  // ── Latency / PipeWire ────────────────────────────────────────────────────

  function audioLatencyQuantum(id) {
    const key = id && String(id).length ? String(id) : Config.audioLatency
    for (let i = 0; i < audioLatencyProfiles.length; i++) {
      if (audioLatencyProfiles[i].id === key)
        return audioLatencyProfiles[i].quantum
    }
    return 0
  }

  function setAudioLatency(id) {
    const key = String(id || "")
    let ok = false
    for (let i = 0; i < audioLatencyProfiles.length; i++) {
      if (audioLatencyProfiles[i].id === key) {
        ok = true
        break
      }
    }
    if (!ok)
      return
    Config.audioLatency = key
    applyAudioLatency()
  }

  // Maps Settings preference → PipeWire settings metadata clock.force-quantum.
  // 0 clears the force (PipeWire negotiates from defaults / min-quantum).
  function applyAudioLatency() {
    const q = audioLatencyQuantum(Config.audioLatency)
    Quickshell.execDetached({
      command: ["pw-metadata", "-n", "settings", "0", "clock.force-quantum", String(q > 0 ? q : 0)]
    })
  }

  function getPipeWireClock(callback) {
    pipewireClockProc.callback = callback
    pipewireClockProc.running = false
    pipewireClockProc.running = true
  }

  // ── Processes ─────────────────────────────────────────────────────────────

  Process {
    id: volumeProc
    property var callback
    command: ["pactl", "get-sink-volume", "@DEFAULT_SINK@"]
    stdout: StdioCollector {
      onStreamFinished: {
        const m = text.match(/(\d+)%/)
        if (volumeProc.callback)
          volumeProc.callback(m ? parseInt(m[1], 10) : 50)
      }
    }
  }

  Process {
    id: muteProc
    property var callback
    command: ["pactl", "get-sink-mute", "@DEFAULT_SINK@"]
    stdout: StdioCollector {
      onStreamFinished: {
        const muted = /yes/i.test(text)
        if (muteProc.callback)
          muteProc.callback(muted)
      }
    }
  }

  Process {
    id: defaultSinkProc
    property var callback
    command: ["pactl", "get-default-sink"]
    stdout: StdioCollector {
      onStreamFinished: {
        if (defaultSinkProc.callback)
          defaultSinkProc.callback(text.trim())
      }
    }
  }

  Process {
    id: sinksProc
    property var callback
    property string defaultName: ""
    command: ["pactl", "list", "short", "sinks"]
    stdout: StdioCollector {
      onStreamFinished: {
        const def = sinksProc.defaultName
        const lines = text.trim().split("\n").filter(l => l.length)
        const out = []
        for (let i = 0; i < lines.length; i++) {
          // id \t name \t module \t sample \t state
          const parts = lines[i].split("\t")
          if (parts.length < 2)
            continue
          const name = parts[1]
          out.push({
            id: parts[0],
            name: name,
            label: root.formatAudioDeviceName(name),
            driver: parts[2] || "",
            sample: parts[3] || "",
            state: parts[4] || "",
            isDefault: name === def
          })
        }
        if (sinksProc.callback)
          sinksProc.callback(out)
      }
    }
  }

  Process {
    id: sinkPeakProc
    property var callback
    command: [
      "bash",
      "-lc",
      "if ! command -v parec >/dev/null; then echo 0; exit 0; fi; "
          + "sink=$(pactl get-default-sink 2>/dev/null); "
          + "dev=\"@DEFAULT_MONITOR@\"; "
          + "if [[ -n \"$sink\" ]]; then dev=\"${sink}.monitor\"; fi; "
          + "timeout 0.3 parec -d \"$dev\" --raw --format=s16le --rate=8000 --channels=1 --latency-msec=40 2>/dev/null "
          + "| head -c 640 "
          + "| od -An -td2 "
          + "| awk 'BEGIN{m=0}{for(i=1;i<=NF;i++){v=$i;if(v<0)v=-v;if(v>m)m=v}}END{print int((m*100)/32767)}'"
    ]
    stdout: StdioCollector {
      onStreamFinished: {
        const n = parseInt(text.trim(), 10)
        if (sinkPeakProc.callback)
          sinkPeakProc.callback(isNaN(n) ? 0 : Math.max(0, Math.min(100, n)))
      }
    }
  }

  Process {
    id: pipewireClockProc
    property var callback
    command: ["pw-metadata", "-n", "settings", "0"]
    stdout: StdioCollector {
      onStreamFinished: {
        const rateM = text.match(/key:'clock\.rate'\s+value:'(\d+)'/)
        const forceM = text.match(/key:'clock\.force-quantum'\s+value:'(\d+)'/)
        const quantumM = text.match(/key:'clock\.quantum'\s+value:'(\d+)'/)
        if (pipewireClockProc.callback) {
          pipewireClockProc.callback({
            rate: rateM ? parseInt(rateM[1], 10) : 0,
            forceQuantum: forceM ? parseInt(forceM[1], 10) : 0,
            quantum: quantumM ? parseInt(quantumM[1], 10) : 0
          })
        }
      }
    }
  }

  Process {
    id: sourceVolumeProc
    property var callback
    command: ["pactl", "get-source-volume", "@DEFAULT_SOURCE@"]
    stdout: StdioCollector {
      onStreamFinished: {
        const m = text.match(/(\d+)%/)
        if (sourceVolumeProc.callback)
          sourceVolumeProc.callback(m ? parseInt(m[1], 10) : 50)
      }
    }
  }

  Process {
    id: sourceMuteProc
    property var callback
    command: ["pactl", "get-source-mute", "@DEFAULT_SOURCE@"]
    stdout: StdioCollector {
      onStreamFinished: {
        const muted = /yes/i.test(text)
        if (sourceMuteProc.callback)
          sourceMuteProc.callback(muted)
      }
    }
  }

  Process {
    id: defaultSourceProc
    property var callback
    command: ["pactl", "get-default-source"]
    stdout: StdioCollector {
      onStreamFinished: {
        if (defaultSourceProc.callback)
          defaultSourceProc.callback(text.trim())
      }
    }
  }

  Process {
    id: sourcesProc
    property var callback
    property string defaultName: ""
    command: ["pactl", "list", "short", "sources"]
    stdout: StdioCollector {
      onStreamFinished: {
        const def = sourcesProc.defaultName
        const lines = text.trim().split("\n").filter(l => l.length)
        const out = []
        for (let i = 0; i < lines.length; i++) {
          const parts = lines[i].split("\t")
          if (parts.length < 2)
            continue
          const name = parts[1]
          // Skip monitor-of-sink pseudo sources
          if (name.indexOf(".monitor") >= 0)
            continue
          out.push({
            id: parts[0],
            name: name,
            label: root.formatAudioDeviceName(name),
            driver: parts[2] || "",
            sample: parts[3] || "",
            state: parts[4] || "",
            isDefault: name === def
          })
        }
        if (sourcesProc.callback)
          sourcesProc.callback(out)
      }
    }
  }

  Process {
    id: sourcePeakProc
    property var callback
    command: [
      "bash",
      "-lc",
      "if ! command -v parec >/dev/null; then echo 0; exit 0; fi; "
          + "timeout 0.3 parec --raw --format=s16le --rate=8000 --channels=1 --latency-msec=40 2>/dev/null "
          + "| head -c 640 "
          + "| od -An -td2 "
          + "| awk 'BEGIN{m=0}{for(i=1;i<=NF;i++){v=$i;if(v<0)v=-v;if(v>m)m=v}}END{print int((m*100)/32767)}'"
    ]
    stdout: StdioCollector {
      onStreamFinished: {
        const n = parseInt(text.trim(), 10)
        if (sourcePeakProc.callback)
          sourcePeakProc.callback(isNaN(n) ? 0 : Math.max(0, Math.min(100, n)))
      }
    }
  }

  Process {
    id: sinkInputsProc
    property var callback
    command: ["pactl", "list", "sink-inputs"]
    stdout: StdioCollector {
      onStreamFinished: {
        const chunks = text.split(/\n(?=Sink Input #)/)
        const out = []
        for (let i = 0; i < chunks.length; i++) {
          const block = chunks[i]
          const idM = block.match(/Sink Input #(\d+)/)
          if (!idM)
            continue
          const volM = block.match(/Volume:[^\n]*?(\d+)%/)
          const appM = block.match(/application\.name\s*=\s*"([^"]*)"/)
          const binM = block.match(/application\.process\.binary\s*=\s*"([^"]*)"/)
          const mediaM = block.match(/media\.name\s*=\s*"([^"]*)"/)
          const name = (appM && appM[1].length) ? appM[1]
              : ((binM && binM[1].length) ? binM[1] : ("Stream " + idM[1]))
          const detail = (mediaM && mediaM[1].length && mediaM[1] !== name) ? mediaM[1]
              : ((binM && binM[1].length && binM[1] !== name) ? binM[1] : "")
          out.push({
            id: idM[1],
            name: name,
            detail: detail,
            volume: volM ? parseInt(volM[1], 10) : 100,
            muted: /Mute:\s*yes/i.test(block)
          })
        }
        if (sinkInputsProc.callback)
          sinkInputsProc.callback(out)
      }
    }
  }
}
