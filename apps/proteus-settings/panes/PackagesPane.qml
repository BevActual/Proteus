import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../shared"
import "../kit"

// Software hub — Omarchy-style: pick a source leaf to Install / Remove via searchable lists.
ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: 12

  property string page: "packages"
  signal requestGo(string id)

  readonly property bool onHub: page === "packages"

  readonly property var sections: {
    const _ = Packages.packageUpgradeCount
    const __ = Packages.aurHelper
    const ___ = Packages.flatpakAvailable
    const ____ = Packages.flathubConfigured
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
        label: "Repos",
        hint: "Install / Installed"
      },
      {
        key: "packages-aur",
        label: "AUR",
        hint: Packages.aurHelper.length ? ("Install / Installed · " + Packages.aurHelper) : "Needs yay/paru"
      },
      {
        key: "packages-flatpak",
        label: "Flathub",
        hint: !Packages.flatpakAvailable
            ? "Needs flatpak"
            : (Packages.flathubConfigured ? "Install / Installed" : "Add Flathub remote")
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

  ColumnLayout {
    Layout.fillWidth: true
    spacing: 12
    visible: root.onHub

    Text {
      Layout.fillWidth: true
      text: "Install and remove software like Omarchy’s Package / AUR pickers — each leaf is a searchable list with multi-select."
      color: Theme.textMute
      font.family: Theme.fontFamily
      font.pixelSize: 12
      wrapMode: Text.WordWrap
    }

    SettingsHubList {
      items: root.sections
      onActivated: key => root.requestGo(key)
    }
  }

  StickyPaneLoader {
    want: root.page === "packages-updates"
    source: "PackagesUpdatesPane.qml"
    onLoaded: item.active = Qt.binding(() => root.page === "packages-updates")
  }
  StickyPaneLoader {
    want: root.page === "packages-search"
    source: "PackagesSearchPane.qml"
    onLoaded: item.active = Qt.binding(() => root.page === "packages-search")
  }
  StickyPaneLoader {
    want: root.page === "packages-aur"
    source: "PackagesAurPane.qml"
    onLoaded: item.active = Qt.binding(() => root.page === "packages-aur")
  }
  StickyPaneLoader {
    want: root.page === "packages-flatpak"
    source: "PackagesFlatpakPane.qml"
    onLoaded: item.active = Qt.binding(() => root.page === "packages-flatpak")
  }
  StickyPaneLoader {
    want: root.page === "packages-appimages"
    source: "PackagesAppImagesPane.qml"
    onLoaded: item.active = Qt.binding(() => root.page === "packages-appimages")
  }
  StickyPaneLoader {
    want: root.page === "packages-orphans"
    source: "PackagesOrphansPane.qml"
    onLoaded: item.active = Qt.binding(() => root.page === "packages-orphans")
  }

  onPageChanged: {
    if (page === "packages" || page.startsWith("packages-")) {
      Packages.refreshHelpers()
      warmCount()
    }
  }

  Component.onCompleted: {
    Packages.refreshHelpers()
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
      if (Packages.packageUpgradeCount < 0 && exitCode !== 0)
        Packages.notePackageUpgrades(0)
    }
  }
}
