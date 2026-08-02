pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Menu-bar privacy dots — mic / camera / screen capture in use.
// Best-effort probe (privacy-indicators.py); grant store is Permissions.qml.
Singleton {
  id: root

  property bool mic: false
  property bool camera: false
  property bool screen: false
  property var apps: []

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

  Timer {
    interval: 2500
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
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
        } catch (e) {
          // Keep last known state on parse blips
        }
      }
    }
  }
}
