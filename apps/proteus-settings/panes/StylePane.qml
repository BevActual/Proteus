import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../shared"
import "../kit"

// Appearance category (page id style): list of sub-settings → leaf. Navigation via page + requestGo.
ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: 12

  property string page: "style"
  signal requestGo(string id)

  readonly property bool active: page === "style" || page.startsWith("style-")

  readonly property var sections: [
    {
      key: "style-accent",
      label: "Accent & chrome"
    },
    {
      key: "style-background",
      label: "Background"
    },
    {
      key: "style-lock",
      label: "Lock screen"
    },
    {
      key: "style-icons",
      label: "Icons"
    },
    {
      key: "style-font",
      label: "Font"
    }
  ]

  readonly property int wallpaperFillMode: {
    switch (Config.wallpaperMode) {
    case "fit":
      return Image.PreserveAspectFit
    case "stretch":
      return Image.Stretch
    case "center":
      return Image.Pad
    default:
      return Image.PreserveAspectCrop
    }
  }

  property string accentHexDraft: Config.accentCustom
  property string wallpaperColorDraft: Config.wallpaperColor
  // Kind list is browse-only — does not apply until a concrete color/image/video/style is chosen
  property string browseKind: Config.wallpaperKind
  property string iconPlateHexDraft: Config.iconPlateCustom
  property string iconSwitchTargetId: ""
  property bool addDockOpen: false
  property string addDockFilter: ""

  readonly property var dockMiddlePins: {
    if (page !== "style-icons")
      return []
    const _p = Config.dockPins
    const _o = Config.iconOverrides
    const list = DockApps.visiblePinned
    const out = []
    for (let i = 0; i < list.length; i++) {
      const e = list[i]
      if (!e || e.special === "launcher" || e.special === "settings")
        continue
      out.push(e)
    }
    return out
  }

  readonly property var addDockCandidates: {
    if (page !== "style-icons")
      return []
    const _p = Config.dockPins
    const q = String(root.addDockFilter || "").trim().toLowerCase()
    const apps = DesktopEntries.applications.values
    const out = []
    for (let i = 0; i < apps.length; i++) {
      const a = apps[i]
      if (!a || !a.name)
        continue
      const id = String(a.id || "").replace(/\.desktop$/i, "")
      if (!id.length || DockApps.isPinned(id))
        continue
      if (q.length) {
        const hay = (String(a.name) + " " + String(a.genericName || "") + " " + id).toLowerCase()
        if (hay.indexOf(q) < 0)
          continue
      }
      out.push({
        id: id,
        name: String(a.name),
        icon: EnvGate.resolveAppIcon(a)
      })
      if (out.length >= 48)
        break
    }
    out.sort((x, y) => String(x.name).localeCompare(String(y.name)))
    return out
  }

  function localPathFromUrl(url) {
    let s = String(url)
    if (s.startsWith("file://"))
      s = s.slice(7)
    // URL-decode basic spaces
    try {
      return decodeURIComponent(s)
    } catch (e) {
      return s
    }
  }

  // Keep Kind browse in sync after a concrete background is applied
  Connections {
    target: Config
    function onWallpaperKindChanged() {
      root.browseKind = Config.wallpaperKind
    }
  }

  // —— Category list ——
  SettingsHubList {
    visible: root.page === "style"
    items: root.sections
    secondaryItems: [
      {
        key: "edit-settings-json",
        label: "Edit settings.json"
      }
    ]
    onActivated: key => {
      if (key === "edit-settings-json")
        Config.openSettingsJsonInEditor()
      else
        root.requestGo(key)
    }
  }

  // —— Accent leaf ——
  StickyPaneLoader {
    want: root.page === "style-accent"
    source: "StyleAccentLeaf.qml"
    onLoaded: item.host = root
  }

  // —— Background leaf ——
  StickyPaneLoader {
    want: root.page === "style-background"
    source: "StyleBackgroundLeaf.qml"
    onLoaded: item.host = root
  }

  StickyPaneLoader {
    want: root.page === "style-lock"
    source: "StyleLockLeaf.qml"
    onLoaded: item.host = root
  }

  // —— Icons leaf ——
  StickyPaneLoader {
    want: root.page === "style-icons"
    source: "StyleIconsLeaf.qml"
    onLoaded: item.host = root
  }

  // —— Font leaf ——
  StickyPaneLoader {
    want: root.page === "style-font"
    source: "StyleFontLeaf.qml"
    onLoaded: item.host = root
  }

}
