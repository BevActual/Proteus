pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Lightweight status for the menu-bar system-services cluster.
// Wi‑Fi / Bluetooth / volume — Control Center owns deep controls; this just
// mirrors state so the bar stays honest when CC is closed.
Singleton {
  id: root

  property bool wifiSupported: false
  property bool wifiEnabled: false
  property bool btAvailable: false
  property bool btPowered: false
  property string netSummary: ""
  property string netKind: "" // wifi | ethernet | other | ""
  property bool connected: false

  property int volume: 50
  property bool muted: false

  readonly property bool networkVisible: wifiSupported || connected
  readonly property bool bluetoothVisible: btAvailable

  function refresh() {
    radioProc.running = false
    radioProc.running = true
    netProc.running = false
    netProc.running = true
    Audio.getVolume(v => {
      root.volume = Math.max(0, Math.min(150, Math.round(v)))
    })
    Audio.getMute(m => {
      root.muted = !!m
    })
  }

  Timer {
    interval: 4000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Process {
    id: radioProc
    command: [
      "bash",
      "-lc",
      "echo WIFI=$(nmcli -t radio wifi 2>/dev/null || echo none); "
          + "if command -v bluetoothctl >/dev/null 2>&1; then "
          + "  bt=$(timeout 2 bluetoothctl show 2>/dev/null); "
          + "  if echo \"$bt\" | grep -q '^Controller '; then "
          + "    echo BT=yes; "
          + "    echo \"$bt\" | grep -q 'Powered: yes' && echo BTPOW=yes || echo BTPOW=no; "
          + "  else echo BT=no; fi; "
          + "else echo BT=no; fi"
    ]
    stdout: StdioCollector {
      onStreamFinished: {
        const lines = String(text).trim().split("\n")
        for (let i = 0; i < lines.length; i++) {
          const l = lines[i].trim()
          if (l.indexOf("WIFI=") === 0)
            root.wifiEnabled = l === "WIFI=enabled"
          else if (l === "BT=yes")
            root.btAvailable = true
          else if (l === "BT=no")
            root.btAvailable = false
          else if (l.indexOf("BTPOW=") === 0)
            root.btPowered = l === "BTPOW=yes"
        }
      }
    }
  }

  Process {
    id: netProc
    command: ["nmcli", "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "dev", "status"]
    stdout: StdioCollector {
      onStreamFinished: {
        const lines = String(text).trim().split("\n").filter(l => l.length)
        let best = ""
        let kind = ""
        let sawWifi = false
        let connected = false
        for (let i = 0; i < lines.length; i++) {
          const p = lines[i].split(":")
          if (p.length < 3)
            continue
          const type = p[1]
          const state = p[2]
          const conn = p.length > 3 ? p.slice(3).join(":") : ""
          if (type === "wifi")
            sawWifi = true
          if (state.indexOf("connected") >= 0 && state.indexOf("disconnected") < 0) {
            connected = true
            if (type === "wifi") {
              best = conn.length ? conn : "Wi‑Fi"
              kind = "wifi"
              break
            }
            if (type === "ethernet" && kind !== "wifi") {
              best = conn.length ? conn : "Ethernet"
              kind = "ethernet"
            } else if (!kind.length) {
              best = conn.length ? conn : type
              kind = "other"
            }
          }
        }
        root.wifiSupported = sawWifi
        root.connected = connected
        root.netKind = kind
        root.netSummary = best
      }
    }
  }
}
