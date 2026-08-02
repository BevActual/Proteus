pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Online accounts → contacts for menu-bar CalendarPanel glance.
// Fact: CardDAV seats via proteus-accounts; fetch via proteus-contacts-glance.py.
Singleton {
  id: root

  property bool busy: false
  property string error: ""
  property string hint: ""
  property var contacts: []
  property int seats: 0
  property int rev: 0

  readonly property string script: Config.scriptsDir + "/proteus-contacts-glance.py"

  readonly property bool hasSeats: seats > 0
  readonly property bool hasContacts: (contacts || []).length > 0

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
            root.rev++
            return
          }
          root.contacts = Array.isArray(data.contacts) ? data.contacts : []
          root.seats = Math.max(0, Math.round(Number(data.seats) || 0))
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
}
