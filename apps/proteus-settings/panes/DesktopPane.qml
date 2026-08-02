import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../shared"
import "../kit"

// Desktop category: hub list → leaf loaders (Appearance-style).
ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: Theme.spaceMd

  property string page: "desktop"
  property Item focusHost
  signal requestGo(string id)

  readonly property bool active: page === "desktop" || page.startsWith("desktop-")

  readonly property var allSections: [
    {
      key: "desktop-gaps",
      label: "Gaps"
    },
    {
      key: "desktop-chrome",
      label: "Borders & rounding"
    },
    {
      key: "desktop-motion",
      label: "Motion"
    },
    {
      key: "desktop-dock",
      label: "Dock & menu bar"
    },
    {
      key: "desktop-spaces",
      label: "Spaces"
    },
    {
      key: "desktop-defaults",
      label: "Default apps"
    },
    {
      key: "desktop-focus",
      label: "Focus"
    },
    {
      key: "desktop-control-center",
      label: "Control Center"
    },
    {
      key: "desktop-launcher",
      label: "Beacon"
    }
  ]

  readonly property var sections: {
    const _ = FocusMode.paneDensity
    const out = []
    for (let i = 0; i < root.allSections.length; i++) {
      const s = root.allSections[i]
      if (EnvGate.paneAvailable(s.key))
        out.push(s)
    }
    return out
  }

  SettingsHubList {
    visible: root.page === "desktop"
    items: root.sections
    onActivated: key => root.requestGo(key)
  }

  StickyPaneLoader {
    want: root.page === "desktop-gaps"
    source: "DesktopGapsLeaf.qml"
  }

  StickyPaneLoader {
    want: root.page === "desktop-chrome"
    source: "DesktopChromeLeaf.qml"
  }

  StickyPaneLoader {
    want: root.page === "desktop-motion"
    source: "DesktopMotionLeaf.qml"
  }

  StickyPaneLoader {
    want: root.page === "desktop-dock"
    source: "DesktopDockLeaf.qml"
  }

  StickyPaneLoader {
    want: root.page === "desktop-spaces"
    source: "DesktopSpacesLeaf.qml"
    onLoaded: item.focusHost = root.focusHost
  }

  StickyPaneLoader {
    want: root.page === "desktop-defaults"
    source: "DesktopDefaultsLeaf.qml"
  }

  StickyPaneLoader {
    want: root.page === "desktop-focus"
    source: "DesktopFocusLeaf.qml"
  }

  StickyPaneLoader {
    want: root.page === "desktop-control-center"
    source: "DesktopControlCenterLeaf.qml"
  }

  StickyPaneLoader {
    want: root.page === "desktop-launcher"
    source: "DesktopLauncherLeaf.qml"
  }
}
