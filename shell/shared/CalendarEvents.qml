pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Online accounts → day's events for menu-bar CalendarPanel glance.
// Fact: seats via proteus-accounts; fetch via proteus-calendar-events.py.
// Create/update/delete via proteus-calendar-mutate.py (CalDAV + Google/MS/Exchange).
Singleton {
  id: root

  property bool busy: false
  property bool mutating: false
  property string error: ""
  property string hint: ""
  property string dateIso: ""
  property var events: []
  property int seats: 0
  property int mutableSeats: 0
  property int rev: 0
  property string pendingDayIso: ""

  readonly property string script: Config.scriptsDir + "/proteus-calendar-events.py"
  readonly property string mutateScript: Config.scriptsDir + "/proteus-calendar-mutate.py"

  readonly property bool hasSeats: seats > 0
  readonly property bool hasEvents: (events || []).length > 0
  readonly property bool canCreate: mutableSeats > 0

  function refresh(dayIso) {
    const d = String(dayIso || "").trim()
    root.pendingDayIso = d
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
    const m = s.match(/T(\d{2}):(\d{2})/) || s.match(/T(\d{2})(\d{2})/)
    if (m)
      return m[1] + ":" + m[2]
    return ""
  }

  function isMutable(ev) {
    if (!ev)
      return false
    if (ev.mutable === true)
      return String(ev.href || "").length > 0
    return false
  }

  function createEvent(title, dayIso, recurrence) {
    if (!root.canCreate || root.mutating)
      return false
    const t = String(title || "").trim()
    if (!t.length)
      return false
    const d = String(dayIso || root.dateIso || "").trim()
    const r = String(recurrence || "").trim().toLowerCase()
    root.mutating = true
    root.error = ""
    const args = ["python3", root.mutateScript, "create", "--title", t]
    if (d.length)
      args.push("--date", d)
    if (r.length && r !== "none")
      args.push("--recurrence", r)
    mutateProc.command = args
    mutateProc.running = false
    mutateProc.running = true
    return true
  }

  function updateEvent(ev, title, dayIso) {
    if (!root.isMutable(ev) || root.mutating)
      return false
    const t = String(title || "").trim()
    if (!t.length)
      return false
    const d = String(dayIso || root.dateIso || "").trim()
    root.mutating = true
    root.error = ""
    const args = [
      "python3", root.mutateScript, "update",
      "--provider", String(ev.provider || ""),
      "--href", String(ev.href || ""),
      "--uid", String(ev.id || ev.uid || ""),
      "--title", t
    ]
    if (d.length)
      args.push("--date", d)
    mutateProc.command = args
    mutateProc.running = false
    mutateProc.running = true
    return true
  }

  function deleteEvent(ev) {
    if (!root.isMutable(ev) || root.mutating)
      return false
    root.mutating = true
    root.error = ""
    mutateProc.command = [
      "python3", root.mutateScript, "delete",
      "--provider", String(ev.provider || ""),
      "--href", String(ev.href || "")
    ]
    mutateProc.running = false
    mutateProc.running = true
    return true
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
            root.mutableSeats = 0
            root.rev++
            return
          }
          root.dateIso = String(data.date || "")
          root.events = Array.isArray(data.events) ? data.events : []
          root.seats = Math.max(0, Math.round(Number(data.seats) || 0))
          root.mutableSeats = Math.max(0, Math.round(Number(data.mutableSeats) || 0))
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

  Process {
    id: mutateProc
    command: ["true"]
    stdout: StdioCollector {
      onStreamFinished: {
        root.mutating = false
        try {
          const data = JSON.parse(String(text).trim() || "{}")
          if (data.ok === false) {
            root.error = String(data.error || "Calendar update failed")
            root.rev++
            return
          }
          root.refresh(root.pendingDayIso || root.dateIso)
        } catch (e) {
          root.error = "Could not parse calendar mutate"
          root.rev++
        }
      }
    }
  }
}
