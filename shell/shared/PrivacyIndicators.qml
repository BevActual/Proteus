pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Menu-bar privacy dots — mic / camera / screen capture in use.
// Best-effort probe (privacy-indicators.py); grant store is Permissions.qml.
// Mid-session Ask: new mic/camera/screen activity with per-app Ask → PrivacyAsk.promptCapture.
Singleton {
  id: root

  property bool mic: false
  property bool camera: false
  property bool screen: false
  property var apps: []
  // Keys "appId\tkind" already offered a mid-session Ask this session.
  property var promptedCaptureKeys: ({})
  property var prevActivityKeys: ({})

  readonly property bool anyActive: mic || camera || screen

  // macOS-adjacent indicator colors
  readonly property color micColor: "#ff9f0a"
  readonly property color cameraColor: "#30d158"
  readonly property color screenColor: "#bf5af2"

  function refresh() {
    probe.running = false
    probe.running = true
  }

  function appsForKind(kind) {
    const k = String(kind || "")
    const out = []
    const list = root.apps || []
    for (let i = 0; i < list.length; i++) {
      if (String(list[i].kind) === k)
        out.push(list[i])
    }
    return out
  }

  function openPrivacySettings() {
    ShellState.openSettings(anyActive ? "privacy-activity" : "privacy")
  }

  function activityKey(app) {
    const id = Permissions.normalizeAppId(app && app.id)
    const kind = String((app && app.kind) || "")
    if (!id.length || !kind.length)
      return ""
    return id + "\t" + kind
  }

  function maybePromptCapture(list) {
    const nextPrev = ({})
    const prompted = Object.assign({}, root.promptedCaptureKeys)
    for (let i = 0; i < list.length; i++) {
      const a = list[i]
      const kind = String(a.kind || "")
      if (kind !== "microphone" && kind !== "camera" && kind !== "screen")
        continue
      const key = root.activityKey(a)
      if (!key.length)
        continue
      nextPrev[key] = true
      const id = Permissions.normalizeAppId(a.id)
      if (!Permissions.isAsk(id, kind))
        continue
      if (prompted[key])
        continue
      // Edge: first time we see this Ask capture this session (or after idle).
      if (!root.prevActivityKeys[key]) {
        if (PrivacyAsk.promptCapture(id, kind, String(a.label || id)))
          prompted[key] = true
      }
    }
    root.prevActivityKeys = nextPrev
    root.promptedCaptureKeys = prompted
  }

  Timer {
    interval: 2500
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // Best-effort capture enforce — pause while Ask dialog open so mid-session
  // Allow once can land before mute/destroy; session file covers Allow once.
  Timer {
    interval: 5000
    running: true
    repeat: true
    triggeredOnStart: false
    onTriggered: {
      if (PrivacyAsk.visible)
        return
      enforceProc.running = false
      enforceProc.running = true
    }
  }

  Process {
    id: probe
    command: ["python3", Config.scriptsDir + "/privacy-indicators.py"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const data = JSON.parse(String(text).trim())
          root.mic = !!data.mic
          root.camera = !!data.camera
          root.screen = !!data.screen
          root.apps = data.apps || []
          try {
            Permissions.activityApps = root.apps
          } catch (e) {
          }
          root.maybePromptCapture(root.apps)
        } catch (e) {
          // Keep last known state on parse blips
        }
      }
    }
  }

  Process {
    id: enforceProc
    command: ["python3", Config.scriptsDir + "/proteus-permissions.py", "enforce-capture"]
  }
}
