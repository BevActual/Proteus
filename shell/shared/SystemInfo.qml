pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Read-only system identity for Settings → About
// (os-release · kernel · hostname · Quickshell · Hyprland · tip).
Singleton {
  id: root

  property string osPretty: ""
  property string kernelRelease: ""
  property string hostname: ""
  property string qsVersion: ""
  property string hyprVersion: ""
  property string proteusTip: ""
  property bool ready: false
  property bool busy: false
  property string error: ""
  property bool copiedFlash: false

  readonly property string osLabel: root.osPretty.length ? root.osPretty : "—"
  readonly property string kernelLabel: root.kernelRelease.length ? root.kernelRelease : "—"
  readonly property string hostnameLabel: root.hostname.length ? root.hostname : "—"
  readonly property string qsLabel: root.qsVersion.length ? root.qsVersion : "—"
  readonly property string hyprLabel: root.hyprVersion.length ? root.hyprVersion : "—"
  readonly property string tipLabel: root.proteusTip.length ? root.proteusTip : "—"

  // Multi-line clipboard block for Settings → About.
  readonly property string summaryText: {
    const lines = [
      "Proteus — Bevington Systems",
      "Hostname: " + root.hostnameLabel,
      "OS: " + root.osLabel,
      "Kernel: " + root.kernelLabel,
      "Hyprland: " + root.hyprLabel,
      "Quickshell: " + root.qsLabel
    ]
    if (root.proteusTip.length)
      lines.push("Proteus tip: " + root.proteusTip)
    if (Hardware.ready) {
      lines.push("Class: " + (Hardware.deviceClass || "—")
          + (Hardware.chassis ? (" · chassis " + Hardware.chassis) : ""))
      lines.push("Posture hint: " + (Hardware.postureHint || "—"))
    }
    if (SystemLoad.cpuModel.length)
      lines.push("CPU: " + SystemLoad.cpuModel)
    if (SystemLoad.summaryLabel !== "—")
      lines.push("Load: " + SystemLoad.summaryLabel)
    if (SystemLoad.memoryDetailLabel !== "—")
      lines.push("Memory: " + SystemLoad.memoryDetailLabel)
    if (SystemLoad.storageLabel !== "—")
      lines.push("Storage: " + SystemLoad.storageLabel)
    if (Power.hasBattery && Power.percent >= 0)
      lines.push("Battery: " + Power.percent + "% · " + Power.stateLabel)
    if (HyprProfile.activeProfileLabel && HyprProfile.activeProfileLabel !== "—")
      lines.push("Hyprland profile: " + HyprProfile.activeProfileLabel + " (soft)")
    return lines.join("\n")
  }

  function copySummary() {
    Config.copyToClipboard(root.summaryText)
    root.copiedFlash = true
    copiedTimer.restart()
  }

  function refresh() {
    if (root.busy)
      return
    root.busy = true
    root.error = ""
    identityProc.running = false
    identityProc.running = true
  }

  Timer {
    id: copiedTimer
    interval: 1600
    onTriggered: root.copiedFlash = false
  }

  Component.onCompleted: root.refresh()

  Process {
    id: identityProc
    command: [
      "python3",
      "-c",
      "import json, os, platform, shutil, subprocess\n"
          + "\n"
          + "def first_line(cmd):\n"
          + "    try:\n"
          + "        out = subprocess.check_output(cmd, stderr=subprocess.STDOUT, text=True, timeout=3)\n"
          + "        lines = [l.strip() for l in out.splitlines() if l.strip()]\n"
          + "        return lines[0] if lines else ''\n"
          + "    except Exception:\n"
          + "        return ''\n"
          + "\n"
          + "pretty = ''\n"
          + "try:\n"
          + "    with open('/etc/os-release', encoding='utf-8') as f:\n"
          + "        for line in f:\n"
          + "            line = line.strip()\n"
          + "            if line.startswith('PRETTY_NAME='):\n"
          + "                pretty = line.split('=', 1)[1].strip().strip('\"')\n"
          + "                break\n"
          + "except OSError:\n"
          + "    pass\n"
          + "if not pretty:\n"
          + "    try:\n"
          + "        pretty = platform.freedesktop_os_release().get('PRETTY_NAME', '')\n"
          + "    except Exception:\n"
          + "        pretty = ''\n"
          + "\n"
          + "host = first_line(['hostnamectl', '--static']) or first_line(['hostname']) or platform.node() or ''\n"
          + "\n"
          + "qs = ''\n"
          + "if shutil.which('quickshell'):\n"
          + "    qs = first_line(['quickshell', '--version']) or first_line(['quickshell', '-v'])\n"
          + "\n"
          + "hypr = ''\n"
          + "if shutil.which('hyprctl'):\n"
          + "    try:\n"
          + "        raw = subprocess.check_output(['hyprctl', 'version'], stderr=subprocess.STDOUT, text=True, timeout=3)\n"
          + "    except Exception:\n"
          + "        raw = ''\n"
          + "    for line in raw.splitlines():\n"
          + "        s = line.strip()\n"
          + "        if s.startswith('Hyprland '):\n"
          + "            parts = s.split()\n"
          + "            hypr = (parts[0] + ' ' + parts[1]) if len(parts) >= 2 else s\n"
          + "            break\n"
          + "        if s.startswith('Tag:'):\n"
          + "            hypr = s.replace('Tag:', '').strip().split(',')[0].strip() or s\n"
          + "            break\n"
          + "\n"
          + "tip = ''\n"
          + "root = os.environ.get('PROTEUS_ROOT') or ''\n"
          + "if not root and os.path.isdir('/mnt/proteus/.git'):\n"
          + "    root = '/mnt/proteus'\n"
          + "if root and shutil.which('git'):\n"
          + "    tip = first_line(['git', '-C', root, 'rev-parse', '--short', 'HEAD'])\n"
          + "\n"
          + "print(json.dumps({\n"
          + "    'os': pretty or '',\n"
          + "    'kernel': platform.release() or '',\n"
          + "    'hostname': host or '',\n"
          + "    'qs': qs or '',\n"
          + "    'hypr': hypr or '',\n"
          + "    'tip': tip or '',\n"
          + "}))\n"
    ]
    stdout: StdioCollector {
      onStreamFinished: {
        root.busy = false
        try {
          const res = JSON.parse(text.trim() || "{}")
          root.osPretty = String(res.os || "")
          root.kernelRelease = String(res.kernel || "")
          root.hostname = String(res.hostname || "")
          root.qsVersion = String(res.qs || "")
          root.hyprVersion = String(res.hypr || "")
          root.proteusTip = String(res.tip || "")
          root.ready = root.osPretty.length > 0 || root.kernelRelease.length > 0
              || root.qsVersion.length > 0 || root.hyprVersion.length > 0
              || root.hostname.length > 0
          root.error = root.ready ? "" : "Could not read system identity"
        } catch (e) {
          root.osPretty = ""
          root.kernelRelease = ""
          root.hostname = ""
          root.qsVersion = ""
          root.hyprVersion = ""
          root.proteusTip = ""
          root.ready = false
          root.error = "Could not read system identity"
        }
      }
    }
    stderr: StdioCollector {
      id: identityErr
    }
    onExited: (exitCode) => {
      if (exitCode === 0)
        return
      root.busy = false
      if (!root.ready) {
        const e = identityErr.text.trim().split("\n")[0] || ""
        root.error = e.length ? e : "Could not read system identity"
      }
    }
  }
}
