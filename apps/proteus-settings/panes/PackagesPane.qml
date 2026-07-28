import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../shared"

// Software category (page id packages) — Updates · Search.
ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: 12

  property string page: "packages"
  signal requestGo(string id)

  readonly property var sections: [
    {
      key: "packages-updates",
      label: "Updates"
    },
    {
      key: "packages-search",
      label: "Search"
    }
  ]

  function warmCount() {
    if (Packages.packageUpgradeCount >= 0)
      return
    warmCheck.running = false
    warmCheck.running = true
  }

  SettingsHubList {
    visible: root.page === "packages"
    items: root.sections
    onActivated: key => root.requestGo(key)
  }

  onPageChanged: {
    if (page === "packages")
      warmCount()
  }

  Component.onCompleted: {
    if (page === "packages")
      warmCount()
  }

  Process {
    id: warmCheck
    command: ["pacman", "-Qu"]
    stdout: StdioCollector {
      onStreamFinished: {
        const lines = text.trim().split("\n").filter(l => l.length && l.indexOf("->") >= 0)
        Packages.notePackageUpgrades(lines.length)
      }
    }
  }
}
