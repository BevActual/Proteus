pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Proteus audio control — thin wrapper over pactl / pw-metadata / pw-link
// plus resident proteus-audio-mix serve for Mixer dump+peaks (Python fallback).
//
// Extracted from Config.qml, which had grown to own prefs, wallpaper, packages,
// displays and audio at once. Persisted state still lives in Config (one
// FileView owns settings.json); this singleton is behaviour only, and reads
// Config.audioLatency rather than keeping its own copy.
//
// Audio matrix (Omnibus-style) uses shell/scripts/audio-matrix.py → pw-link.
// Mixer mutations still use shell/scripts/audio-mix.py.
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

  // Media-key / HUD path — step 0–100%, show Status HUD (#1158).
  // HUD self-suppresses while Control Center is open (see Hud.show).
  function stepVolume(delta) {
    const d = Math.round(Number(delta) || 0)
    getMute(muted => {
      getVolume(v => {
        let cur = Math.max(0, Math.min(150, Math.round(v)))
        if (muted) {
          if (d > 0) {
            setMute(false)
            muted = false
          } else {
            Hud.show("volume", 0, "Muted")
            return
          }
        }
        const next = Math.max(0, Math.min(100, cur + d))
        setVolume(next)
        Hud.show("volume", next, "Sound")
      })
    })
  }

  function toggleMuteHud() {
    getMute(muted => {
      const next = !muted
      setMute(next)
      if (next) {
        Hud.show("volume", 0, "Muted")
        return
      }
      getVolume(v => {
        Hud.show("volume", Math.min(100, Math.max(0, Math.round(v))), "Sound")
      })
    })
  }

  function showVolumeHud(pct, muted) {
    if (muted)
      Hud.show("volume", 0, "Muted")
    else
      Hud.show("volume", Math.min(100, Math.max(0, Math.round(pct))), "Sound")
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

  // Streaming input peak via shell/scripts/audio-peak.py (one long-lived parec).
  // Subscribe while a meter is visible — same pattern as BgConfig for wallpaper.
  property real sourcePeak: 0
  property int sourcePeakSubscribers: 0

  function subscribeSourcePeaks() {
    sourcePeakSubscribers = sourcePeakSubscribers + 1
  }

  function unsubscribeSourcePeaks() {
    sourcePeakSubscribers = Math.max(0, sourcePeakSubscribers - 1)
    if (sourcePeakSubscribers === 0)
      sourcePeak = 0
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

  // Wave Link–style mixer: channels × Monitor/Stream mixes
  property var mixChannels: []
  property var mixInputs: []
  property var mixAvailableSources: []
  property var mixMixes: []
  property string mixListening: "system"
  property var mixPeaks: ({})
  property int mixPeakSubscribers: 0
  property string mixPeakDevices: ""
  // Resident helper (proteus-audio-mix serve) — dump+peaks while Apps/Mixer open.
  property int mixServeConsumers: 0
  property bool mixServeRunning: false
  property bool mixServeStopping: false
  property bool mixHelperAvailable: false
  property string mixHelperBin: ""
  property string mixCtlPath: ""

  function subscribeMixPeaks(deviceList) {
    const devices = (deviceList || []).filter(d => d && String(d).length)
    const key = devices.join("\n")
    root.mixPeakDevices = key
    root.mixPeakSubscribers = root.mixPeakSubscribers + 1
    root._restartMixPeaks()
  }

  function unsubscribeMixPeaks() {
    root.mixPeakSubscribers = Math.max(0, root.mixPeakSubscribers - 1)
    if (root.mixPeakSubscribers === 0) {
      root.mixPeaks = ({})
      root.mixPeakDevices = ""
      mixPeaksProc.running = false
      if (root.mixServeRunning)
        root._mixCtlWrite("peaks")
    }
  }

  function refreshMixPeakDevices(deviceList) {
    const devices = (deviceList || []).filter(d => d && String(d).length)
    const key = devices.join("\n")
    if (key === root.mixPeakDevices)
      return
    root.mixPeakDevices = key
    if (root.mixPeakSubscribers > 0)
      root._restartMixPeaks()
  }

  function _mixCtlWrite(line) {
    const ctl = root.mixCtlPath
    if (!ctl || !String(line || "").length)
      return
    Quickshell.execDetached({
      command: ["bash", "-c", "printf '%s\\n' " + JSON.stringify(String(line)) + " > " + JSON.stringify(ctl)]
    })
  }

  function _restartMixPeaks() {
    const sinks = root.mixPeakDevices.split("\n").filter(s => s.length)
    if (root.mixServeRunning) {
      mixPeaksProc.running = false
      if (root.mixPeakSubscribers <= 0) {
        root._mixCtlWrite("peaks")
        return
      }
      root._mixCtlWrite(sinks.length ? ("peaks " + sinks.join(" ")) : "peaks")
      return
    }
    mixPeaksProc.running = false
    if (root.mixPeakSubscribers <= 0 || !sinks.length)
      return
    mixPeaksProc.command = [
      "python3",
      Config.scriptsDir + "/audio-mix-peaks.py",
      "--window-ms",
      "35",
      "--period-ms",
      "140"
    ].concat(sinks)
    mixPeaksProc.running = true
  }

  function startMixServe() {
    root.mixServeConsumers = root.mixServeConsumers + 1
    if (root.mixServeConsumers === 1)
      root._ensureMixServe()
  }

  function stopMixServe() {
    root.mixServeConsumers = Math.max(0, root.mixServeConsumers - 1)
    if (root.mixServeConsumers === 0)
      root._stopMixServe()
  }

  function _ensureMixServe() {
    if (root.mixServeRunning)
      return
    if (root.mixHelperBin.length) {
      root._launchMixServe(root.mixHelperBin)
      return
    }
    mixHelperResolveProc.running = false
    mixHelperResolveProc.running = true
  }

  function _stopMixServe() {
    root.mixServeStopping = true
    if (root.mixServeRunning)
      root._mixCtlWrite("quit")
    mixServeProc.running = false
    root.mixServeRunning = false
    // Fall back to Python peaks if still subscribed.
    if (root.mixPeakSubscribers > 0)
      root._restartMixPeaks()
  }

  function _launchMixServe(bin) {
    const path = String(bin || "").trim()
    if (!path.length)
      return
    root.mixServeStopping = false
    root.mixHelperBin = path
    root.mixHelperAvailable = true
    const runtime = Quickshell.env("XDG_RUNTIME_DIR") || ("/tmp/proteus-" + Quickshell.env("USER"))
    root.mixCtlPath = runtime + "/proteus-audio-mix.ctl"
    const sinks = root.mixPeakDevices.split("\n").filter(s => s.length)
    const cmd = [path, "serve", "--dump-ms", "4500", "--ctl", root.mixCtlPath]
    if (sinks.length) {
      cmd.push("--peaks")
      for (let i = 0; i < sinks.length; i++)
        cmd.push(sinks[i])
    }
    mixServeProc.command = cmd
    mixServeProc.running = false
    mixServeProc.running = true
    root.mixServeRunning = true
    if (root.mixDragging)
      Qt.callLater(() => root._mixCtlWrite("pause"))
  }

  function mixPeakFor(sinkId) {
    const m = root.mixPeaks || ({})
    const v = m[String(sinkId || "")]
    return typeof v === "number" ? v : 0
  }

  property var mixApps: []
  property var mixUnassigned: []
  property var mixAssignOptions: []
  property string mixError: ""
  property bool mixBusy: false
  // Mixer UI mid-drag — pause polling so dumps don't fight live reorder.
  property bool mixDragging: false
  onMixDraggingChanged: {
    if (!root.mixServeRunning)
      return
    root._mixCtlWrite(root.mixDragging ? "pause" : "resume")
  }
  property bool mixReady: false
  property string mixDumpFp: ""

  function applyMixOrder(kind, orderIds) {
    if (kind === "mix")
      root.mixMixes = root._reorderByIds(root.mixMixes, orderIds)
    else if (kind === "channel")
      root.mixChannels = root._reorderByIds(root.mixChannels, orderIds)
    else if (kind === "input")
      root.mixInputs = root._reorderByIds(root.mixInputs, orderIds)
  }

  function _reorderByIds(list, orderIds) {
    const src = list || []
    const order = orderIds || []
    if (!src.length || !order.length)
      return src
    const byId = {}
    for (let i = 0; i < src.length; i++) {
      const id = src[i] && src[i].id
      if (id)
        byId[id] = src[i]
    }
    const next = []
    const seen = {}
    for (let i = 0; i < order.length; i++) {
      const id = order[i]
      if (byId[id] && !seen[id]) {
        next.push(byId[id])
        seen[id] = true
      }
    }
    for (let i = 0; i < src.length; i++) {
      const id = src[i] && src[i].id
      if (id && !seen[id])
        next.push(src[i])
    }
    return next
  }

  // Cheap dump identity — avoid JSON.stringify of full channel/app trees every poll.
  function _mixDumpFingerprint(d, assign) {
    const ch = d.channels || []
    const inn = d.inputs || []
    const mixes = d.mixes || []
    const apps = d.apps || []
    const srcs = d.availableSources || []
    const parts = [
      d.ok ? 1 : 0,
      d.listening || "",
      d.ok ? "" : (d.error || "")
    ]
    for (let i = 0; i < srcs.length; i++) {
      const s = srcs[i] || {}
      parts.push("s", s.id || s.name, s.label || "")
    }
    for (let i = 0; i < ch.length; i++) {
      const c = ch[i] || {}
      const folder = c.apps || []
      let keys = ""
      for (let j = 0; j < folder.length; j++)
        keys += (folder[j].key || "") + (folder[j].playing ? "*" : "") + ","
      parts.push("c", c.id, c.label, c.volume, c.muted ? 1 : 0, c.count || 0, keys)
      const cells = c.cells || c.routes || {}
      if (typeof cells === "object") {
        for (const mixId of Object.keys(cells)) {
          const cell = cells[mixId] || {}
          parts.push(mixId, cell.on ? 1 : 0, cell.volume, cell.muted ? 1 : 0)
        }
      }
    }
    for (let i = 0; i < inn.length; i++) {
      const c = inn[i] || {}
      parts.push("i", c.id, c.label, c.volume, c.muted ? 1 : 0, c.source || "")
      const cells = c.cells || c.routes || {}
      if (typeof cells === "object") {
        for (const mixId of Object.keys(cells)) {
          const cell = cells[mixId] || {}
          parts.push(mixId, cell.on ? 1 : 0, cell.volume, cell.muted ? 1 : 0)
        }
      }
    }
    for (let i = 0; i < mixes.length; i++) {
      const m = mixes[i] || {}
      parts.push("m", m.id, m.label, m.hear ? 1 : 0)
    }
    for (let i = 0; i < apps.length; i++) {
      const a = apps[i] || {}
      parts.push("a", a.key || a.id, a.channel || a.sink || "", a.volume, a.muted ? 1 : 0)
    }
    for (let i = 0; i < (assign || []).length; i++) {
      const o = assign[i] || {}
      parts.push("o", o.id, o.kind, o.label, o.present === false ? 0 : 1)
    }
    return parts.join("|")
  }

  function _assignMixList(kind, nextList) {
    if (kind === "mix")
      root.mixMixes = nextList || []
    else if (kind === "channel")
      root.mixChannels = nextList || []
    else
      root.mixInputs = nextList || []
  }

  readonly property var mixChannelCatalog: [
    { id: "proteus_mix_system", label: "Apps" },
    { id: "proteus_mix_voice", label: "Voice" },
    { id: "proteus_mix_music", label: "Music" },
    { id: "proteus_mix_browser", label: "Browser" },
    { id: "proteus_mix_game", label: "Game" }
  ]

  function addMixChannel(label) {
    const name = String(label || "").trim()
    if (!name || root.mixBusy)
      return
    root.mixBusy = true
    root.mixError = ""
    root.mixDumpFp = ""
    mixAddChannelProc.command = [
      "python3",
      Config.scriptsDir + "/audio-mix.py",
      "add-channel",
      name
    ]
    mixAddChannelProc.running = false
    mixAddChannelProc.running = true
  }

  function removeMixChannel(channelId) {
    const ch = String(channelId || "").trim()
    if (!ch || root.mixBusy)
      return
    root.mixBusy = true
    root.mixError = ""
    root.mixDumpFp = ""
    mixRemoveChannelProc.command = [
      "python3",
      Config.scriptsDir + "/audio-mix.py",
      "remove-channel",
      ch
    ]
    mixRemoveChannelProc.running = false
    mixRemoveChannelProc.running = true
  }

  readonly property var mixMixCatalog: [
    { id: "monitor", label: "Monitor", hear: true },
    { id: "stream", label: "Stream", hear: false }
  ]

  function addMixBus(label, hear) {
    const name = String(label || "").trim()
    if (!name || root.mixBusy)
      return
    root.mixBusy = true
    root.mixError = ""
    root.mixDumpFp = ""
    const args = [
      "python3",
      Config.scriptsDir + "/audio-mix.py",
      "add-mix",
      name
    ]
    if (hear)
      args.push("--hear")
    mixAddMixProc.command = args
    mixAddMixProc.running = false
    mixAddMixProc.running = true
  }

  function removeMixBus(mixId) {
    const id = String(mixId || "").trim()
    if (!id || root.mixBusy)
      return
    root.mixBusy = true
    root.mixError = ""
    root.mixDumpFp = ""
    mixRemoveMixProc.command = [
      "python3",
      Config.scriptsDir + "/audio-mix.py",
      "remove-mix",
      id
    ]
    mixRemoveMixProc.running = false
    mixRemoveMixProc.running = true
  }

  function renameMixChannel(channelId, label) {
    const ch = String(channelId || "").trim()
    const name = String(label || "").trim()
    if (!ch || !name || root.mixBusy)
      return
    root.mixBusy = true
    root.mixError = ""
    root.mixDumpFp = ""
    mixRenameChannelProc.command = [
      "python3",
      Config.scriptsDir + "/audio-mix.py",
      "rename-channel",
      ch,
      name
    ]
    mixRenameChannelProc.running = false
    mixRenameChannelProc.running = true
  }

  function renameMixBus(mixId, label) {
    const id = String(mixId || "").trim()
    const name = String(label || "").trim()
    if (!id || !name || root.mixBusy)
      return
    root.mixBusy = true
    root.mixError = ""
    root.mixDumpFp = ""
    mixRenameMixProc.command = [
      "python3",
      Config.scriptsDir + "/audio-mix.py",
      "rename-mix",
      id,
      name
    ]
    mixRenameMixProc.running = false
    mixRenameMixProc.running = true
  }

  function renameMixInput(inputId, label) {
    const id = String(inputId || "").trim()
    const name = String(label || "").trim()
    if (!id || !name || root.mixBusy)
      return
    root.mixBusy = true
    root.mixError = ""
    root.mixDumpFp = ""
    mixRenameInputProc.command = [
      "python3",
      Config.scriptsDir + "/audio-mix.py",
      "rename-input",
      id,
      name
    ]
    mixRenameInputProc.running = false
    mixRenameInputProc.running = true
  }

  function moveMixChannel(channelId, index) {
    const ch = String(channelId || "").trim()
    if (!ch || root.mixBusy)
      return
    root.mixError = ""
    mixMoveChannelProc.command = [
      "python3",
      Config.scriptsDir + "/audio-mix.py",
      "move-channel",
      ch,
      String(Math.max(0, Math.round(index)))
    ]
    mixMoveChannelProc.running = false
    mixMoveChannelProc.running = true
  }

  function moveMixBus(mixId, index) {
    const id = String(mixId || "").trim()
    if (!id || root.mixBusy)
      return
    root.mixError = ""
    mixMoveMixProc.command = [
      "python3",
      Config.scriptsDir + "/audio-mix.py",
      "move-mix",
      id,
      String(Math.max(0, Math.round(index)))
    ]
    mixMoveMixProc.running = false
    mixMoveMixProc.running = true
  }

  function moveMixInput(inputId, index) {
    const id = String(inputId || "").trim()
    if (!id || root.mixBusy)
      return
    root.mixError = ""
    mixMoveInputProc.command = [
      "python3",
      Config.scriptsDir + "/audio-mix.py",
      "move-input",
      id,
      String(Math.max(0, Math.round(index)))
    ]
    mixMoveInputProc.running = false
    mixMoveInputProc.running = true
  }

  function listenMixBus(mixId) {
    const id = String(mixId || "").trim()
    if (!id || root.mixBusy)
      return
    root.mixBusy = true
    root.mixError = ""
    root.mixDumpFp = ""
    mixListenProc.command = [
      "python3",
      Config.scriptsDir + "/audio-mix.py",
      "listen",
      id
    ]
    mixListenProc.running = false
    mixListenProc.running = true
  }

  function addMixInput(sourceName, label) {
    const src = String(sourceName || "").trim()
    if (!src || root.mixBusy)
      return
    root.mixBusy = true
    root.mixError = ""
    root.mixDumpFp = ""
    const args = [
      "python3",
      Config.scriptsDir + "/audio-mix.py",
      "add-input",
      src
    ]
    if (label !== undefined && label !== null && String(label).length)
      args.push("--label", String(label))
    mixAddInputProc.command = args
    mixAddInputProc.running = false
    mixAddInputProc.running = true
  }

  function removeMixInput(inputId) {
    const id = String(inputId || "").trim()
    if (!id || root.mixBusy)
      return
    root.mixBusy = true
    root.mixError = ""
    root.mixDumpFp = ""
    mixRemoveInputProc.command = [
      "python3",
      Config.scriptsDir + "/audio-mix.py",
      "remove-input",
      id
    ]
    mixRemoveInputProc.running = false
    mixRemoveInputProc.running = true
  }

  function refreshMix() {
    if (root.mixServeRunning) {
      root._mixCtlWrite("dump")
      return
    }
    mixDumpProc.running = false
    mixDumpProc.running = true
  }

  function _applyMixDump(d) {
    if (!d || typeof d !== "object")
      return
    const assign = (d.assignOptions || []).filter(o => o.kind === "mix" || o.present !== false)
    const fp = root._mixDumpFingerprint(d, assign)
    if (fp === root.mixDumpFp) {
      if (!d.ok)
        root.mixError = d.error || "Could not list apps"
      return
    }
    root.mixDumpFp = fp
    root.mixReady = !!d.ok
    root._assignMixList("channel", d.channels || [])
    root._assignMixList("input", d.inputs || [])
    root.mixAvailableSources = d.availableSources || []
    root._assignMixList("mix", d.mixes || [])
    root.mixListening = d.listening || "system"
    root.mixApps = d.apps || []
    root.mixUnassigned = d.unassigned || []
    root.mixAssignOptions = assign
    if (!d.ok)
      root.mixError = d.error || "Could not list apps"
    else if (!root.mixBusy)
      root.mixError = ""
  }

  function _applyMixPeaksMap(d) {
    if (!d || typeof d !== "object")
      return
    const prev = root.mixPeaks || ({})
    const next = {}
    let changed = false
    const keys = Object.keys(d)
    for (let i = 0; i < keys.length; i++) {
      const k = keys[i]
      const raw = Number(d[k])
      const v = isNaN(raw) ? 0 : Math.max(0, Math.min(100, Math.round(raw / 5) * 5))
      next[k] = v
      if ((prev[k] || 0) !== v)
        changed = true
    }
    const prevKeys = Object.keys(prev)
    if (prevKeys.length !== keys.length)
      changed = true
    if (changed)
      root.mixPeaks = next
  }

  function ensureMixChannels() {
    root.mixBusy = true
    root.mixError = ""
    mixEnsureProc.running = false
    mixEnsureProc.running = true
  }

  // appKey = stable application name; streamId / label / desktopId optional.
  function assignAppToSink(appKey, sinkName, streamId, label, desktopId) {
    const key = String(appKey || "").trim()
    const sink = String(sinkName || "").trim()
    if (!key || !sink || root.mixBusy)
      return
    root.mixBusy = true
    root.mixError = ""
    root.mixDumpFp = ""
    const args = [
      "python3",
      Config.scriptsDir + "/audio-mix.py",
      "assign",
      key,
      sink
    ]
    if (streamId !== undefined && streamId !== null && String(streamId).length)
      args.push("--stream-id", String(streamId))
    if (label !== undefined && label !== null && String(label).length)
      args.push("--label", String(label))
    if (desktopId !== undefined && desktopId !== null && String(desktopId).length)
      args.push("--desktop-id", String(desktopId))
    mixMoveProc.command = args
    mixMoveProc.running = false
    mixMoveProc.running = true
  }

  function unassignApp(appKey) {
    const key = String(appKey || "").trim()
    if (!key || root.mixBusy)
      return
    root.mixBusy = true
    root.mixError = ""
    root.mixDumpFp = ""
    mixUnassignProc.command = [
      "python3",
      Config.scriptsDir + "/audio-mix.py",
      "unassign",
      key
    ]
    mixUnassignProc.running = false
    mixUnassignProc.running = true
  }

  function setMixRoute(channelId, mixId, on) {
    const ch = String(channelId || "").trim()
    const mix = String(mixId || "").trim()
    if (!ch || !mix || root.mixBusy)
      return
    root.mixBusy = true
    root.mixError = ""
    mixRouteProc.command = [
      "python3",
      Config.scriptsDir + "/audio-mix.py",
      "route",
      ch,
      mix,
      on ? "on" : "off"
    ]
    mixRouteProc.running = false
    mixRouteProc.running = true
  }

  function setMixChannelVolume(channelId, pct) {
    const ch = String(channelId || "").trim()
    if (!ch)
      return
    // Volume is live on the slider; don't poke dump until release (UI).
    Quickshell.execDetached({
      command: [
        "python3",
        Config.scriptsDir + "/audio-mix.py",
        "volume",
        ch,
        String(Math.max(0, Math.min(150, Math.round(pct))))
      ]
    })
  }

  function setMixChannelMute(channelId, muted) {
    const ch = String(channelId || "").trim()
    if (!ch || root.mixBusy)
      return
    root.mixBusy = true
    root.mixDumpFp = ""
    mixMuteProc.command = [
      "python3",
      Config.scriptsDir + "/audio-mix.py",
      "mute",
      ch,
      muted ? "1" : "0"
    ]
    mixMuteProc.running = false
    mixMuteProc.running = true
  }

  function setMixCellVolume(channelId, mixId, pct) {
    const ch = String(channelId || "").trim()
    const mix = String(mixId || "").trim()
    if (!ch || !mix)
      return
    Quickshell.execDetached({
      command: [
        "python3",
        Config.scriptsDir + "/audio-mix.py",
        "cell-volume",
        ch,
        mix,
        String(Math.max(0, Math.min(150, Math.round(pct))))
      ]
    })
  }

  function setMixCellMute(channelId, mixId, muted) {
    const ch = String(channelId || "").trim()
    const mix = String(mixId || "").trim()
    if (!ch || !mix || root.mixBusy)
      return
    root.mixBusy = true
    root.mixDumpFp = ""
    mixCellMuteProc.command = [
      "python3",
      Config.scriptsDir + "/audio-mix.py",
      "cell-mute",
      ch,
      mix,
      muted ? "1" : "0"
    ]
    mixCellMuteProc.running = false
    mixCellMuteProc.running = true
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

  // One long-lived parec reader for the default mic. Idles at 0 when capture
  // is unavailable so Settings can keep the meter mounted without respawning.
  Process {
    id: sourcePeakProc
    running: root.sourcePeakSubscribers > 0
    command: [
      "python3",
      Config.scriptsDir + "/audio-peak.py",
      "--device",
      "@DEFAULT_SOURCE@",
      "--window-ms",
      "100"
    ]
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: line => {
        const v = parseInt(String(line).trim(), 10)
        if (!isNaN(v))
          root.sourcePeak = Math.max(0, Math.min(100, v))
      }
    }
  }

  Process {
    id: mixPeaksProc
    running: false
    command: ["true"]
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: line => {
        try {
          const d = JSON.parse(String(line || "").trim() || "{}")
          root._applyMixPeaksMap(d)
        } catch (e) {
        }
      }
    }
  }

  Process {
    id: mixHelperResolveProc
    command: [
      "bash",
      "-c",
      "ROOT=\"" + Config.scriptsDir + "/../..\"; "
          + "for c in \"$ROOT/services/proteus-audio-mix/bin/proteus-audio-mix\" "
          + "\"$ROOT/services/proteus-audio-mix/target/release/proteus-audio-mix\" "
          + "/usr/local/libexec/proteus-audio-mix "
          + "$(command -v proteus-audio-mix 2>/dev/null); do "
          + "if [ -x \"$c\" ]; then printf '%s' \"$c\"; exit 0; fi; done; exit 1"
    ]
    stdout: StdioCollector {
      id: mixHelperResolveOut
    }
    onExited: exitCode => {
      const bin = String(mixHelperResolveOut.text || "").trim()
      if (exitCode === 0 && bin.length) {
        root.mixHelperAvailable = true
        if (root.mixServeConsumers > 0 && !root.mixServeRunning)
          root._launchMixServe(bin)
        return
      }
      root.mixHelperAvailable = false
      root.mixHelperBin = ""
      // No helper — fall back to Python dump poll via refreshMix.
      if (root.mixServeConsumers > 0)
        root.refreshMix()
    }
  }

  Process {
    id: mixServeProc
    running: false
    command: ["true"]
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: line => {
        try {
          const d = JSON.parse(String(line || "").trim() || "{}")
          if (!d || typeof d !== "object")
            return
          if (d.t === "peaks") {
            root._applyMixPeaksMap(d.v || {})
            return
          }
          if (d.t === "dump" || d.ok !== undefined) {
            root._applyMixDump(d)
          }
        } catch (e) {
        }
      }
    }
    onExited: () => {
      root.mixServeRunning = false
      if (root.mixServeStopping) {
        root.mixServeStopping = false
        return
      }
      if (root.mixServeConsumers > 0 && root.mixHelperBin.length) {
        // Brief respawn if leaf still open (crash).
        Qt.callLater(() => {
          if (root.mixServeConsumers > 0 && !root.mixServeRunning && !root.mixServeStopping)
            root._launchMixServe(root.mixHelperBin)
        })
      }
    }
  }

  Process {
    id: mixDumpProc
    command: ["python3", Config.scriptsDir + "/audio-mix.py", "dump"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const d = JSON.parse(String(text || "").trim() || "{}")
          root._applyMixDump(d)
        } catch (e) {
          root.mixReady = false
          root.mixDumpFp = ""
          root.mixChannels = []
          root.mixInputs = []
          root.mixAvailableSources = []
          root.mixMixes = []
          root.mixListening = "system"
          root.mixApps = []
          root.mixUnassigned = []
          root.mixAssignOptions = []
          root.mixError = "Could not parse app mix"
        }
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

  // ── Audio matrix (pw-link / Omnibus-style node grid) ─────────────────────

  property var matrixOutputs: []
  property var matrixInputs: []
  property var matrixCells: ({})
  property string matrixError: ""
  property bool matrixBusy: false
  property bool matrixShowMonitors: false
  property bool matrixOk: false

  function matrixCell(outId, inId) {
    const k = String(outId) + "|" + String(inId)
    const c = root.matrixCells[k]
    if (c)
      return c
    return {
      linked: false,
      partial: false,
      linkIds: [],
      count: 0,
      possible: 0
    }
  }

  function refreshMatrix() {
    const args = ["python3", Config.scriptsDir + "/audio-matrix.py", "dump"]
    if (root.matrixShowMonitors)
      args.push("--monitors")
    matrixDumpProc.command = args
    matrixDumpProc.running = false
    matrixDumpProc.running = true
  }

  function toggleMatrixRoute(outId, inId) {
    if (!outId || !inId || root.matrixBusy)
      return
    const cell = root.matrixCell(outId, inId)
    root.matrixBusy = true
    root.matrixError = ""
    const op = cell.linked ? "unlink" : "link"
    matrixMutateProc.command = [
      "python3",
      Config.scriptsDir + "/audio-matrix.py",
      op,
      String(outId),
      String(inId)
    ]
    matrixMutateProc.running = false
    matrixMutateProc.running = true
  }

  function openGraphEditor() {
    Quickshell.execDetached({
      command: [
        "bash",
        "-lc",
        "if command -v qpwgraph >/dev/null; then exec qpwgraph; "
            + "elif command -v helvum >/dev/null; then exec helvum; "
            + "elif command -v pavucontrol >/dev/null; then exec pavucontrol; "
            + "else exec proteus-terminal -e bash -lc "
            + "'echo Install qpwgraph or helvum for a graph editor; read -r _'; fi"
      ]
    })
  }

  Process {
    id: mixEnsureProc
    command: ["python3", Config.scriptsDir + "/audio-mix.py", "ensure"]
    stdout: StdioCollector {
      id: mixEnsureOut
    }
    onExited: () => {
      root.mixBusy = false
      try {
        const d = JSON.parse(String(mixEnsureOut.text || "").trim() || "{}")
        if (d && d.ok === false)
          root.mixError = d.error || "Could not create mix channels"
        else
          root.mixError = ""
      } catch (e) {
        root.mixError = "Could not create mix channels"
      }
      root.refreshMix()
      root.refreshMatrix()
    }
  }

  Process {
    id: mixMoveProc
    command: ["true"]
    stdout: StdioCollector {
      id: mixMoveOut
    }
    onExited: () => {
      root.mixBusy = false
      root.mixDumpFp = ""
      try {
        const d = JSON.parse(String(mixMoveOut.text || "").trim() || "{}")
        if (d && d.ok === false)
          root.mixError = d.error || "Could not move app"
        else
          root.mixError = ""
      } catch (e) {
      }
      root.refreshMix()
    }
  }

  Process {
    id: mixUnassignProc
    command: ["true"]
    stdout: StdioCollector {
      id: mixUnassignOut
    }
    onExited: () => {
      root.mixBusy = false
      root.mixDumpFp = ""
      try {
        const d = JSON.parse(String(mixUnassignOut.text || "").trim() || "{}")
        if (d && d.ok === false)
          root.mixError = d.error || "Could not remove app"
        else
          root.mixError = ""
      } catch (e) {
      }
      root.refreshMix()
    }
  }

  Process {
    id: mixAddChannelProc
    command: ["true"]
    stdout: StdioCollector {
      id: mixAddChannelOut
    }
    onExited: () => {
      root.mixBusy = false
      root.mixDumpFp = ""
      try {
        const d = JSON.parse(String(mixAddChannelOut.text || "").trim() || "{}")
        if (d && d.ok === false)
          root.mixError = d.error || "Could not add channel"
        else
          root.mixError = ""
      } catch (e) {
      }
      root.refreshMix()
    }
  }

  Process {
    id: mixRemoveChannelProc
    command: ["true"]
    stdout: StdioCollector {
      id: mixRemoveChannelOut
    }
    onExited: () => {
      root.mixBusy = false
      root.mixDumpFp = ""
      try {
        const d = JSON.parse(String(mixRemoveChannelOut.text || "").trim() || "{}")
        if (d && d.ok === false)
          root.mixError = d.error || "Could not remove channel"
        else
          root.mixError = ""
      } catch (e) {
      }
      root.refreshMix()
    }
  }

  Process {
    id: mixRenameChannelProc
    command: ["true"]
    stdout: StdioCollector {
      id: mixRenameChannelOut
    }
    onExited: () => {
      root.mixBusy = false
      root.mixDumpFp = ""
      try {
        const d = JSON.parse(String(mixRenameChannelOut.text || "").trim() || "{}")
        if (d && d.ok === false)
          root.mixError = d.error || "Could not rename channel"
        else
          root.mixError = ""
      } catch (e) {
      }
      root.refreshMix()
    }
  }

  Process {
    id: mixAddMixProc
    command: ["true"]
    stdout: StdioCollector {
      id: mixAddMixOut
    }
    onExited: () => {
      root.mixBusy = false
      root.mixDumpFp = ""
      try {
        const d = JSON.parse(String(mixAddMixOut.text || "").trim() || "{}")
        if (d && d.ok === false)
          root.mixError = d.error || "Could not add mix"
        else
          root.mixError = ""
      } catch (e) {
      }
      root.refreshMix()
    }
  }

  Process {
    id: mixRemoveMixProc
    command: ["true"]
    stdout: StdioCollector {
      id: mixRemoveMixOut
    }
    onExited: () => {
      root.mixBusy = false
      root.mixDumpFp = ""
      try {
        const d = JSON.parse(String(mixRemoveMixOut.text || "").trim() || "{}")
        if (d && d.ok === false)
          root.mixError = d.error || "Could not remove mix"
        else
          root.mixError = ""
      } catch (e) {
      }
      root.refreshMix()
    }
  }

  Process {
    id: mixRenameMixProc
    command: ["true"]
    stdout: StdioCollector {
      id: mixRenameMixOut
    }
    onExited: () => {
      root.mixBusy = false
      root.mixDumpFp = ""
      try {
        const d = JSON.parse(String(mixRenameMixOut.text || "").trim() || "{}")
        if (d && d.ok === false)
          root.mixError = d.error || "Could not rename mix"
        else
          root.mixError = ""
      } catch (e) {
      }
      root.refreshMix()
    }
  }

  Process {
    id: mixListenProc
    command: ["true"]
    stdout: StdioCollector {
      id: mixListenOut
    }
    onExited: () => {
      root.mixBusy = false
      root.mixDumpFp = ""
      try {
        const d = JSON.parse(String(mixListenOut.text || "").trim() || "{}")
        if (d && d.ok === false)
          root.mixError = d.error || "Could not switch listen"
        else
          root.mixError = ""
      } catch (e) {
      }
      root.refreshMix()
    }
  }

  Process {
    id: mixAddInputProc
    command: ["true"]
    stdout: StdioCollector {
      id: mixAddInputOut
    }
    onExited: () => {
      root.mixBusy = false
      root.mixDumpFp = ""
      try {
        const d = JSON.parse(String(mixAddInputOut.text || "").trim() || "{}")
        if (d && d.ok === false)
          root.mixError = d.error || "Could not add input"
        else
          root.mixError = ""
      } catch (e) {
      }
      root.refreshMix()
    }
  }

  Process {
    id: mixRemoveInputProc
    command: ["true"]
    stdout: StdioCollector {
      id: mixRemoveInputOut
    }
    onExited: () => {
      root.mixBusy = false
      root.mixDumpFp = ""
      try {
        const d = JSON.parse(String(mixRemoveInputOut.text || "").trim() || "{}")
        if (d && d.ok === false)
          root.mixError = d.error || "Could not remove input"
        else
          root.mixError = ""
      } catch (e) {
      }
      root.refreshMix()
    }
  }

  Process {
    id: mixRenameInputProc
    command: ["true"]
    stdout: StdioCollector {
      id: mixRenameInputOut
    }
    onExited: () => {
      root.mixBusy = false
      root.mixDumpFp = ""
      try {
        const d = JSON.parse(String(mixRenameInputOut.text || "").trim() || "{}")
        if (d && d.ok === false)
          root.mixError = d.error || "Could not rename input"
        else
          root.mixError = ""
      } catch (e) {
      }
      root.refreshMix()
    }
  }

  Process {
    id: mixMoveChannelProc
    command: ["true"]
    stdout: StdioCollector {
      id: mixMoveChannelOut
    }
    onExited: () => {
      try {
        const d = JSON.parse(String(mixMoveChannelOut.text || "").trim() || "{}")
        if (d && d.ok === false) {
          root.mixError = d.error || "Could not move channel"
          root.refreshMix()
        } else {
          root.mixError = ""
          if (d && d.order && d.order.length) {
            const cur = (root.mixChannels || []).map(c => c && c.id)
            if (cur.join("\n") !== d.order.join("\n"))
              root.applyMixOrder("channel", d.order)
          }
        }
      } catch (e) {
        root.refreshMix()
      }
    }
  }

  Process {
    id: mixMoveMixProc
    command: ["true"]
    stdout: StdioCollector {
      id: mixMoveMixOut
    }
    onExited: () => {
      try {
        const d = JSON.parse(String(mixMoveMixOut.text || "").trim() || "{}")
        if (d && d.ok === false) {
          root.mixError = d.error || "Could not move mix"
          root.refreshMix()
        } else {
          root.mixError = ""
          if (d && d.order && d.order.length) {
            const cur = (root.mixMixes || []).map(m => m && m.id)
            if (cur.join("\n") !== d.order.join("\n"))
              root.applyMixOrder("mix", d.order)
          }
        }
      } catch (e) {
        root.refreshMix()
      }
    }
  }

  Process {
    id: mixMoveInputProc
    command: ["true"]
    stdout: StdioCollector {
      id: mixMoveInputOut
    }
    onExited: () => {
      try {
        const d = JSON.parse(String(mixMoveInputOut.text || "").trim() || "{}")
        if (d && d.ok === false) {
          root.mixError = d.error || "Could not move input"
          root.refreshMix()
        } else {
          root.mixError = ""
          if (d && d.order && d.order.length) {
            const cur = (root.mixInputs || []).map(m => m && m.id)
            if (cur.join("\n") !== d.order.join("\n"))
              root.applyMixOrder("input", d.order)
          }
        }
      } catch (e) {
        root.refreshMix()
      }
    }
  }

  Process {
    id: mixRouteProc
    command: ["true"]
    stdout: StdioCollector {
      id: mixRouteOut
    }
    onExited: () => {
      root.mixBusy = false
      root.mixDumpFp = ""
      try {
        const d = JSON.parse(String(mixRouteOut.text || "").trim() || "{}")
        if (d && d.ok === false)
          root.mixError = d.error || "Could not update route"
        else
          root.mixError = ""
      } catch (e) {
      }
      root.refreshMix()
    }
  }

  Process {
    id: mixMuteProc
    command: ["true"]
    stdout: StdioCollector {
      id: mixMuteOut
    }
    onExited: () => {
      root.mixBusy = false
      root.mixDumpFp = ""
      try {
        const d = JSON.parse(String(mixMuteOut.text || "").trim() || "{}")
        if (d && d.ok === false)
          root.mixError = d.error || "Could not mute channel"
        else
          root.mixError = ""
      } catch (e) {
      }
      root.refreshMix()
    }
  }

  Process {
    id: mixCellMuteProc
    command: ["true"]
    stdout: StdioCollector {
      id: mixCellMuteOut
    }
    onExited: () => {
      root.mixBusy = false
      root.mixDumpFp = ""
      try {
        const d = JSON.parse(String(mixCellMuteOut.text || "").trim() || "{}")
        if (d && d.ok === false)
          root.mixError = d.error || "Could not mute mix cell"
        else
          root.mixError = ""
      } catch (e) {
      }
      root.refreshMix()
    }
  }

  Process {
    id: matrixDumpProc
    command: ["true"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const d = JSON.parse(String(text || "").trim() || "{}")
          root.matrixOk = !!d.ok
          root.matrixOutputs = d.outputs || []
          root.matrixInputs = d.inputs || []
          root.matrixCells = d.cells || {}
          if (!d.ok)
            root.matrixError = d.error || "Could not read PipeWire graph"
          else if (!root.matrixBusy)
            root.matrixError = ""
        } catch (e) {
          root.matrixOk = false
          root.matrixOutputs = []
          root.matrixInputs = []
          root.matrixCells = {}
          root.matrixError = "Could not parse audio matrix"
        }
      }
    }
  }

  Process {
    id: matrixMutateProc
    command: ["true"]
    stdout: StdioCollector {
      id: matrixMutateOut
    }
    stderr: StdioCollector {
      id: matrixMutateErr
    }
    onExited: (exitCode, exitStatus) => {
      root.matrixBusy = false
      try {
        const d = JSON.parse(String(matrixMutateOut.text || "").trim() || "{}")
        if (d && d.ok === false && d.error)
          root.matrixError = String(d.error)
        else
          root.matrixError = ""
      } catch (e) {
        const err = matrixMutateErr.text.trim().split("\n")[0] || ""
        if (exitCode !== 0 && err.length)
          root.matrixError = err
      }
      root.refreshMatrix()
    }
  }
}
