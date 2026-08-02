pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Online accounts → today's events for menu-bar CalendarPanel glance.
// Fact: seats via proteus-accounts; fetch via proteus-calendar-events.py.
Singleton {
  id: root

  property bool busy: false
  property string error: ""
  property string hint: ""
  property string dateIso: ""
  property var events: []
  property int seats: 0
  property int rev: 0

  readonly property string script: Config.scriptsDir + "/proteus-calendar-events.py"

  readonly property bool hasSeats: seats > 0
  readonly property bool hasEvents: (events || []).length > 0

  function refresh(dayIso) {
    const d = String(dayIso || "").trim()
    root.busy = true
    root.error = ""
    const args = ["python3", root.script]
    if (d.length)
      args.push("--date", d)
    fetchProc.command = args
    fetchProc.running = false
    fetchProc.running = true
  }

  function refreshForDate(jsDate) {
    if (!jsDate)
      return root.refresh("")
    const y = jsDate.getFullYear()
    const m = ("0" + (jsDate.getMonth() + 1)).slice(-2)
    const d = ("0" + jsDate.getDate()).slice(-2)
    root.refresh(y + "-" + m + "-" + d)
  }

  function timeLabel(ev) {
    if (!ev)
      return ""
    if (ev.allDay)
      return "All day"
    const s = String(ev.start || "")
    // 2026-08-01T09:00:00Z or 20260801T090000Z
    const m = s.match(/T(\d{2}):(\d{2})/) || s.match(/T(\d{2})(\d{2})/)
    if (m)
      return m[1] + ":" + m[2]
    return ""
  }

  Process {
    id: fetchProc
    command: ["true"]
    stdout: StdioCollector {
      onStreamFinished: {
        root.busy = false
        try {
          const data = JSON.parse(String(text).trim() || "{}")
          if (data.ok === false) {
            root.error = String(data.error || "Could not load events")
            root.events = []
            root.seats = 0
            root.rev++
            return
          }
          root.dateIso = String(data.date || "")
          root.events = Array.isArray(data.events) ? data.events : []
          root.seats = Math.max(0, Math.round(Number(data.seats) || 0))
          root.hint = String(data.hint || "")
          const errs = data.errors || []
          root.error = (errs.length && !root.events.length)
              ? String(errs[0])
              : ""
          root.rev++
        } catch (e) {
          root.error = "Could not parse calendar events"
          root.events = []
          root.rev++
        }
      }
    }
  }
}
