pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Gate Settings panes / launcher / dock by Hardware capabilities.
// Spec: docs/proteus/APPLICATIONS.md · HARDWARE.md
// App manifests: env/apps/catalog.json (preferred over appRules heuristics).
Singleton {
  id: root

  // When probe is not ready, fail open (show everything) so the session is usable.
  readonly property bool gatingActive: Hardware.ready

  // Declarative manifests from env/apps/catalog.json (empty until load).
  property var appManifests: []
  property bool manifestsReady: false
  property string manifestsError: ""

  readonly property string catalogPath: {
    const shell = Quickshell.shellRoot
    if (shell && shell.length)
      return shell + "/../env/apps/catalog.json"
    return "/mnt/proteus/env/apps/catalog.json"
  }

  // North-star sidebar order — status: shipped | partial | stub | planned
  readonly property var settingsCatalog: [
    {
      id: "style",
      label: "Appearance",
      status: "partial",
      requires: [],
      requiresAny: []
    },
    {
      id: "desktop",
      label: "Desktop",
      status: "shipped",
      requires: ["display"],
      requiresAny: []
    },
    {
      id: "displays",
      label: "Displays",
      status: "partial",
      requires: ["display"],
      requiresAny: []
    },
    {
      id: "sound",
      label: "Sound",
      status: "partial",
      requires: [],
      requiresAny: ["speaker", "mic", "qs_pipewire"]
    },
    {
      id: "network",
      label: "Network",
      status: "partial",
      requires: [],
      requiresAny: ["wifi", "ethernet", "bt"]
    },
    {
      id: "peripherals",
      label: "Peripherals",
      status: "shipped",
      requires: [],
      requiresAny: ["keyboard", "pointer"]
    },
    {
      id: "power",
      label: "Power",
      status: "partial",
      requires: [],
      requiresAny: []
    },
    {
      id: "users",
      label: "Users",
      status: "partial",
      requires: [],
      requiresAny: []
    },
    {
      id: "accounts",
      label: "Online accounts",
      status: "partial",
      requires: [],
      requiresAny: []
    },
    {
      id: "datetime",
      label: "Date & time",
      status: "partial",
      requires: [],
      requiresAny: []
    },
    {
      id: "privacy",
      label: "Privacy",
      status: "partial",
      requires: [],
      requiresAny: []
    },
    {
      id: "packages",
      label: "Software",
      status: "partial",
      requires: [],
      requiresAny: []
    },
    {
      id: "system",
      label: "About",
      status: "partial",
      requires: [],
      requiresAny: []
    }
  ]

  // Desktop-id / name / category heuristics → capability needs (Wave A).
  readonly property var appRules: [
    {
      match: /(pavucontrol|easyeffects|qpwgraph|helvum|cadence|carla|audacity)/i,
      requiresAny: ["speaker", "mic", "qs_pipewire"],
      reason: "Needs audio"
    },
    {
      match: /(nm-connection|nmtui|networkmanager|wifi|wi-fi)/i,
      requiresAny: ["wifi", "ethernet"],
      reason: "Needs network"
    },
    {
      match: /(blueman|blueberry|bluetooth)/i,
      requiresAny: ["bt"],
      reason: "Needs Bluetooth"
    },
    {
      match: /(virt-manager|virtualbox|gnome-boxes|aqemu)/i,
      requiresAny: ["libvirt", "containers"],
      reason: "Needs virtualization"
    },
    {
      match: /(steam|lutris|heroic|gamescope)/i,
      requiresAny: ["display"],
      reason: "Needs a display"
    }
  ]

  function hasAll(list) {
    if (!list || !list.length)
      return true
    for (let i = 0; i < list.length; i++) {
      if (!Hardware.has(list[i]))
        return false
    }
    return true
  }

  function hasAny(list) {
    if (!list || !list.length)
      return true
    for (let i = 0; i < list.length; i++) {
      if (Hardware.has(list[i]))
        return true
    }
    return false
  }

  function paneSpec(id) {
    for (let i = 0; i < settingsCatalog.length; i++) {
      if (settingsCatalog[i].id === id)
        return settingsCatalog[i]
    }
    return null
  }

  function paneAvailable(id) {
    if (!gatingActive)
      return true
    const spec = paneSpec(id)
    if (!spec)
      return true
    return hasAll(spec.requires) && hasAny(spec.requiresAny)
  }

  function paneBlockReason(id) {
    if (paneAvailable(id))
      return ""
    const spec = paneSpec(id)
    if (!spec)
      return "Unavailable on this device"
    if (spec.requiresAny && spec.requiresAny.length)
      return "Needs " + spec.requiresAny.join(" or ")
    if (spec.requires && spec.requires.length)
      return "Needs " + spec.requires.join(", ")
    return "Unavailable on this device"
  }

  function availableSettingsPanes() {
    const out = []
    for (let i = 0; i < settingsCatalog.length; i++) {
      const p = settingsCatalog[i]
      if (paneAvailable(p.id))
        out.push(p)
    }
    return out
  }

  function firstAvailablePane() {
    const panes = availableSettingsPanes()
    return panes.length ? panes[0].id : "system"
  }

  function ensureSettingsPageValid(nav) {
    // `nav` is SettingsNav when called from the Settings app (not present in shell-only).
    if (!gatingActive || !nav)
      return
    const page = nav.page
    const p = String(page)
    const isStyleDrill = p === "style" || p.startsWith("style-")
    const isDesktopDrill = p === "desktop" || p.startsWith("desktop-")
    const isPeripheralsDrill = p === "peripherals" || p.startsWith("peripherals-") || p === "keyboard"
    const isPackagesDrill = p === "packages" || p.startsWith("packages-")
    const isSoundDrill = p === "sound" || p.startsWith("sound-")
    if (isStyleDrill) {
      if (!paneAvailable("style"))
        nav.page = firstAvailablePane()
      return
    }
    if (isDesktopDrill) {
      if (!paneAvailable("desktop"))
        nav.page = firstAvailablePane()
      return
    }
    if (isPeripheralsDrill) {
      if (!paneAvailable("peripherals"))
        nav.page = firstAvailablePane()
      return
    }
    if (isPackagesDrill) {
      if (!paneAvailable("packages"))
        nav.page = firstAvailablePane()
      return
    }
    if (isSoundDrill) {
      if (!paneAvailable("sound"))
        nav.page = firstAvailablePane()
      return
    }
    if (!paneAvailable(page))
      nav.page = firstAvailablePane()
  }

  function categoriesOf(entry) {
    const c = entry && entry.categories
    if (!c)
      return ""
    if (typeof c === "string")
      return c
    if (c.join)
      return c.join(";")
    return String(c)
  }

  function normalizeDesktopId(id) {
    let s = String(id || "").toLowerCase().trim()
    if (s.endsWith(".desktop"))
      s = s.slice(0, -8)
    return s
  }

  function applyCatalog(obj) {
    const list = (obj && obj.manifests) ? obj.manifests : []
    if (!Array.isArray(list)) {
      manifestsError = "catalog.manifests must be an array"
      appManifests = []
      manifestsReady = false
      return
    }
    appManifests = list
    manifestsError = ""
    manifestsReady = true
  }

  function loadManifests() {
    const path = catalogPath
    catalogProc.command = [
      "bash",
      "-lc",
      "test -f " + shellQuote(path) + " && cat " + shellQuote(path) + " || echo ''"
    ]
    catalogProc.running = false
    catalogProc.running = true
  }

  function shellQuote(s) {
    return "'" + String(s).replace(/'/g, "'\\''") + "'"
  }

  function manifestForApp(entry) {
    if (!entry || !appManifests || !appManifests.length)
      return null
    const id = normalizeDesktopId(entry.id)
    const hay = [
      entry.id || "",
      entry.name || "",
      entry.genericName || "",
      entry.execString || entry.exec || ""
    ].join(" ")
    for (let i = 0; i < appManifests.length; i++) {
      const m = appManifests[i]
      if (!m)
        continue
      if (m.id && normalizeDesktopId(m.id) === id)
        return m
      const ids = m.desktopIds || []
      for (let j = 0; j < ids.length; j++) {
        if (normalizeDesktopId(ids[j]) === id)
          return m
      }
      if (m.match) {
        try {
          if (new RegExp(m.match, "i").test(hay))
            return m
        } catch (e) {
          // ignore bad regex in catalog
        }
      }
    }
    return null
  }

  function ruleFromManifest(m) {
    if (!m)
      return null
    return {
      requires: m.requires || [],
      requiresAny: m.requiresAny || [],
      reason: m.reason || "Unavailable on this device"
    }
  }

  function ruleForApp(entry) {
    if (!entry)
      return null
    const fromMan = ruleFromManifest(manifestForApp(entry))
    if (fromMan)
      return fromMan
    const hay = [
      entry.id || "",
      entry.name || "",
      entry.genericName || "",
      categoriesOf(entry),
      entry.execString || entry.exec || ""
    ].join(" ")
    for (let i = 0; i < appRules.length; i++) {
      if (appRules[i].match.test(hay))
        return appRules[i]
    }
    const cats = categoriesOf(entry).toLowerCase()
    if (cats.indexOf("audiovideo") >= 0 || /(^|;)audio(;|$)/.test(cats)) {
      return {
        requiresAny: ["speaker", "mic", "qs_pipewire"],
        reason: "Needs audio"
      }
    }
    if (cats.indexOf("network") >= 0) {
      return {
        requiresAny: ["wifi", "ethernet", "bt"],
        reason: "Needs network"
      }
    }
    return null
  }

  Component.onCompleted: loadManifests()

  Process {
    id: catalogProc
    stdout: StdioCollector {
      onStreamFinished: {
        const text = this.text
        if (!text || !String(text).trim().length) {
          root.manifestsError = "catalog missing"
          root.appManifests = []
          root.manifestsReady = false
          return
        }
        try {
          root.applyCatalog(JSON.parse(String(text).trim()))
        } catch (e) {
          root.manifestsError = "catalog parse failed"
          root.appManifests = []
          root.manifestsReady = false
        }
      }
    }
  }

  function appAvailable(entry) {
    if (!gatingActive)
      return true
    const rule = ruleForApp(entry)
    if (!rule)
      return true
    if (rule.requires && !hasAll(rule.requires))
      return false
    if (rule.requiresAny && !hasAny(rule.requiresAny))
      return false
    return true
  }

  function appBlockReason(entry) {
    if (appAvailable(entry))
      return ""
    const rule = ruleForApp(entry)
    return (rule && rule.reason) ? rule.reason : "Unavailable on this device"
  }

  function dockEntryAvailable(entry) {
    if (!gatingActive || !entry)
      return true
    if (entry.requiresAny && entry.requiresAny.length)
      return hasAny(entry.requiresAny)
    if (entry.requires && entry.requires.length)
      return hasAll(entry.requires)
    return true
  }
}
