pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import QtQuick

// Battery state (UPower), power-profiles-daemon mode, and logind idle / lid.
//
// Power mode (Performance / Balanced / Eco) → powerprofilesctl / PPD D-Bus;
// active seat may switch without a Proteus helper (polkit allow_active=yes).
//
// Idle/lid writes go through services/proteus-logind (pkexec + polkit), which
// owns /etc/systemd/logind.conf.d/99-proteus.conf. The main logind.conf stays
// an escape hatch; Settings reports the effective merge of main + drop-ins.
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

  // —— power-profiles-daemon (Performance / Balanced / Eco) ————————————————

  // UI ids: performance | balanced | eco  (eco → PPD power-saver)
  property string activeProfile: ""
  property var availableProfiles: []
  property bool profilesAvailable: false
  property string profileError: ""
  property bool profileBusy: false

  readonly property var profileCatalog: [
    { id: "performance", label: "Performance", ppd: "performance" },
    { id: "balanced", label: "Balanced", ppd: "balanced" },
    { id: "eco", label: "Eco", ppd: "power-saver" }
  ]

  readonly property var profileOptions: {
    const avail = root.availableProfiles || []
    const out = []
    for (let i = 0; i < root.profileCatalog.length; i++) {
      const c = root.profileCatalog[i]
      if (avail.indexOf(c.ppd) >= 0)
        out.push({ id: c.id, label: c.label })
    }
    return out
  }

  readonly property string activeProfileLabel: root.profileLabel(root.activeProfile)

  function uiIdFromPpd(ppd) {
    const p = String(ppd || "")
    if (p === "power-saver")
      return "eco"
    return p
  }

  function ppdFromUiId(id) {
    const u = String(id || "")
    if (u === "eco")
      return "power-saver"
    return u
  }

  function profileLabel(uiId) {
    const u = String(uiId || "")
    for (let i = 0; i < root.profileCatalog.length; i++) {
      if (root.profileCatalog[i].id === u)
        return root.profileCatalog[i].label
    }
    return u.length ? u : "—"
  }

  function refreshProfiles() {
    profileProc.running = false
    profileProc.running = true
  }

  function setProfile(uiId) {
    const ppd = root.ppdFromUiId(uiId)
    if (!ppd.length)
      return
    if ((root.availableProfiles || []).indexOf(ppd) < 0) {
      root.profileError = "Profile not available on this machine"
      return
    }
    if (root.uiIdFromPpd(ppd) === root.activeProfile && !root.profileBusy)
      return
    root.profileBusy = true
    root.profileError = ""
    setProfileProc.command = ["powerprofilesctl", "set", ppd]
    setProfileProc.running = false
    setProfileProc.running = true
  }

  // —— logind policy ——————————————————————————————————————————————————————

  property string idleAction: ""
  property string idleActionSec: ""
  property string lidSwitch: ""
  property string lidSwitchExternalPower: ""
  property bool idleActionDefaulted: true
  property bool idleActionSecDefaulted: true
  property bool lidSwitchDefaulted: true
  property bool lidSwitchExternalPowerDefaulted: true
  property string logindError: ""
  property bool busy: false
  property bool helperMissing: false

  readonly property string logindConfPath: "/etc/systemd/logind.conf"
  readonly property var actionValues: [
    "ignore", "lock", "suspend", "hibernate",
    "hybrid-sleep", "suspend-then-hibernate", "poweroff"
  ]
  readonly property var idleSecPresets: [
    { id: "5min", label: "5 minutes" },
    { id: "15min", label: "15 minutes" },
    { id: "30min", label: "30 minutes" },
    { id: "1h", label: "1 hour" },
    { id: "2h", label: "2 hours" }
  ]

  function shellQuote(s) {
    return "'" + String(s).replace(/'/g, "'\\''") + "'"
  }

  function refreshLogind() {
    logindProc.running = false
    logindProc.running = true
    probeHelperProc.running = false
    probeHelperProc.running = true
    root.refreshProfiles()
  }

  function openLogindConf() {
    Quickshell.execDetached({
      command: [
        "bash",
        "-lc",
        "(command -v xdg-open >/dev/null && xdg-open " + root.logindConfPath + ")"
            + " || exec proteus-terminal -e less " + root.logindConfPath
      ]
    })
  }

  function openInstallHelper() {
    Quickshell.execDetached({
      command: [
        "bash",
        "-lc",
        "exec proteus-terminal -e bash -lc "
            + JSON.stringify(
              "sudo bash /mnt/proteus/vm/guest/install-proteus-logind.sh"
                  + "; echo; read -r -p \"Press Enter to close…\" _")
      ]
    })
  }

  function actionLabel(value) {
    const v = String(value || "")
    switch (v) {
    case "ignore": return "Do nothing"
    case "lock": return "Lock"
    case "suspend": return "Sleep"
    case "hibernate": return "Hibernate"
    case "hybrid-sleep": return "Hybrid sleep"
    case "suspend-then-hibernate": return "Sleep then hibernate"
    case "poweroff": return "Shut down"
    default: return v.length ? v : "Not set"
    }
  }

  function idleSecLabel(value) {
    const v = String(value || "")
    for (let i = 0; i < root.idleSecPresets.length; i++) {
      if (root.idleSecPresets[i].id === v)
        return root.idleSecPresets[i].label
    }
    return v.length ? v : "Not set"
  }

  // assignments: array of "Key=value" strings (allowlisted by helper)
  function setLogindPolicy(assignments) {
    const list = assignments || []
    if (!list.length)
      return
    root.busy = true
    root.logindError = ""
    root.helperMissing = false
    pendingArgs = ["set"].concat(list)
    _resolveAndRun()
  }

  function clearLogindOverrides() {
    root.busy = true
    root.logindError = ""
    root.helperMissing = false
    pendingArgs = ["clear"]
    _resolveAndRun()
  }

  // Remove one or more keys from the Proteus drop-in (e.g. IdleActionSec).
  function unsetLogindKeys(keys) {
    const list = keys || []
    if (!list.length)
      return
    root.busy = true
    root.logindError = ""
    root.helperMissing = false
    pendingArgs = ["unset"].concat(list)
    _resolveAndRun()
  }

  property var pendingArgs: []

  function _resolveAndRun() {
    // pkexec only allows the polkit-annotated libexec wrapper. That wrapper
    // re-execs the 9p/share binary when present — do not pkexec the share path.
    const script = "BIN=\"\"; "
        + "if [ -x /usr/local/libexec/proteus-logind ]; then BIN=/usr/local/libexec/proteus-logind; "
        + "elif command -v proteus-logind >/dev/null 2>&1; then BIN=$(command -v proteus-logind); fi; "
        + "printf '%s' \"$BIN\""
    resolveProc.command = ["bash", "-c", script]
    resolveProc.running = false
    resolveProc.running = true
  }

  function _startMutator(bin) {
    const args = ["pkexec", bin]
    for (let i = 0; i < pendingArgs.length; i++)
      args.push(pendingArgs[i])
    setProc.command = args
    setProc.running = false
    setProc.running = true
  }

  // Commented keys in logind.conf are the shipped defaults, so a `#Key=value`
  // line is reported as the effective value rather than as unset. Drop-ins under
  // logind.conf.d/ override (later files win).
  Process {
    id: profileProc
    command: [
      "python3",
      "-c",
      "import json, re, subprocess\n"
          + "try:\n"
          + "    out = subprocess.check_output(['powerprofilesctl', 'list'], text=True, stderr=subprocess.STDOUT)\n"
          + "except Exception as e:\n"
          + "    print(json.dumps({'ok': False, 'active': '', 'profiles': [], 'error': str(e)}))\n"
          + "    raise SystemExit(0)\n"
          + "active, profiles = '', []\n"
          + "for line in out.splitlines():\n"
          + "    m = re.match(r'^(\\*| )\\s*([a-z0-9-]+):\\s*$', line)\n"
          + "    if not m:\n"
          + "        continue\n"
          + "    name = m.group(2)\n"
          + "    profiles.append(name)\n"
          + "    if m.group(1) == '*':\n"
          + "        active = name\n"
          + "print(json.dumps({'ok': True, 'active': active, 'profiles': profiles}))\n"
    ]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const res = JSON.parse(text.trim() || "{}")
          root.profilesAvailable = !!res.ok && (res.profiles || []).length > 0
          root.availableProfiles = res.profiles || []
          root.activeProfile = root.uiIdFromPpd(res.active || "")
          if (!root.profileBusy) {
            if (res.ok)
              root.profileError = ""
            else
              root.profileError = (res.error && String(res.error).split("\n")[0])
                  || "power-profiles-daemon unavailable"
          }
        } catch (e) {
          root.profilesAvailable = false
          root.availableProfiles = []
          root.activeProfile = ""
          if (!root.profileBusy)
            root.profileError = "Could not read power profiles"
        }
      }
    }
  }

  Process {
    id: setProfileProc
    command: ["true"]
    stderr: StdioCollector {
      id: setProfileErr
    }
    stdout: StdioCollector {
      id: setProfileOut
    }
    onExited: (exitCode, exitStatus) => {
      root.profileBusy = false
      if (exitCode === 0) {
        root.profileError = ""
        root.refreshProfiles()
        return
      }
      const e = setProfileErr.text.trim().split("\n")[0]
          || setProfileOut.text.trim().split("\n").filter(l => l.length).slice(-1)[0]
          || ""
      root.profileError = e.length ? e : "Could not change power profile"
      root.refreshProfiles()
    }
  }

  Process {
    id: logindProc
    command: [
      "python3",
      "-c",
      "import json, pathlib\n"
          + "keys = ['IdleAction','IdleActionSec','HandleLidSwitch','HandleLidSwitchExternalPower']\n"
          + "out = {k: {'value': '', 'default': True} for k in keys}\n"
          + "def apply(path):\n"
          + "    if not path.is_file():\n"
          + "        return\n"
          + "    for line in path.read_text(errors='replace').splitlines():\n"
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
          + "apply(pathlib.Path('/etc/systemd/logind.conf'))\n"
          + "d = pathlib.Path('/etc/systemd/logind.conf.d')\n"
          + "if d.is_dir():\n"
          + "    for p in sorted(d.glob('*.conf')):\n"
          + "        apply(p)\n"
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
          if (!root.busy)
            root.logindError = ""
        } catch (e) {
          root.logindError = "Could not read logind.conf"
        }
      }
    }
    stderr: StdioCollector {
      onStreamFinished: {
        const e = text.trim()
        if (e.length && !root.busy)
          root.logindError = e.split("\n")[0]
      }
    }
  }

  Process {
    id: probeHelperProc
    command: [
      "bash", "-c",
      "if [ -x /usr/local/libexec/proteus-logind ] || command -v proteus-logind >/dev/null 2>&1; then echo 1; else echo 0; fi"
    ]
    stdout: StdioCollector {
      onStreamFinished: {
        root.helperMissing = text.trim() !== "1"
      }
    }
  }

  Process {
    id: resolveProc
    command: ["true"]
    stdout: StdioCollector {
      id: resolveOut
    }
    onExited: (exitCode, exitStatus) => {
      const bin = resolveOut.text.trim()
      if (!bin.length) {
        root.busy = false
        root.helperMissing = true
        root.logindError = "proteus-logind not installed — use Install below or sudo install-proteus-logind.sh"
        return
      }
      root.helperMissing = false
      root._startMutator(bin)
    }
  }

  Process {
    id: setProc
    command: ["true"]
    stderr: StdioCollector {
      id: setErr
    }
    stdout: StdioCollector {
      id: setOut
    }
    onExited: (exitCode, exitStatus) => {
      root.busy = false
      if (exitCode === 0) {
        root.logindError = ""
        root.refreshLogind()
        return
      }
      const e = setErr.text.trim().split("\n")[0]
          || setOut.text.trim().split("\n").filter(l => l.length).slice(-1)[0]
          || ""
      root.logindError = e.length ? e : "Change refused (needs authorization)"
      root.refreshLogind()
    }
  }

  Component.onCompleted: {
    refreshLogind()
    refreshProfiles()
  }
}
