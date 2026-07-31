pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// LocalSend (AirDrop-style LAN share) — Network Settings leaf + Control Center.
// Detects native binary, Flatpak (org.localsend.localsend_app), or port 53317.
Singleton {
  id: root

  property bool available: false
  property bool running: false
  property bool flatpak: false
  property string hint: "Checking LocalSend…"
  property string binaryPath: ""
  // Primary LAN IPv4 for “copy address” (empty if unknown).
  property string lanAddress: ""

  readonly property string statusLabel: {
    if (!root.available)
      return "Not installed"
    if (root.running)
      return "Receiving"
    return "Ready"
  }

  readonly property string shortLabel: {
    if (!root.available)
      return "—"
    return root.running ? "On" : "Off"
  }

  readonly property string receiveEndpoint: {
    if (!root.lanAddress.length)
      return ""
    return root.lanAddress + ":53317"
  }

  // Control Center tile menu (Keep Awake–style).
  readonly property var menuOptions: {
    const opts = []
    if (!root.available) {
      opts.push({ id: "settings", title: "Install in Settings…" })
      opts.push({ id: "refresh", title: "Refresh" })
      return opts
    }
    if (root.running) {
      opts.push({ id: "stop", title: "Stop receiving" })
      opts.push({ id: "open", title: "Show window" })
    } else {
      opts.push({ id: "start", title: "Start receiving" })
      opts.push({ id: "open", title: "Open LocalSend" })
    }
    if (root.receiveEndpoint.length)
      opts.push({ id: "copy", title: "Copy " + root.receiveEndpoint })
    opts.push({ id: "settings", title: "Network Settings…" })
    opts.push({ id: "refresh", title: "Refresh" })
    return opts
  }

  function refresh() {
    probeProc.running = false
    probeProc.running = true
  }

  function select(id) {
    switch (String(id || "")) {
    case "start":
      root.start()
      break
    case "stop":
      root.stop()
      break
    case "open":
      root.open()
      break
    case "toggle":
      root.toggle()
      break
    case "copy":
      if (root.receiveEndpoint.length)
        Config.copyToClipboard(root.receiveEndpoint)
      break
    case "settings":
      if (!root.available) {
        Packages.seedPackageSearch("localsend-bin", "packages-aur")
        ShellState.openSettings("packages-aur", "localsend-bin")
      } else {
        ShellState.openSettings("network-localsend")
      }
      break
    case "refresh":
      root.refresh()
      break
    }
  }

  function open() {
    if (!root.available)
      return
    if (root.flatpak) {
      Quickshell.execDetached({
        command: ["flatpak", "run", "org.localsend.localsend_app"]
      })
      return
    }
    const e = DesktopEntries.heuristicLookup("localsend")
        || DesktopEntries.heuristicLookup("org.localsend.localsend_app")
    if (e) {
      e.execute()
      return
    }
    if (root.binaryPath.length) {
      Quickshell.execDetached({
        command: [root.binaryPath]
      })
      return
    }
    Quickshell.execDetached({
      command: ["bash", "-lc", "command -v localsend >/dev/null && exec localsend || exec proteus-terminal -e bash -lc 'echo LocalSend not found; read -r _'"]
    })
  }

  function start() {
    root.open()
    kick.restart()
  }

  function stop() {
    // Always attempt kill — don't trust the probe (port/name races).
    // Flutter/LocalSend can ignore a single soft signal; escalate to KILL
    // and free :53317 if anything is still bound.
    root.running = false
    root.hint = root.available
        ? ("Ready · " + (root.flatpak ? "Flatpak" : "localsend"))
        : root.hint
    stopProc.running = false
    stopProc.running = true
  }

  function toggle() {
    if (!root.available)
      return
    if (root.running)
      root.stop()
    else
      root.start()
  }

  Timer {
    id: kick
    interval: 900
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    interval: 4000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Process {
    id: stopProc
    // Exact-name kills only — never pkill -f with a path that also appears in
    // this bash -c cmdline (that matched and SIGTERM'd the helper itself).
    command: [
      "bash",
      "-c",
      "set +e\n"
          + "pkill -TERM -x localsend 2>/dev/null\n"
          + "killall -TERM localsend 2>/dev/null\n"
          + "sleep 0.35\n"
          + "pkill -KILL -x localsend 2>/dev/null\n"
          + "killall -KILL localsend 2>/dev/null\n"
          + "if command -v flatpak >/dev/null 2>&1; then\n"
          + "  flatpak kill org.localsend.localsend_app 2>/dev/null\n"
          + "fi\n"
          + "if command -v fuser >/dev/null 2>&1; then\n"
          + "  fuser -k 53317/tcp 53317/udp >/dev/null 2>&1\n"
          + "fi\n"
          + "exit 0\n"
    ]
    onExited: kick.restart()
  }

  Process {
    id: probeProc
    command: [
      "python3",
      "-c",
      "import json, os, shutil, subprocess\n"
          + "o={'available':False,'running':False,'flatpak':False,'hint':'LocalSend not installed','path':'','address':''}\n"
          + "def usable(p):\n"
          + "  try:\n"
          + "    p=os.path.realpath(p)\n"
          + "    return os.path.isfile(p) and os.access(p, os.X_OK) and os.path.getsize(p) > 1024\n"
          + "  except Exception:\n"
          + "    return False\n"
          + "addr=''\n"
          + "try:\n"
          + "  r=subprocess.run(['ip','-4','-o','addr','show','scope','global'],capture_output=True,text=True)\n"
          + "  for line in (r.stdout or '').splitlines():\n"
          + "    parts=line.split()\n"
          + "    for i,p in enumerate(parts):\n"
          + "      if p=='inet' and i+1 < len(parts):\n"
          + "        a=parts[i+1].split('/')[0]\n"
          + "        if a and not a.startswith('127.'):\n"
          + "          addr=a; break\n"
          + "    if addr: break\n"
          + "except Exception:\n"
          + "  pass\n"
          + "if not addr:\n"
          + "  try:\n"
          + "    r=subprocess.run(['hostname','-I'],capture_output=True,text=True)\n"
          + "    for a in (r.stdout or '').split():\n"
          + "      if a and not a.startswith('127.') and '.' in a and ':' not in a:\n"
          + "        addr=a; break\n"
          + "  except Exception:\n"
          + "    pass\n"
          + "o['address']=addr\n"
          + "path=''\n"
          + "w=shutil.which('localsend') or ''\n"
          + "if w and usable(w):\n"
          + "  path=w\n"
          + "elif w and not usable(w):\n"
          + "  o['hint']='Broken localsend — Install… → Software → AUR · localsend-bin'\n"
          + "if not path:\n"
          + "  for c in ('/usr/bin/localsend','/opt/localsend/localsend','/usr/lib/localsend/localsend'):\n"
          + "    if usable(c):\n"
          + "      path=c; break\n"
          + "flatpak=False\n"
          + "if shutil.which('flatpak'):\n"
          + "  r=subprocess.run(['flatpak','info','org.localsend.localsend_app'],capture_output=True)\n"
          + "  flatpak=r.returncode==0\n"
          + "if path:\n"
          + "  o['available']=True; o['path']=path; o['flatpak']=False\n"
          + "elif flatpak:\n"
          + "  o['available']=True; o['flatpak']=True; o['path']='flatpak:org.localsend.localsend_app'\n"
          + "else:\n"
          + "  if not o['hint'].startswith('Broken'):\n"
          + "    o['hint']='Software → AUR · localsend-bin'\n"
          + "  print(json.dumps(o)); raise SystemExit\n"
          + "running=False\n"
          + "try:\n"
          + "  r=subprocess.run(['pgrep','-x','localsend'],capture_output=True)\n"
          + "  running=r.returncode==0\n"
          + "except Exception:\n"
          + "  pass\n"
          + "if not running:\n"
          + "  try:\n"
          + "    r=subprocess.run(['pgrep','-f','org.localsend.localsend_app'],capture_output=True)\n"
          + "    running=r.returncode==0\n"
          + "  except Exception:\n"
          + "    pass\n"
          + "if not running:\n"
          + "  try:\n"
          + "    r=subprocess.run(['ss','-lntu'],capture_output=True,text=True)\n"
          + "    running=':53317' in (r.stdout or '')\n"
          + "  except Exception:\n"
          + "    pass\n"
          + "o['running']=bool(running)\n"
          + "src='Flatpak' if o['flatpak'] else 'localsend'\n"
          + "ep=(addr+':53317') if addr else ':53317'\n"
          + "o['hint']=('Receiving · '+ep+' · '+src) if running else ('Ready · '+src)\n"
          + "print(json.dumps(o))\n"
    ]
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const o = JSON.parse(String(text || "").trim() || "{}")
          root.available = !!o.available
          root.running = !!o.running
          root.flatpak = !!o.flatpak
          root.hint = o.hint || ""
          root.binaryPath = o.path || ""
          root.lanAddress = o.address || ""
        } catch (e) {
          root.available = false
          root.running = false
          root.flatpak = false
          root.hint = "Could not probe LocalSend"
          root.binaryPath = ""
          root.lanAddress = ""
        }
      }
    }
  }

  Component.onCompleted: refresh()
}
