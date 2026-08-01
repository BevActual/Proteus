import Quickshell
import Quickshell.Io
import QtQuick
import "shared"

ShellRoot {
  FloatingWindow {
    id: win
    title: "Proteus Settings"
    visible: true
    implicitWidth: 820
    implicitHeight: 560
    minimumSize: Qt.size(640, 420)
    color: Theme.bgElevated

    onClosed: Qt.quit()

    // Show the window shell immediately; build the heavy UI off the first frame.
    Loader {
      id: settingsLoader
      anchors.fill: parent
      asynchronous: true
      source: "Settings.qml"
      onLoaded: {
        if (item) {
          item.anchors.fill = settingsLoader
        }
      }
    }
  }

  // Smoke/dogfood probe: drive nav + Install… seed from the CLI.
  //   qs -p <config> ipc call nav state
  //   qs -p <config> ipc call nav installSearch qpwgraph packages-search
  //   qs -p <config> ipc call nav raise   # focus existing window (single-instance)
  IpcHandler {
    target: "nav"

    function page(): string {
      return SettingsNav.page
    }

    function go(id: string): void {
      SettingsNav.go(id)
    }

    function installSearch(query: string, leaf: string): void {
      SettingsNav.goInstallSearch(query, leaf)
    }

    // Bring the existing Settings window forward (launcher reuses one instance).
    // Pulls off special:minimized when the dock parked it there.
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
              + "  if c.get(\"title\")==\"Proteus Settings\":\n"
              + "    print(c.get(\"address\",\"\") or \"\"); break\n"
              + "' 2>/dev/null || true)\n"
              + "if [[ -n \"${addr}\" ]]; then\n"
              + "  hyprctl dispatch movetoworkspace +0,address:\"${addr}\" >/dev/null 2>&1 || true\n"
              + "  hyprctl dispatch focuswindow address:\"${addr}\" >/dev/null 2>&1 || true\n"
              + "else\n"
              + "  hyprctl dispatch focuswindow 'title:^(Proteus Settings)$' >/dev/null 2>&1 || true\n"
              + "fi\n"
        ]
      })
    }

    function state(): string {
      return JSON.stringify({
        page: SettingsNav.page,
        pendingQuery: SettingsNav.pendingInstallQuery,
        pendingLeaf: SettingsNav.pendingInstallLeaf,
        seed: Packages.searchSeed,
        seedTarget: Packages.searchSeedTarget
      })
    }
  }
}
