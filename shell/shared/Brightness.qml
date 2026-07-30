pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Backlight control for Status HUD (#1159) — brightnessctl, else sysfs.
// Honest skip when no backlight device (typical desktop VM).
Singleton {
  id: root

  property bool available: false
  property string backend: "" // brightnessctl | sysfs | ""
  property string sysfsPath: ""
  property int lastPercent: -1

  function refreshAvailability() {
    availProc.running = false
    availProc.running = true
  }

  function stepBrightness(delta) {
    const d = Math.round(Number(delta) || 0)
    if (!root.available) {
      // Honest skip — no fake HUD on headless / VM without backlight
      return
    }
    getBrightness(pct => {
      const cur = Math.max(0, Math.min(100, Math.round(pct)))
      const next = Math.max(0, Math.min(100, cur + d))
      setBrightness(next)
      root.lastPercent = next
      Hud.show("brightness", next, "Brightness")
    })
  }

  function getBrightness(callback) {
    if (!root.available) {
      if (callback)
        callback(-1)
      return
    }
    if (root.backend === "brightnessctl") {
      getCtlProc.callback = callback
      getCtlProc.running = false
      getCtlProc.running = true
      return
    }
    if (root.backend === "sysfs" && root.sysfsPath.length) {
      getSysProc.callback = callback
      getSysProc.command = ["bash", "-lc", "echo $(cat '" + root.sysfsPath + "/brightness') $(cat '" + root.sysfsPath + "/max_brightness')"]
      getSysProc.running = false
      getSysProc.running = true
      return
    }
    if (callback)
      callback(-1)
  }

  function setBrightness(pct) {
    const v = Math.max(0, Math.min(100, Math.round(pct)))
    if (!root.available)
      return
    if (root.backend === "brightnessctl") {
      Quickshell.execDetached({
        command: ["brightnessctl", "set", v + "%"]
      })
      return
    }
    if (root.backend === "sysfs" && root.sysfsPath.length) {
      Quickshell.execDetached({
        command: [
          "bash",
          "-lc",
          "p='" + root.sysfsPath + "'; max=$(cat \"$p/max_brightness\"); "
              + "val=$(( max * " + v + " / 100 )); "
              + "echo \"$val\" > \"$p/brightness\" 2>/dev/null || true"
        ]
      })
    }
  }

  Component.onCompleted: refreshAvailability()

  Process {
    id: availProc
    command: [
      "bash",
      "-lc",
      // Backlight SoT = /sys/class/backlight (not keyboard LEDs via brightnessctl -m).
      "dev=$(ls -d /sys/class/backlight/* 2>/dev/null | head -1); "
          + "if [ -n \"$dev\" ] && [ -f \"$dev/brightness\" ] && [ -f \"$dev/max_brightness\" ]; then "
          + "  if command -v brightnessctl >/dev/null 2>&1; then echo brightnessctl \"$dev\"; "
          + "  else echo sysfs \"$dev\"; fi; "
          + "else echo none; fi"
    ]
    stdout: StdioCollector {
      onStreamFinished: {
        const line = String(text).trim()
        const parts = line.split(/\s+/)
        if (parts[0] === "brightnessctl" && parts.length >= 2) {
          root.backend = "brightnessctl"
          root.sysfsPath = parts[1]
          root.available = true
          return
        }
        if (parts[0] === "sysfs" && parts.length >= 2) {
          root.backend = "sysfs"
          root.sysfsPath = parts[1]
          root.available = true
          return
        }
        root.backend = ""
        root.sysfsPath = ""
        root.available = false
      }
    }
  }

  Process {
    id: getCtlProc
    property var callback
    command: ["brightnessctl", "-m"]
    stdout: StdioCollector {
      onStreamFinished: {
        // device,class,...,percent%,...
        const parts = String(text).trim().split(",")
        let pct = 50
        for (let i = 0; i < parts.length; i++) {
          if (parts[i].indexOf("%") >= 0) {
            pct = parseInt(parts[i], 10)
            break
          }
        }
        if (!isFinite(pct))
          pct = 50
        if (getCtlProc.callback)
          getCtlProc.callback(pct)
      }
    }
  }

  Process {
    id: getSysProc
    property var callback
    command: ["true"]
    stdout: StdioCollector {
      onStreamFinished: {
        const parts = String(text).trim().split(/\s+/)
        const cur = parseInt(parts[0], 10)
        const max = parseInt(parts[1], 10)
        let pct = 50
        if (isFinite(cur) && isFinite(max) && max > 0)
          pct = Math.round((cur / max) * 100)
        if (getSysProc.callback)
          getSysProc.callback(pct)
      }
    }
  }
}
