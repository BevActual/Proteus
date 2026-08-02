import Quickshell
import QtQuick
import "../../shared"

// DesktopEntries + UniversalSearch extras → console Library / Search cards.
QtObject {
  id: root

  property string query: ""
  // Library tab section: all | games | media | apps | web
  property string section: "all"

  readonly property var sectionIds: ["all", "games", "media", "apps", "web"]
  readonly property var sectionLabels: [
    { id: "all", label: "All" },
    { id: "games", label: "Games" },
    { id: "media", label: "Media" },
    { id: "apps", label: "Apps" },
    { id: "web", label: "Web" }
  ]

  readonly property var palette: [
    { color0: "#1a3a5c", color1: "#0d1828" },
    { color0: "#1a5c3a", color1: "#0d2818" },
    { color0: "#5c3a1a", color1: "#28180d" },
    { color0: "#3a1a5c", color1: "#1c0d28" },
    { color0: "#1a4a5c", color1: "#0d2228" },
    { color0: "#2a2a2e", color1: "#141416" }
  ]

  function colorFor(name) {
    const s = String(name || "")
    let h = 0
    for (let i = 0; i < s.length; i++)
      h = (h + s.charCodeAt(i) * (i + 1)) % 997
    return root.palette[h % root.palette.length]
  }

  function matchesSection(a, section) {
    const sec = String(section || "all")
    if (sec === "all")
      return true
    const tag = String(a.tag || "").toUpperCase()
    const id = String(a.id || a.desktopId || "").toLowerCase()
    const title = String(a.title || "").toLowerCase()
    if (sec === "games")
      return tag === "GAMES" || id.indexOf("steam") >= 0 || id.indexOf("retroarch") >= 0
          || title.indexOf("game") >= 0
    if (sec === "media")
      return tag === "MEDIA" || tag.indexOf("AUDIO") >= 0 || tag.indexOf("VIDEO") >= 0
          || id.indexOf("mpv") >= 0 || id.indexOf("vlc") >= 0 || id.indexOf("totem") >= 0
    if (sec === "web")
      return tag === "WEB" || id.indexOf("proteus-web-") === 0
          || id.indexOf("firefox") >= 0 || id.indexOf("chromium") >= 0
          || id.indexOf("chrome") >= 0
    if (sec === "apps")
      return !root.matchesSection(a, "games") && !root.matchesSection(a, "media")
          && !root.matchesSection(a, "web")
    return true
  }

  function isHiddenEntry(a) {
    if (!a || !a.name)
      return true
    try {
      if (a.noDisplay)
        return true
    } catch (e) {
    }
    const id = String(a.id || "").toLowerCase()
    const name = String(a.name || "").toLowerCase()
    if (id.indexOf("proteus-settings") >= 0)
      return false
    if (id === "quickshell" || name === "quickshell")
      return true
    if (id.indexOf("wayland") >= 0 && id.indexOf("session") >= 0)
      return true
    return false
  }

  // Lean-back Home *Apps* shelf allowlist — Library keeps the full catalog.
  // Games / Web / Media shelves use their own section filters.
  function isConsoleHomeApp(card) {
    if (!card)
      return false
    const id = String(card.id || card.desktopId || "").toLowerCase()
    const title = String(card.title || "").toLowerCase()
    if (id.indexOf("proteus-settings") >= 0)
      return true
    if (id.indexOf("firefox") >= 0 || id.indexOf("chromium") >= 0 || id.indexOf("chrome") >= 0
        || id.indexOf("brave") >= 0 || id.indexOf("librewolf") >= 0)
      return true
    if (id.indexOf("ghostty") >= 0 || id.indexOf("kitty") >= 0 || id.indexOf("alacritty") >= 0
        || id.indexOf("foot") >= 0 || id.indexOf("wezterm") >= 0 || id.indexOf("konsole") >= 0
        || id.indexOf("proteus-terminal") >= 0)
      return true
    // Explicit denylist for anything that slips past allowlist expansions
    const deny = [
      "calculator", "galculator", "gnome-calculator", "file-roller", "fileroller",
      "mousepad", "gedit", "texteditor", "evince", "nautilus", "thunar", "pcmanfm",
      "hwloc", "lstopo", "nvtop", "htop", "btop", "missioncenter", "mission-center",
      "localsend", "blueman", "pavucontrol", "nm-connection", "system-monitor",
      "baobab", "characters", "gnome-clocks", "font-viewer", "gnome-logs", "yelp"
    ]
    for (let i = 0; i < deny.length; i++) {
      if (id.indexOf(deny[i]) >= 0 || title.indexOf(deny[i]) >= 0)
        return false
    }
    return false
  }

  function iconPathFor(iconName) {
    const name = String(iconName || "")
    if (!name.length)
      return ""
    if (name.indexOf("file:") === 0)
      return name
    if (name.indexOf("/") === 0)
      return "file://" + name
    try {
      const path = Quickshell.iconPath(name, true)
      if (path && path.length)
        return path
    } catch (e) {
    }
    return ""
  }

  readonly property var allApps: {
    const apps = DesktopEntries.applications.values
    const out = []
    for (let i = 0; i < apps.length; i++) {
      const a = apps[i]
      if (root.isHiddenEntry(a))
        continue
      if (EnvGate && typeof EnvGate.appAvailable === "function" && !EnvGate.appAvailable(a))
        continue
      const id = String(a.id || "")
      const title = String(a.name || id)
      const colors = root.colorFor(title)
      let tag = "APP"
      let needsGs = false
      try {
        const cats = a.categories || []
        const catStr = (cats && cats.length) ? cats.join(";").toLowerCase() : ""
        if (catStr.indexOf("game") >= 0) {
          tag = "GAMES"
          needsGs = true
        } else if (cats && cats.length) {
          tag = String(cats[0]).toUpperCase().slice(0, 12)
        }
      } catch (e) {
      }
      const idLower = id.toLowerCase()
      if (idLower.indexOf("steam") >= 0 || idLower.indexOf("retroarch") >= 0) {
        tag = "GAMES"
        needsGs = true
      }
      if (idLower.indexOf("proteus-web-") === 0)
        tag = "WEB"
      let iconName = ""
      try {
        iconName = String(a.icon || "")
      } catch (e2) {
      }
      out.push({
        id: id,
        title: title,
        tag: tag,
        color0: colors.color0,
        color1: colors.color1,
        desktopId: id,
        kind: "desktop",
        needsGamescope: needsGs,
        commandArgs: [],
        chromeStyle: true,
        meta: id,
        icon: iconName,
        iconSource: root.iconPathFor(iconName)
      })
    }
    out.sort((x, y) => String(x.title).localeCompare(String(y.title)))
    return out
  }

  readonly property var sectionedApps: {
    const sec = root.section || "all"
    const out = []
    for (let i = 0; i < root.allApps.length; i++) {
      if (root.matchesSection(root.allApps[i], sec))
        out.push(root.allApps[i])
    }
    return out
  }

  readonly property var webApps: {
    const out = []
    for (let i = 0; i < root.allApps.length; i++) {
      const a = root.allApps[i]
      const id = String(a.id || a.desktopId || "").toLowerCase()
      if (id.indexOf("proteus-web-") === 0)
        out.push(a)
    }
    return out
  }

  // Home Apps shelf — curated lean-back only (isConsoleHomeApp).
  readonly property var appsShelf: {
    const out = []
    for (let i = 0; i < root.allApps.length; i++) {
      const a = root.allApps[i]
      if (!root.matchesSection(a, "apps"))
        continue
      if (!root.isConsoleHomeApp(a))
        continue
      out.push(a)
    }
    return out.slice(0, 24)
  }

  readonly property var gamesShelf: {
    const out = []
    for (let i = 0; i < root.allApps.length; i++) {
      if (root.matchesSection(root.allApps[i], "games"))
        out.push(root.allApps[i])
    }
    return out.slice(0, 24)
  }

  readonly property var mediaShelf: {
    const out = []
    for (let i = 0; i < root.allApps.length; i++) {
      if (root.matchesSection(root.allApps[i], "media"))
        out.push(root.allApps[i])
    }
    return out.slice(0, 24)
  }

  // Search empty-state shortcuts (not a full app dump).
  readonly property var searchShortcuts: [
    {
      id: "action:lock",
      title: "Lock screen",
      tag: "ACTION",
      kind: "action",
      actionId: "lock",
      chromeStyle: true,
      color0: Theme.elevatedFill,
      color1: Theme.bgElevated,
      meta: "Action"
    },
    {
      id: "action:control-center",
      title: "Control Center",
      tag: "ACTION",
      kind: "action",
      actionId: "control-center",
      chromeStyle: true,
      color0: Theme.elevatedFill,
      color1: Theme.bgElevated,
      meta: "Action"
    },
    {
      id: "settings:network-wifi",
      title: "Wi‑Fi",
      tag: "SETTINGS",
      kind: "settings",
      settingsPage: "network-wifi",
      chromeStyle: true,
      color0: Theme.elevatedFill,
      color1: Theme.bgElevated,
      meta: "Settings"
    },
    {
      id: "settings:sound",
      title: "Sound",
      tag: "SETTINGS",
      kind: "settings",
      settingsPage: "sound",
      chromeStyle: true,
      color0: Theme.elevatedFill,
      color1: Theme.bgElevated,
      meta: "Settings"
    },
    {
      id: "settings:displays",
      title: "Displays",
      tag: "SETTINGS",
      kind: "settings",
      settingsPage: "displays",
      chromeStyle: true,
      color0: Theme.elevatedFill,
      color1: Theme.bgElevated,
      meta: "Settings"
    },
    {
      id: "action:enter-desktop",
      title: "Return to Desktop",
      tag: "ACTION",
      kind: "action",
      actionId: "enter-desktop",
      chromeStyle: true,
      color0: Theme.elevatedFill,
      color1: Theme.bgElevated,
      meta: "Posture"
    }
  ]

  readonly property var filtered: {
    const q = String(root.query || "").trim().toLowerCase()
    if (!q.length)
      return root.searchShortcuts
    const out = []
    for (let i = 0; i < root.allApps.length; i++) {
      const a = root.allApps[i]
      const hay = (a.title + " " + a.tag + " " + a.id).toLowerCase()
      const score = UniversalSearch.scoreQuery(hay, q)
      if (score < 0)
        continue
      out.push({
        id: a.id,
        title: a.title,
        tag: a.tag,
        color0: a.color0,
        color1: a.color1,
        desktopId: a.desktopId,
        kind: a.kind,
        needsGamescope: a.needsGamescope,
        commandArgs: a.commandArgs,
        chromeStyle: true,
        meta: a.meta,
        score: score
      })
    }
    const extras = UniversalSearch.consoleExtras(q)
    for (let i = 0; i < extras.length; i++)
      out.push(extras[i])
    out.sort((x, y) => {
      if ((y.score || 0) !== (x.score || 0))
        return (y.score || 0) - (x.score || 0)
      return String(x.title).localeCompare(String(y.title))
    })
    return out.slice(0, 40)
  }
}
