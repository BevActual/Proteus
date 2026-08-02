pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Online accounts → unread/recent mail for menu-bar CalendarPanel glance.
// Fact: seats via proteus-accounts; fetch via proteus-mail-glance.py;
// send via proteus-mail-send.py (To/Subject/Body thin).
Singleton {
  id: root

  property bool busy: false
  property bool sending: false
  property string error: ""
  property string sendError: ""
  property string hint: ""
  property int unread: 0
  property var messages: []
  property int seats: 0
  property int sendableSeats: 0
  property int rev: 0

  property string composeTo: ""
  property string composeSubject: ""
  property string composeBody: ""

  readonly property string script: Config.scriptsDir + "/proteus-mail-glance.py"
  readonly property string sendScript: Config.scriptsDir + "/proteus-mail-send.py"

  readonly property bool hasSeats: seats > 0
  readonly property bool hasMessages: (messages || []).length > 0
  readonly property bool canSend: sendableSeats > 0

  function refresh() {
    root.busy = true
    root.error = ""
    fetchProc.command = ["python3", root.script, "--limit", "5"]
    fetchProc.running = false
    fetchProc.running = true
    providersProc.command = ["python3", root.sendScript, "providers"]
    providersProc.running = false
    providersProc.running = true
  }

  function fromLabel(msg) {
    if (!msg)
      return ""
    const f = String(msg.from || "").trim()
    if (!f.length)
      return ""
    // "Name <addr>" → Name
    const m = f.match(/^([^<]+)</)
    if (m)
      return m[1].trim()
    return f
  }

  function sendMessage(toAddr, subject, body) {
    if (!root.canSend || root.sending)
      return false
    const to = String(toAddr !== undefined ? toAddr : root.composeTo).trim()
    const sub = String(subject !== undefined ? subject : root.composeSubject).trim()
    const bod = String(body !== undefined ? body : root.composeBody)
    if (!to.length || !sub.length)
      return false
    root.sending = true
    root.sendError = ""
    sendProc.command = [
      "python3", root.sendScript, "send",
      "--to", to,
      "--subject", sub,
      "--body", bod
    ]
    sendProc.running = false
    sendProc.running = true
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
            root.error = String(data.error || "Could not load mail")
            root.messages = []
            root.unread = 0
            root.seats = 0
            root.rev++
            return
          }
          root.unread = Math.max(0, Math.round(Number(data.unread) || 0))
          root.messages = Array.isArray(data.messages) ? data.messages : []
          root.seats = Math.max(0, Math.round(Number(data.seats) || 0))
          root.hint = String(data.hint || "")
          const errs = data.errors || []
          root.error = (errs.length && !root.messages.length)
              ? String(errs[0])
              : ""
          root.rev++
        } catch (e) {
          root.error = "Could not parse mail glance"
          root.messages = []
          root.rev++
        }
      }
    }
  }

  Process {
    id: providersProc
    command: ["true"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const data = JSON.parse(String(text).trim() || "{}")
          root.sendableSeats = data.ok === false
              ? 0
              : Math.max(0, Math.round(Number(data.sendableSeats) || 0))
          root.rev++
        } catch (e) {
          root.sendableSeats = 0
        }
      }
    }
  }

  Process {
    id: sendProc
    command: ["true"]
    stdout: StdioCollector {
      onStreamFinished: {
        root.sending = false
        try {
          const data = JSON.parse(String(text).trim() || "{}")
          if (data.ok === false) {
            root.sendError = String(data.error || "Send failed")
            root.rev++
            return
          }
          root.composeTo = ""
          root.composeSubject = ""
          root.composeBody = ""
          root.sendError = ""
          root.refresh()
        } catch (e) {
          root.sendError = "Could not parse mail send"
          root.rev++
        }
      }
    }
  }
}
