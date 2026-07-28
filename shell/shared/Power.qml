pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import QtQuick

// Battery state (UPower) plus the logind idle / lid policy.
//
// The logind side is read-only on purpose: /etc/systemd/logind.conf is root
// owned, so changing it needs a privileged helper like services/proteus-pkg.
// Until that exists, Settings reports the effective policy and offers the
// file as an escape hatch rather than pretending to own it.
Singleton {
  id: root

  readonly property var device: UPower.displayDevice
  readonly property bool onBattery: UPower.onBattery

  // Ask UPower what the device is rather than inferring from charge — a laptop
  // sitting at 0% is still a laptop, and a desktop still reports a display device.
  readonly property bool hasBattery: {
    const d = root.device
    if (!d)
      return false
    return !!d.isLaptopBattery && !!d.isPresent
  }

  readonly property int health: {
    const d = root.device
    if (!d)
      return -1
    const h = Number(d.healthPercentage)
    if (isNaN(h) || h <= 0)
      return -1
    return Math.round(h)
  }

  readonly property int percent: {
    const d = root.device
    if (!d)
      return -1
    const p = Number(d.percentage)
    if (isNaN(p))
      return -1
    // UPower percentage is 0..1 in Quickshell.
    return Math.round(Math.max(0, Math.min(1, p)) * 100)
  }

  readonly property string stateLabel: {
    const d = root.device
    if (!d)
      return "Unknown"
    const s = String(d.state)
    if (s.indexOf("FullyCharged") >= 0)
      return "Fully charged"
    if (s.indexOf("Charging") >= 0)
      return "Charging"
    if (s.indexOf("Discharging") >= 0)
      return "On battery"
    if (s.indexOf("Empty") >= 0)
      return "Empty"
    return root.onBattery ? "On battery" : "AC power"
  }

  function formatDuration(seconds) {
    const s = Number(seconds)
    if (isNaN(s) || s <= 0)
      return ""
    const h = Math.floor(s / 3600)
    const m = Math.round((s % 3600) / 60)
    if (h > 0)
      return h + "h " + m + "m"
    return m + "m"
  }

  readonly property string timeRemaining: {
    const d = root.device
    if (!d)
      return ""
    const charging = String(d.state).indexOf("Charging") >= 0
    const secs = charging ? d.timeToFull : d.timeToEmpty
    const txt = root.formatDuration(secs)
    if (!txt.length)
      return ""
    return charging ? (txt + " until full") : (txt + " remaining")
  }

  // —— logind policy (read-only) ——————————————————————————————————————————

  property string idleAction: ""
  property string idleActionSec: ""
  property string lidSwitch: ""
  property string lidSwitchExternalPower: ""
  property bool idleActionDefaulted: true
  property bool idleActionSecDefaulted: true
  property bool lidSwitchDefaulted: true
  property bool lidSwitchExternalPowerDefaulted: true
  property string logindError: ""

  readonly property string logindConfPath: "/etc/systemd/logind.conf"

  function refreshLogind() {
    logindProc.running = false
    logindProc.running = true
  }

  function openLogindConf() {
    Quickshell.execDetached({
      command: [
        "bash",
        "-lc",
        "(command -v xdg-open >/dev/null && xdg-open " + root.logindConfPath + ")"
            + " || exec ghostty -e less " + root.logindConfPath
      ]
    })
  }

  // Commented keys in logind.conf are the shipped defaults, so a `#Key=value`
  // line is reported as the effective value rather than as unset.
  Process {
    id: logindProc
    command: [
      "python3",
      "-c",
      "import json, re, pathlib\n"
          + "keys = ['IdleAction','IdleActionSec','HandleLidSwitch','HandleLidSwitchExternalPower']\n"
          + "out = {k: {'value': '', 'default': True} for k in keys}\n"
          + "p = pathlib.Path('/etc/systemd/logind.conf')\n"
          + "if p.is_file():\n"
          + "    for line in p.read_text(errors='replace').splitlines():\n"
          + "        s = line.strip()\n"
          + "        if not s or '=' not in s:\n"
          + "            continue\n"
          + "        commented = s.startswith('#')\n"
          + "        body = s.lstrip('#').strip()\n"
          + "        k, _, v = body.partition('=')\n"
          + "        k, v = k.strip(), v.strip()\n"
          + "        if k not in keys:\n"
          + "            continue\n"
          + "        if commented and out[k]['value']:\n"
          + "            continue\n"
          + "        out[k] = {'value': v, 'default': commented}\n"
          + "print(json.dumps(out))\n"
    ]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const res = JSON.parse(text.trim() || "{}")
          root.idleAction = (res.IdleAction && res.IdleAction.value) || ""
          root.idleActionSec = (res.IdleActionSec && res.IdleActionSec.value) || ""
          root.lidSwitch = (res.HandleLidSwitch && res.HandleLidSwitch.value) || ""
          root.lidSwitchExternalPower = (res.HandleLidSwitchExternalPower && res.HandleLidSwitchExternalPower.value) || ""
          root.idleActionDefaulted = !(res.IdleAction) || !!res.IdleAction.default
          root.idleActionSecDefaulted = !(res.IdleActionSec) || !!res.IdleActionSec.default
          root.lidSwitchDefaulted = !(res.HandleLidSwitch) || !!res.HandleLidSwitch.default
          root.lidSwitchExternalPowerDefaulted = !(res.HandleLidSwitchExternalPower)
              || !!res.HandleLidSwitchExternalPower.default
          root.logindError = ""
        } catch (e) {
          root.logindError = "Could not read logind.conf"
        }
      }
    }
    stderr: StdioCollector {
      onStreamFinished: {
        const e = text.trim()
        if (e.length)
          root.logindError = e.split("\n")[0]
      }
    }
  }

  Component.onCompleted: refreshLogind()
}
