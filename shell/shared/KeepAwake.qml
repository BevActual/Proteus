pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Temporary keep-awake (Amphetamine-style) — Control Center + menu-bar indicator.
// Holds systemd-inhibit idle:sleep so hypridle / logind skip idle lock & sleep.
Singleton {
  id: root

  // off | 5m | 10m | 15m | 30m | 1h | 2h | 3h | 5h | indefinite
  property string mode: "off"
  property bool active: mode !== "off"
  property double endsAtMs: 0
  property int clock: 0
  // Bumped on every start/stop so late Process.onExited cannot clear a fresh hold.
  property int inhibitGen: 0

  readonly property string label: {
    if (!root.active)
      return "Off"
    if (root.mode === "indefinite")
      return "Until turned off"
    return root.remainingLabel + " left"
  }

  readonly property string shortLabel: {
    if (!root.active)
      return "Off"
    if (root.mode === "indefinite")
      return "On"
    return root.remainingLabel
  }

  readonly property string remainingLabel: {
    void root.clock
    if (!root.active || root.mode === "indefinite" || root.endsAtMs <= 0)
      return ""
    const sec = Math.max(0, Math.ceil((root.endsAtMs - Date.now()) / 1000))
    const h = Math.floor(sec / 3600)
    const m = Math.floor((sec % 3600) / 60)
    if (h > 0)
      return h + "h " + m + "m"
    if (m > 0)
      return m + "m"
    return sec + "s"
  }

  readonly property var modes: [
    { id: "5m", secs: 5 * 60, title: "5 minutes" },
    { id: "10m", secs: 10 * 60, title: "10 minutes" },
    { id: "15m", secs: 15 * 60, title: "15 minutes" },
    { id: "30m", secs: 30 * 60, title: "30 minutes" },
    { id: "1h", secs: 60 * 60, title: "1 hour" },
    { id: "2h", secs: 2 * 60 * 60, title: "2 hours" },
    { id: "3h", secs: 3 * 60 * 60, title: "3 hours" },
    { id: "5h", secs: 5 * 60 * 60, title: "5 hours" },
    { id: "indefinite", secs: 0, title: "Until turned off" }
  ]

  // Menu rows including Off (for Control Center popup).
  readonly property var menuOptions: {
    const rows = [{ id: "off", secs: -1, title: "Off" }]
    for (let i = 0; i < root.modes.length; i++)
      rows.push(root.modes[i])
    return rows
  }

  function start(modeId) {
    let id = String(modeId || "indefinite")
    if (id === "off") {
      root.stop()
      return
    }
    let secs = 0
    let found = false
    for (let i = 0; i < root.modes.length; i++) {
      if (root.modes[i].id === id) {
        secs = root.modes[i].secs
        found = true
        break
      }
    }
    if (!found) {
      id = "indefinite"
      secs = 0
    }

    root.mode = id
    root.endsAtMs = secs > 0 ? (Date.now() + secs * 1000) : 0
    tick.restart()
    _restartInhibit()
  }

  function stop() {
    root.inhibitGen++
    root.mode = "off"
    root.endsAtMs = 0
    tick.stop()
    inhibitProc.running = false
  }

  function select(modeId) {
    const id = String(modeId || "off")
    if (id === "off" || !id.length)
      root.stop()
    else
      root.start(id)
  }

  // Spotlight / legacy: toggle indefinite on/off (does not cycle durations).
  function toggle() {
    if (root.active)
      root.stop()
    else
      root.start("indefinite")
  }

  // Spotlight: open next duration without landing on Off until the end of the list.
  // Prefer Control Center menu; this stays for Actions.
  function cycle() {
    if (!root.active) {
      root.start("5m")
      return
    }
    for (let i = 0; i < root.modes.length; i++) {
      if (root.modes[i].id === root.mode) {
        if (i + 1 < root.modes.length)
          root.start(root.modes[i + 1].id)
        else
          root.stop()
        return
      }
    }
    root.start("5m")
  }

  function _restartInhibit() {
    const gen = ++root.inhibitGen
    inhibitProc.running = false
    restartTimer.gen = gen
    restartTimer.restart()
  }

  Timer {
    id: restartTimer
    property int gen: 0
    interval: 40
    repeat: false
    onTriggered: {
      if (root.active && root.inhibitGen === restartTimer.gen)
        inhibitProc.running = true
    }
  }

  Timer {
    id: tick
    interval: 1000
    repeat: true
    running: false
    onTriggered: {
      root.clock++
      if (root.mode !== "off" && root.mode !== "indefinite" && root.endsAtMs > 0
          && Date.now() >= root.endsAtMs) {
        root.stop()
      }
    }
  }

  Process {
    id: inhibitProc
    // hypridle honors systemd idle inhibitors by default (ignore_systemd_inhibit=false).
    command: [
      "systemd-inhibit",
      "--what=idle:sleep",
      "--who=Proteus",
      "--why=Keep awake",
      "--mode=block",
      "sleep",
      "infinity"
    ]
    running: false
    // Do not clear mode from onExited — late exits after restart were flipping
    // Keep Awake off immediately on click. Duration timer + explicit stop are SoT.
  }
}
