pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Read-only system identity for Settings → About (os-release · kernel).
// Versions / copy summary land in later About depth tips.
Singleton {
  id: root

  property string osPretty: ""
  property string kernelRelease: ""
  property bool ready: false
  property bool busy: false
  property string error: ""

  readonly property string osLabel: root.osPretty.length ? root.osPretty : "—"
  readonly property string kernelLabel: root.kernelRelease.length ? root.kernelRelease : "—"

  function refresh() {
    if (root.busy)
      return
    root.busy = true
    root.error = ""
    identityProc.running = false
    identityProc.running = true
  }

  Component.onCompleted: root.refresh()

  Process {
    id: identityProc
    command: [
      "python3",
      "-c",
      "import json, platform\n"
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
          + "print(json.dumps({'os': pretty or '', 'kernel': platform.release() or ''}))\n"
    ]
    stdout: StdioCollector {
      onStreamFinished: {
        root.busy = false
        try {
          const res = JSON.parse(text.trim() || "{}")
          root.osPretty = String(res.os || "")
          root.kernelRelease = String(res.kernel || "")
          root.ready = root.osPretty.length > 0 || root.kernelRelease.length > 0
          root.error = root.ready ? "" : "Could not read OS / kernel"
        } catch (e) {
          root.osPretty = ""
          root.kernelRelease = ""
          root.ready = false
          root.error = "Could not read OS / kernel"
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
        root.error = e.length ? e : "Could not read OS / kernel"
      }
    }
  }
}
