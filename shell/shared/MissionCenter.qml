pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Mission Center escape for Settings → About (Activity Monitor).
// Detect native binary or Flatpak; honest missing install.
Singleton {
  id: root

  property bool available: false
  property bool flatpak: false
  property string binaryPath: ""
  property string hint: "Checking…"

  readonly property string statusLabel: root.available ? "Installed" : "Not installed"

  function refresh() {
    probeProc.running = false
    probeProc.running = true
  }

  function open() {
    if (!root.available)
      return
    if (root.flatpak) {
      Quickshell.execDetached({
        command: ["flatpak", "run", "io.missioncenter.MissionCenter"]
      })
      return
    }
    const e = DesktopEntries.heuristicLookup("missioncenter")
        || DesktopEntries.heuristicLookup("io.missioncenter.MissionCenter")
        || DesktopEntries.heuristicLookup("mission-center")
    if (e) {
      e.execute()
      return
    }
    if (root.binaryPath.length) {
      Quickshell.execDetached({ command: [root.binaryPath] })
      return
    }
    Quickshell.execDetached({
      command: ["bash", "-lc", "command -v missioncenter >/dev/null && exec missioncenter || command -v mission-center >/dev/null && exec mission-center"]
    })
  }

  function openSoftware() {
    const q = "io.missioncenter.MissionCenter"
    Packages.seedPackageSearch(q, "packages-flatpak")
    ShellState.openSettings("packages-flatpak", q)
  }

  Component.onCompleted: root.refresh()

  Process {
    id: probeProc
    command: [
      "python3",
      "-c",
      "import json, shutil, subprocess\n"
          + "path = shutil.which('missioncenter') or shutil.which('mission-center') or ''\n"
          + "flatpak = False\n"
          + "if not path:\n"
          + "    try:\n"
          + "        out = subprocess.check_output(\n"
          + "            ['flatpak', 'list', '--app', '--columns=application'],\n"
          + "            stderr=subprocess.DEVNULL, text=True, timeout=4)\n"
          + "        flatpak = 'io.missioncenter.MissionCenter' in out\n"
          + "    except Exception:\n"
          + "        flatpak = False\n"
          + "ok = bool(path) or flatpak\n"
          + "hint = ('Mission Center · Flatpak' if flatpak else ('Mission Center · ' + path if path else 'Software → Flathub · Mission Center'))\n"
          + "print(json.dumps({'available': ok, 'flatpak': flatpak, 'path': path or '', 'hint': hint}))\n"
    ]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const res = JSON.parse(text.trim() || "{}")
          root.available = !!res.available
          root.flatpak = !!res.flatpak
          root.binaryPath = String(res.path || "")
          root.hint = String(res.hint || "")
        } catch (e) {
          root.available = false
          root.flatpak = false
          root.binaryPath = ""
          root.hint = "Software → Flathub · Mission Center"
        }
      }
    }
    stderr: StdioCollector {}
  }
}
