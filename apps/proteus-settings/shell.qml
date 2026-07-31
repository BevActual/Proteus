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
