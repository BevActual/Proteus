//@ pragma IconTheme Papirus-Dark

import Quickshell
import Quickshell.Io
import QtQuick
import "shared"

ShellRoot {
  FloatingWindow {
    id: win
    title: "Proteus Workloads"
    visible: true
    implicitWidth: 560
    implicitHeight: 520
    minimumSize: Qt.size(420, 360)
    color: Theme.bgElevated

    onClosed: Qt.quit()

    // Window-level Escape when focus is not in a child that eats keys.
    Shortcut {
      sequences: ["Escape"]
      onActivated: {
        if (appLoader.item && typeof appLoader.item.escapeAction === "function")
          appLoader.item.escapeAction()
        else
          Qt.quit()
      }
    }

    Loader {
      id: appLoader
      anchors.fill: parent
      asynchronous: true
      source: "WorkloadsApp.qml"
      onLoaded: {
        if (item) {
          item.anchors.fill = appLoader
          if (typeof item.forceActiveFocus === "function")
            item.forceActiveFocus()
        }
      }
    }
  }

  // Single-instance: qs -p <config> ipc call app raise
  IpcHandler {
    target: "app"

    function state(): string {
      return "open"
    }

    function openTab(tab: string): void {
      if (appLoader.item && typeof appLoader.item.openTab === "function")
        appLoader.item.openTab(tab)
    }

    function raise(): void {
      win.visible = true
      try {
        win.requestActivate()
      } catch (e) {
      }
      Quickshell.execDetached({
        command: [
          "bash",
          "-lc",
          "addr=$(hyprctl clients -j 2>/dev/null | python3 -c '"
              + "import json,sys\n"
              + "try:\n"
              + "  cs=json.load(sys.stdin)\n"
              + "except Exception:\n"
              + "  raise SystemExit(0)\n"
              + "for c in cs:\n"
              + "  if c.get(\"title\")==\"Proteus Workloads\":\n"
              + "    print(c.get(\"address\",\"\") or \"\"); break\n"
              + "' 2>/dev/null || true)\n"
              + "if [[ -n \"${addr}\" ]]; then\n"
              + "  hyprctl dispatch movetoworkspace +0,address:\"${addr}\" >/dev/null 2>&1 || true\n"
              + "  hyprctl dispatch focuswindow address:\"${addr}\" >/dev/null 2>&1 || true\n"
              + "else\n"
              + "  hyprctl dispatch focuswindow 'title:^(Proteus Workloads)$' >/dev/null 2>&1 || true\n"
              + "fi\n"
        ]
      })
    }
  }
}
