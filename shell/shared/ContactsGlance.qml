pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Online accounts → contacts for menu-bar CalendarPanel glance.
// Fact: CardDAV seats via proteus-accounts; fetch via proteus-contacts-glance.py.
// Create/update/delete via proteus-contacts-mutate.py (CardDAV + Apple Basic auth).
Singleton {
  id: root

  property bool busy: false
  property bool mutating: false
  property string error: ""
  property string hint: ""
  property var contacts: []
  property int seats: 0
  property int mutableSeats: 0
  property int rev: 0

  readonly property string script: Config.scriptsDir + "/proteus-contacts-glance.py"
  readonly property string mutateScript: Config.scriptsDir + "/proteus-contacts-mutate.py"

  readonly property bool hasSeats: seats > 0
  readonly property bool hasContacts: (contacts || []).length > 0
  readonly property bool canCreate: mutableSeats > 0

  function refresh() {
    root.busy = true
    root.error = ""
    fetchProc.command = ["python3", root.script, "--limit", "5"]
    fetchProc.running = false
    fetchProc.running = true
  }

  function contactLabel(c) {
    if (!c)
      return ""
    const name = String(c.name || "").trim()
    const email = String(c.email || "").trim()
    if (name.length && email.length)
      return name + " · " + email
    return name || email || ""
  }

  function isMutable(c) {
    if (!c)
      return false
    if (c.mutable === true)
      return String(c.href || "").length > 0
    return false
  }

  function createContact(name, email) {
    if (!root.canCreate || root.mutating)
      return false
    const n = String(name || "").trim()
    if (!n.length)
      return false
    root.mutating = true
    root.error = ""
    mutateProc.command = [
      "python3", root.mutateScript, "create",
      "--name", n,
      "--email", String(email || "").trim()
    ]
    mutateProc.running = false
    mutateProc.running = true
    return true
  }

  function updateContact(c, name, email) {
    if (!root.isMutable(c) || root.mutating)
      return false
    const n = String(name || "").trim()
    if (!n.length)
      return false
    root.mutating = true
    root.error = ""
    mutateProc.command = [
      "python3", root.mutateScript, "update",
      "--provider", String(c.provider || ""),
      "--href", String(c.href || ""),
      "--uid", String(c.uid || c.id || ""),
      "--name", n,
      "--email", String(email || "").trim()
    ]
    mutateProc.running = false
    mutateProc.running = true
    return true
  }

  function deleteContact(c) {
    if (!root.isMutable(c) || root.mutating)
      return false
    root.mutating = true
    root.error = ""
    mutateProc.command = [
      "python3", root.mutateScript, "delete",
      "--provider", String(c.provider || ""),
      "--href", String(c.href || "")
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
            root.error = String(data.error || "Could not load contacts")
            root.contacts = []
            root.seats = 0
            root.mutableSeats = 0
            root.rev++
            return
          }
          root.contacts = Array.isArray(data.contacts) ? data.contacts : []
          root.seats = Math.max(0, Math.round(Number(data.seats) || 0))
          root.mutableSeats = Math.max(0, Math.round(Number(data.mutableSeats) || 0))
          root.hint = String(data.hint || "")
          const errs = data.errors || []
          root.error = (errs.length && !root.contacts.length)
              ? String(errs[0])
              : ""
          root.rev++
        } catch (e) {
          root.error = "Could not parse contacts glance"
          root.contacts = []
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
            root.error = String(data.error || "Contact update failed")
            root.rev++
            return
          }
          root.refresh()
        } catch (e) {
          root.error = "Could not parse contacts mutate"
          root.rev++
        }
      }
    }
  }
}
