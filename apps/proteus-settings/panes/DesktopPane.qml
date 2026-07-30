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
  signal requestGo(string id)

  readonly property bool active: page === "desktop" || page.startsWith("desktop-")

  readonly property var sections: [
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
      key: "desktop-launcher",
      label: "Launcher"
    }
  ]

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
    want: root.page === "desktop-launcher"
    source: "DesktopLauncherLeaf.qml"
  }
}
