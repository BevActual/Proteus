import Quickshell
import QtQuick
import "../../shared"

// DesktopEntries + UniversalSearch → Games / Media (streaming) / Search / Settings lists.
QtObject {
  id: root

  property string query: ""
  property string filterText: ""
  // Destination catalog: apps | games | media | search | settings
  property string section: "games"
  // mpv (or another local player) present — enables the local-media shortcut
  // under Search. Media stays streaming-only per POSTURES.
  property bool hasLocalPlayer: false
  // Injected by ConsoleHome: installed titles (proteus-console-games.py scan)
  // and hydrated recents (Config.consoleRecents) for the Games tab sections.
  property var installedTitles: []
  property var recentItems: []

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

  // Local file players — findable under Search, not Media (streaming).
  readonly property var localPlayerIds: [
    "mpv", "vlc", "totem", "celluloid", "smplayer", "smtube", "parole",
    "dragonplayer", "kaffeine", "gmplayer", "mplayer", "xine", "haruna",
    "io.github.celluloid_player", "org.videolan.vlc"
  ]

  // Discord lives under Apps (isConsoleAppsDest), not Media.
  readonly property var streamingHints: [
    "spotify", "plex", "jellyfin", "netflix", "hbo", "disney", "youtube",
    "prime", "amazon.?video", "apple.?music", "apple.?tv", "tidal", "deezer",
    "crunchyroll", "twitch", "hulu", "paramount", "peacock", "max",
    "music.youtube", "youtubemusic", "soundcloud", "pandora",
    "audible", "emby", "kodi", "stremio", "tubi", "roku"
  ]

  function colorFor(name) {
    const s = String(name || "")
    let h = 0
    for (let i = 0; i < s.length; i++)
      h = (h + s.charCodeAt(i) * (i + 1)) % 997
    return root.palette[h % root.palette.length]
  }

  function isLocalPlayer(a) {
    if (!a)
      return false
    const id = String(a.id || a.desktopId || "").toLowerCase()
    const title = String(a.title || a.name || "").toLowerCase()
    for (let i = 0; i < root.localPlayerIds.length; i++) {
      const p = root.localPlayerIds[i]
      if (id.indexOf(p) >= 0 || title === p || title.indexOf(p + " ") === 0)
        return true
    }
    return false
  }

  function isStreamingApp(a) {
    if (!a || root.isLocalPlayer(a))
      return false
    const id = String(a.id || a.desktopId || "").toLowerCase()
    const title = String(a.title || a.name || "").toLowerCase()
    const tag = String(a.tag || "").toUpperCase()
    const hay = id + " " + title
    for (let i = 0; i < root.streamingHints.length; i++) {
      try {
        if (new RegExp(root.streamingHints[i], "i").test(hay))
          return true
      } catch (e) {
        if (hay.indexOf(root.streamingHints[i]) >= 0)
          return true
      }
    }
    // proteus-web-* streaming clients (name match already covered; keep web apps that look like media)
    if (id.indexOf("proteus-web-") === 0) {
      const streamWeb = [
        "spotify", "netflix", "hbo", "disney", "youtube", "plex", "music",
        "twitch", "hulu", "prime", "tidal", "deezer", "crunchyroll", "max"
      ]
      for (let j = 0; j < streamWeb.length; j++) {
        if (hay.indexOf(streamWeb[j]) >= 0)
          return true
      }
    }
    // No AudioVideo-category fallback: desktop tools (qpwgraph, V4L2 test
    // utilities, local players) are not lean-back streaming. Media stays
    // streaming-only — unknown services can be added as web apps.
    return false
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
          || id.indexOf("heroic") >= 0 || id.indexOf("lutris") >= 0
    if (sec === "media")
      return root.isStreamingApp(a)
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

  // Apps top destination — browser, Discord, terminal, non-stream web apps.
  // Excludes games, streaming Media, and local players.
  function isConsoleAppsDest(card) {
    if (!card)
      return false
    if (root.matchesSection(card, "games") || root.isStreamingApp(card) || root.isLocalPlayer(card))
      return false
    if (root.isConsoleHomeApp(card))
      return true
    const id = String(card.id || card.desktopId || "").toLowerCase()
    const title = String(card.title || "").toLowerCase()
    const hay = id + " " + title
    const allow = [
      "discord", "slack", "telegram", "signal", "element",
      "obsidian", "code", "cursor"
    ]
    for (let i = 0; i < allow.length; i++) {
      if (hay.indexOf(allow[i]) >= 0)
        return true
    }
    if (id.indexOf("proteus-web-") === 0)
      return true
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

  function textMatches(item, q, f) {
    const hay = (String(item.title || "") + " " + String(item.tag || "")
        + " " + String(item.id || "") + " " + String(item.meta || "")).toLowerCase()
    if (q.length && hay.indexOf(q) < 0)
      return false
    if (f.length && hay.indexOf(f) < 0)
      return false
    return true
  }

  function filterList(items, q, f) {
    const query = String(q || "").trim().toLowerCase()
    const filt = String(f || "").trim().toLowerCase()
    if (!query.length && !filt.length)
      return items
    const out = []
    for (let i = 0; i < items.length; i++) {
      if (root.textMatches(items[i], query, filt))
        out.push(items[i])
    }
    return out
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
        } else if (catStr.indexOf("audio") >= 0 || catStr.indexOf("video") >= 0
            || catStr.indexOf("tv") >= 0) {
          tag = "MEDIA"
        } else if (cats && cats.length) {
          tag = String(cats[0]).toUpperCase().slice(0, 12)
        }
      } catch (e) {
      }
      const idLower = id.toLowerCase()
      if (idLower.indexOf("steam") >= 0 || idLower.indexOf("retroarch") >= 0
          || idLower.indexOf("heroic") >= 0 || idLower.indexOf("lutris") >= 0) {
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

  readonly property var appsList: {
    const out = []
    for (let i = 0; i < root.allApps.length; i++) {
      if (root.isConsoleAppsDest(root.allApps[i]))
        out.push(root.allApps[i])
    }
    return root.filterList(out, root.query, root.filterText)
  }

  function gamesSection(id, label) {
    const colors = root.colorFor("Games")
    return {
      id: "section:games-" + id,
      title: String(label).toUpperCase(),
      tag: "",
      kind: "section",
      isSection: true,
      chromeStyle: true,
      color0: colors.color0,
      color1: colors.color1,
      meta: "",
      iconSource: "",
      selectable: false
    }
  }

  // Games tab = Recent (jump back in) · Installed (real titles from the
  // Steam/RetroArch scan) · Launchers (store/frontend desktop entries).
  // Section headers only when more than one group has content.
  readonly property var gamesList: {
    const launchers = []
    for (let i = 0; i < root.allApps.length; i++) {
      if (root.matchesSection(root.allApps[i], "games"))
        launchers.push(root.allApps[i])
    }
    const groups = []
    const recents = root.filterList(root.recentItems || [], root.query, root.filterText)
    if (recents.length)
      groups.push({ id: "recent", label: "Recent", items: recents })
    const titles = root.filterList(root.installedTitles || [], root.query, root.filterText)
    if (titles.length)
      groups.push({ id: "installed", label: "Installed", items: titles })
    const launch = root.filterList(launchers, root.query, root.filterText)
    if (launch.length)
      groups.push({ id: "launchers", label: "Launchers", items: launch })
    if (!groups.length)
      return []
    if (groups.length === 1)
      return groups[0].items
    const out = []
    for (let g = 0; g < groups.length; g++) {
      out.push(root.gamesSection(groups[g].id, groups[g].label))
      for (let k = 0; k < groups[g].items.length; k++)
        out.push(groups[g].items[k])
    }
    return out
  }

  readonly property var mediaList: {
    const out = []
    for (let i = 0; i < root.allApps.length; i++) {
      if (root.isStreamingApp(root.allApps[i]))
        out.push(root.allApps[i])
    }
    return root.filterList(out, root.query, root.filterText)
  }

  readonly property var settingsList: {
    const q = String(root.query || "").trim().toLowerCase()
    const f = String(root.filterText || "").trim().toLowerCase()
    const colors = root.colorFor("Settings")
    const out = []

    function hubLabel(hubId) {
      try {
        const panes = EnvGate.availableSettingsPanes() || []
        for (let i = 0; i < panes.length; i++) {
          if (String(panes[i].id) === hubId)
            return String(panes[i].label || hubId)
        }
        const cat = EnvGate.settingsCatalog || []
        for (let j = 0; j < cat.length; j++) {
          if (String(cat[j].id) === hubId)
            return String(cat[j].label || hubId)
        }
      } catch (e) {
      }
      return hubId
    }

    function pushSection(hubId, label) {
      out.push({
        id: "section:" + hubId,
        title: String(label || hubId).toUpperCase(),
        tag: "",
        kind: "section",
        isSection: true,
        settingsPage: "",
        hubId: hubId,
        chromeStyle: true,
        color0: colors.color0,
        color1: colors.color1,
        meta: "",
        iconSource: "",
        selectable: false
      })
    }

    function pushPage(page, title, hubId, hubLbl) {
      out.push({
        id: "settings:" + page,
        title: title,
        tag: page === hubId ? "HUB" : "LEAF",
        kind: "settings",
        settingsPage: page,
        hubId: hubId,
        chromeStyle: true,
        color0: colors.color0,
        color1: colors.color1,
        meta: hubLbl || hubId,
        iconSource: "",
        selectable: true
      })
    }

    function matches(title, page, hub, keywords) {
      if (!q.length && !f.length)
        return true
      const hay = (String(title || "") + " " + String(page || "") + " "
          + String(hub || "") + " " + String(keywords || "")).toLowerCase()
      if (q.length && hay.indexOf(q) < 0)
        return false
      if (f.length && hay.indexOf(f) < 0)
        return false
      return true
    }

    let catalog = []
    try {
      // Console Settings face — not the full desktop catalog.
      if (EnvGate && typeof EnvGate.availableSettingsPanesForFace === "function")
        catalog = EnvGate.availableSettingsPanesForFace("console") || []
      else if (EnvGate && EnvGate.settingsCatalog)
        catalog = EnvGate.settingsCatalog
    } catch (e0) {
    }
    let index = []
    try {
      index = (EnvGate && EnvGate.settingsSearchIndex) ? EnvGate.settingsSearchIndex : []
    } catch (e1) {
    }

    // Walk console Settings face hub order (SETTINGS-IA § Posture faces).
    for (let c = 0; c < catalog.length; c++) {
      const hub = catalog[c]
      const hubId = String(hub.id || "")
      if (!hubId.length)
        continue
      let hubOk = true
      try {
        hubOk = EnvGate.paneAvailable(hubId)
      } catch (e2) {
        hubOk = true
      }
      if (!hubOk)
        continue

      const hLabel = String(hub.label || hubId)
      const group = []

      // Hub row first
      if (matches(hLabel, hubId, hubId, ""))
        group.push({ page: hubId, title: hLabel, keywords: "" })

      // Leaves under this hub (index order, not A–Z — mirrors Settings sidebar drill)
      for (let k = 0; k < index.length; k++) {
        const e = index[k]
        const page = String(e.id || "")
        const leafHub = String(e.hubId || "")
        if (!page.length || page === hubId)
          continue
        if (leafHub !== hubId)
          continue
        let leafOk = true
        try {
          leafOk = EnvGate.paneAvailable(page)
        } catch (e3) {
        }
        if (!leafOk)
          continue
        const title = String(e.label || page)
        if (!matches(title, page, hubId, e.keywords || ""))
          continue
        group.push({ page: page, title: title, keywords: e.keywords || "" })
      }

      if (!group.length)
        continue
      pushSection(hubId, hLabel)
      for (let g = 0; g < group.length; g++)
        pushPage(group[g].page, group[g].title, hubId, hLabel)
    }
    return out
  }

  readonly property var searchShortcuts: {
    const out = baseSearchShortcuts.slice()
    if (root.hasLocalPlayer) {
      out.push({
        id: "media:local",
        title: "Play a media file…",
        tag: "MEDIA",
        kind: "media",
        chromeStyle: true,
        color0: Theme.elevatedFill,
        color1: Theme.bgElevated,
        meta: "mpv · Resume · Choose file"
      })
    }
    return out
  }

  readonly property var baseSearchShortcuts: [
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
    const f = String(root.filterText || "").trim().toLowerCase()
    if (!q.length && !f.length)
      return root.filterList(root.searchShortcuts, "", f)
    const out = []
    for (let i = 0; i < root.allApps.length; i++) {
      const a = root.allApps[i]
      const hay = (a.title + " " + a.tag + " " + a.id).toLowerCase()
      if (f.length && hay.indexOf(f) < 0)
        continue
      const score = q.length ? UniversalSearch.scoreQuery(hay, q) : 1
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
        iconSource: a.iconSource,
        score: score
      })
    }
    if (q.length) {
      const extras = UniversalSearch.consoleExtras(q)
      for (let i = 0; i < extras.length; i++) {
        const e = extras[i]
        if (f.length) {
          const eh = (String(e.title || "") + " " + String(e.id || "")).toLowerCase()
          if (eh.indexOf(f) < 0)
            continue
        }
        out.push(e)
      }
    }
    out.sort((x, y) => {
      if ((y.score || 0) !== (x.score || 0))
        return (y.score || 0) - (x.score || 0)
      return String(x.title).localeCompare(String(y.title))
    })
    return out.slice(0, 40)
  }
}
