import Quickshell
import Quickshell.Io
import QtQuick

// Thin Wi‑Fi scan/connect helper for Console Settings face (nmcli · shared Facts).
// Scope (not QtObject) — child Process objects need a default property.
Scope {
  id: root

  property var networks: []
  property bool busy: false
  property string error: ""
  property string wifiDevice: ""

  function rescan() {
    root.busy = true
    root.error = ""
    wifiListProc.running = false
    wifiListProc.running = true
    wifiDevProc.running = false
    wifiDevProc.running = true
  }

  function connectOpen(ssid) {
    Config.wifiConnect(ssid)
    root.busy = true
    Qt.callLater(function () {
      SystemServices.refresh()
      root.busy = false
    })
  }

  function connectPassword(ssid, password) {
    Config.wifiConnectPassword(ssid, password)
    root.busy = true
    Qt.callLater(function () {
      SystemServices.refresh()
      root.busy = false
    })
  }

  function disconnectWifi() {
    const dev = String(root.wifiDevice || "").trim()
    if (dev.length)
      Config.wifiDisconnect(dev)
    else
      Quickshell.execDetached({
        command: ["bash", "-lc", "nmcli -t -f DEVICE,TYPE,STATE device status 2>/dev/null | awk -F: '$2==\"wifi\" && $3 ~ /connected/ {print $1; exit}' | xargs -r nmcli device disconnect"]
      })
    Qt.callLater(function () {
      SystemServices.refresh()
      root.rescan()
    })
  }

  function isOpenSecurity(sec) {
    const s = String(sec || "").trim().toUpperCase()
    return !s.length || s === "--" || s === "NONE" || s.indexOf("OPEN") >= 0
  }

  Process {
    id: wifiDevProc
    command: ["bash", "-lc", "nmcli -t -f DEVICE,TYPE,STATE device status 2>/dev/null | awk -F: '$2==\"wifi\" {print $1; exit}' || true"]
    stdout: StdioCollector {
      onStreamFinished: {
        root.wifiDevice = String(text || "").trim().split("\n")[0] || ""
      }
    }
  }

  Process {
    id: wifiListProc
    command: [
      "bash", "-lc",
      "nmcli device wifi rescan >/dev/null 2>&1; "
          + "nmcli -t -f ACTIVE,SSID,SIGNAL,SECURITY device wifi list 2>/dev/null | head -n 32 || true"
    ]
    stdout: StdioCollector {
      onStreamFinished: {
        const lines = String(text || "").split("\n")
        const out = []
        const seen = {}
        for (let i = 0; i < lines.length; i++) {
          const line = lines[i].trim()
          if (!line.length)
            continue
          // ACTIVE:SSID:SIGNAL:SECURITY — SSID may contain colons rarely; take first/last carefully
          const parts = line.split(":")
          if (parts.length < 3)
            continue
          const active = parts[0] === "yes"
          const signal = parts[parts.length - 2]
          const security = parts[parts.length - 1]
          const ssid = parts.slice(1, parts.length - 2).join(":")
          if (!ssid.length || seen[ssid])
            continue
          seen[ssid] = true
          out.push({
            ssid: ssid,
            active: active,
            signal: signal,
            security: security,
            open: root.isOpenSecurity(security)
          })
        }
        root.networks = out
        root.busy = false
      }
    }
  }
}
