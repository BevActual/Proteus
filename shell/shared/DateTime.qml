pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Clock, timezone and locale — thin wrapper over timedatectl / localectl.
//
// Mutations go through timedatectl, which is polkit-gated. An inactive session
// (or a host with no polkit agent) will be refused, so writes run through a
// Process and surface stderr rather than fire-and-forget.
Singleton {
  id: root

  property string timezone: ""
  property bool ntp: false
  property bool ntpSynced: false
  property bool localRtc: false
  property bool canNtp: false
  property string timeText: ""
  property string locale: ""
  property string vcKeymap: ""

  property var timezones: []
  property bool loadingZones: false
  property bool busy: false
  property string error: ""

  readonly property string ntpStatus: {
    if (!root.ntp)
      return "Off — clock set manually"
    return root.ntpSynced ? "On — synchronized" : "On — not yet synchronized"
  }

  function refresh() {
    showProc.running = false
    showProc.running = true
    localeProc.running = false
    localeProc.running = true
  }

  function loadTimezones() {
    if (loadingZones || timezones.length)
      return
    loadingZones = true
    zonesProc.running = false
    zonesProc.running = true
  }

  // Filtered zone list for the picker. Matches on any path segment so "york"
  // finds America/New_York.
  function searchTimezones(query, limit) {
    const q = String(query || "").trim().toLowerCase().replace(/\s+/g, "_")
    const cap = limit || 40
    const list = root.timezones
    const out = []
    for (let i = 0; i < list.length && out.length < cap; i++) {
      const tz = list[i]
      if (!q.length || tz.toLowerCase().indexOf(q) >= 0)
        out.push(tz)
    }
    return out
  }

  function setTimezone(tz) {
    const name = String(tz || "").trim()
    if (!name.length || name === root.timezone)
      return
    root.busy = true
    root.error = ""
    setProc.command = ["timedatectl", "set-timezone", name]
    setProc.running = false
    setProc.running = true
  }

  function setNtp(on) {
    root.busy = true
    root.error = ""
    setProc.command = ["timedatectl", "set-ntp", on ? "true" : "false"]
    setProc.running = false
    setProc.running = true
  }

  function openLocaleConf() {
    Quickshell.execDetached({
      command: ["bash", "-lc", "(command -v xdg-open >/dev/null && xdg-open /etc/locale.conf) || exec foot -e less /etc/locale.conf"]
    })
  }

  Process {
    id: showProc
    command: ["timedatectl", "show"]
    stdout: StdioCollector {
      onStreamFinished: {
        const map = {}
        const lines = text.trim().split("\n")
        for (let i = 0; i < lines.length; i++) {
          const eq = lines[i].indexOf("=")
          if (eq > 0)
            map[lines[i].slice(0, eq)] = lines[i].slice(eq + 1)
        }
        root.timezone = map["Timezone"] || ""
        root.ntp = map["NTP"] === "yes"
        root.ntpSynced = map["NTPSynchronized"] === "yes"
        root.localRtc = map["LocalRTC"] === "yes"
        root.canNtp = map["CanNTP"] === "yes"
        root.timeText = map["TimeUSec"] || ""
      }
    }
  }

  Process {
    id: localeProc
    command: ["localectl", "status"]
    stdout: StdioCollector {
      onStreamFinished: {
        const langM = text.match(/LANG=([^\s]+)/)
        const kbM = text.match(/VC Keymap:\s*([^\s]+)/)
        root.locale = langM ? langM[1] : ""
        root.vcKeymap = (kbM && kbM[1] !== "(unset)") ? kbM[1] : ""
      }
    }
  }

  Process {
    id: zonesProc
    command: ["timedatectl", "list-timezones"]
    stdout: StdioCollector {
      onStreamFinished: {
        root.loadingZones = false
        root.timezones = text.trim().split("\n").filter(l => l.length)
      }
    }
  }

  Process {
    id: setProc
    command: ["true"]
    stderr: StdioCollector {
      id: setErr
    }
    onExited: (exitCode, exitStatus) => {
      root.busy = false
      if (exitCode === 0) {
        root.error = ""
        root.refresh()
        return
      }
      const e = setErr.text.trim().split("\n")[0]
      // timedatectl is polkit-gated; without an agent this is the usual failure.
      root.error = e.length ? e : "Change refused (needs authorization)"
    }
  }

  Component.onCompleted: refresh()

  // Keep NTP-sync state fresh without polling hard.
  Timer {
    interval: 30000
    repeat: true
    running: true
    onTriggered: {
      showProc.running = false
      showProc.running = true
    }
  }
}
