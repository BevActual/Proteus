pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Default applications (xdg-mime) for Settings → Desktop → Default apps.
Singleton {
  id: root

  property bool loading: false
  property string error: ""
  property var categories: []
  property int rev: 0

  readonly property string script: Config.scriptsDir + "/proteus-defaults.py"

  function refresh() {
    loading = true
    error = ""
    listProc.running = false
    listProc.running = true
  }

  function setDefault(categoryId, desktopId) {
    const cat = String(categoryId || "").trim()
    const desk = String(desktopId || "").trim()
    if (!cat.length || !desk.length)
      return
    setProc.category = cat
    setProc.desktop = desk
    setProc.running = false
    setProc.running = true
  }

  function categoryAt(id) {
    const list = categories || []
    for (let i = 0; i < list.length; i++) {
      if (list[i].id === id)
        return list[i]
    }
    return null
  }

  Process {
    id: listProc
    command: ["python3", root.script, "list"]
    stdout: StdioCollector {
      onStreamFinished: {
        root.loading = false
        try {
          const data = JSON.parse(String(text).trim())
          if (!data.ok) {
            root.error = String(data.error || "Could not load defaults")
            return
          }
          root.categories = data.categories || []
          root.error = ""
          root.rev++
        } catch (e) {
          root.error = "Could not parse defaults"
        }
      }
    }
    stderr: StdioCollector {
      onStreamFinished: {
        const e = String(text).trim()
        if (e.length && root.loading)
          root.error = e.split("\n")[0]
      }
    }
  }

  Process {
    id: setProc
    property string category: ""
    property string desktop: ""
    command: ["python3", root.script, "set", category, desktop]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const data = JSON.parse(String(text).trim())
          if (!data.ok) {
            root.error = String(data.error || "Could not set default")
            return
          }
          root.error = ""
        } catch (e) {
          root.error = "Could not set default"
        }
        root.refresh()
      }
    }
  }

  Component.onCompleted: root.refresh()
}
