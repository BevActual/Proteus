import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../shared"
import "../kit"

// Software category (page id packages) — Updates · Search · AUR · Flatpak · AppImages · Orphans.
ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: 12

  property string page: "packages"
  signal requestGo(string id)

  readonly property var sections: {
    const _ = Packages.packageUpgradeCount
    return [
      {
        key: "packages-updates",
        label: "Updates",
        hint: Packages.packageUpgradeCount < 0
            ? ""
            : (Packages.packageUpgradeCount === 0
                ? "Up to date"
                : (Packages.packageUpgradeCount + " available"))
      },
      {
        key: "packages-search",
        label: "Search"
      },
      {
        key: "packages-aur",
        label: "AUR"
      },
      {
        key: "packages-flatpak",
        label: "Flatpak"
      },
      {
        key: "packages-appimages",
        label: "AppImages"
      },
      {
        key: "packages-orphans",
        label: "Orphans"
      }
    ]
  }

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
    onExited: (exitCode, exitStatus) => {
      // No upgrades → pacman -Qu exits 1 with empty stdout
      if (Packages.packageUpgradeCount < 0 && exitCode !== 0)
        Packages.notePackageUpgrades(0)
    }
  }
}
