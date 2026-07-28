pragma Singleton

import Quickshell
import QtQuick

// Lock + desktop applet catalog and CRUD.
//
// Extracted from Config.qml. Instance arrays stay in Config (one FileView owns
// settings.json); this singleton is behaviour + derived lists only.
Singleton {
  id: root

  // Applet sizes — common to both surfaces (lockWidgetSizes kept as the old name).
  readonly property var widgetSizes: [
    {
      id: "sm",
      label: "S"
    },
    {
      id: "md",
      label: "M"
    },
    {
      id: "lg",
      label: "L"
    }
  ]

  readonly property var lockWidgetSizes: widgetSizes

  readonly property bool lockHasClockWidget: {
    const list = lockWidgetsList
    for (let i = 0; i < list.length; i++) {
      if (list[i].type === "clock" && list[i].enabled)
        return true
    }
    return false
  }

  // Single registration point for applet types. Lock and desktop keep separate
  // *instances* and separate layout models, but a widget is declared once here:
  // `source` is resolved by both applet hosts, and `lock`/`desktop` carry only
  // the fields that genuinely differ per surface. Adding a widget = one entry
  // here plus one QML file under surfaces/desktop/widgets/.
  readonly property var widgetCatalog: [
    {
      id: "clock",
      label: "Clock",
      category: "Time",
      icon: "🕒",
      defaultSize: "lg",
      unique: true,
      source: "widgets/ClockWidget.qml",
      // chrome: pinned to the lock surface — cannot be resized or removed there
      lock: {
        hint: "Lock chrome — time and date",
        chrome: true
      },
      desktop: {
        hint: "Time and date"
      }
    },
    {
      id: "media",
      label: "Now playing",
      hint: "Album art + track controls",
      category: "Music",
      icon: "♪",
      defaultSize: "md",
      unique: true,
      source: "widgets/MediaWidget.qml"
    },
    {
      id: "battery",
      label: "Battery",
      hint: "Charge level",
      category: "System",
      icon: "🔋",
      defaultSize: "sm",
      unique: true,
      source: "widgets/BatteryWidget.qml"
    },
    {
      id: "weather",
      label: "Weather",
      hint: "Conditions for your location",
      category: "Outside",
      icon: "⛅",
      defaultSize: "md",
      unique: true,
      source: "widgets/WeatherWidget.qml"
    }
  ]

  // Flattens widgetCatalog for one surface: base fields, with that surface's
  // overrides merged over the top. The per-surface keys are dropped so callers
  // see a plain catalog entry exactly as before.
  function widgetCatalogFor(surface) {
    const key = String(surface || "desktop")
    const out = []
    for (let i = 0; i < widgetCatalog.length; i++) {
      const src = widgetCatalog[i]
      const entry = {}
      for (const k in src) {
        if (k === "lock" || k === "desktop")
          continue
        entry[k] = src[k]
      }
      const over = src[key]
      if (over) {
        for (const k in over)
          entry[k] = over[k]
      }
      out.push(entry)
    }
    return out
  }

  // Component path for an applet type, resolved relative to the applet hosts.
  function widgetSourceFor(type) {
    const t = String(type || "")
    for (let i = 0; i < widgetCatalog.length; i++) {
      if (widgetCatalog[i].id === t)
        return String(widgetCatalog[i].source || "")
    }
    return ""
  }

  // Catalog of lock applets (Customize Lock Screen gallery).
  readonly property var lockWidgetCatalog: widgetCatalogFor("lock")

  readonly property var lockClockWeights: [
    { id: "light", label: "Light" },
    { id: "normal", label: "Regular" },
    { id: "medium", label: "Medium" }
  ]

  readonly property var lockClockDateStyles: [
    { id: "full", label: "Full" },
    { id: "short", label: "Short" }
  ]

  readonly property var lockWidgetsList: {
    const raw = Config.lockWidgets
    if (!raw || !raw.length)
      return []
    const out = []
    for (let i = 0; i < raw.length; i++) {
      const n = normalizeLockWidget(raw[i])
      if (n)
        out.push(n)
    }
    return out
  }

  readonly property var lockWidgetsEnabledList: {
    return lockWidgetsList.filter(w => !!w.enabled)
  }

  readonly property var lockClockWidget: {
    const list = lockWidgetsEnabledList
    for (let i = 0; i < list.length; i++) {
      if (list[i].type === "clock")
        return list[i]
    }
    return null
  }

  readonly property var lockStripWidgets: {
    const list = lockWidgetsEnabledList.filter(w => w.type !== "clock")
    list.sort((a, b) => (a.slot - b.slot) || String(a.id).localeCompare(String(b.id)))
    return list
  }

  // Desktop widgets — free place (not stacked). Same applet types; separate instances.
  readonly property var desktopWidgetCatalog: widgetCatalogFor("desktop")

  readonly property var desktopWidgetsList: {
    const raw = Config.desktopWidgets
    if (!raw || !raw.length)
      return []
    const out = []
    for (let i = 0; i < raw.length; i++) {
      const n = normalizeDesktopWidget(raw[i])
      if (n)
        out.push(n)
    }
    return out
  }

  readonly property var desktopWidgetsEnabledList: {
    return desktopWidgetsList.filter(w => !!w.enabled)
  }

  function lockWidgetIdNew() {
    return "lw-" + Math.random().toString(16).slice(2, 9)
  }

  function lockWidgetSpanForSize(size) {
    const s = String(size || "md")
    if (s === "sm")
      return 1
    if (s === "lg")
      return 4
    return 2
  }

  function normalizeLockWidget(w) {
    const type = String((w && w.type) || "")
    let meta = null
    for (let i = 0; i < lockWidgetCatalog.length; i++) {
      if (lockWidgetCatalog[i].id === type) {
        meta = lockWidgetCatalog[i]
        break
      }
    }
    if (!meta)
      return null
    let size = String((w && w.size) || meta.defaultSize || "md")
    if (size !== "sm" && size !== "md" && size !== "lg")
      size = String(meta.defaultSize || "md")
    let slot = Number(w && w.slot)
    if (isNaN(slot) || slot < 0) {
      // Migrate legacy free-place → slot by former y then x
      const y = Number(w && w.y)
      const x = Number(w && w.x)
      if (!isNaN(y) || !isNaN(x))
        slot = Math.round((isNaN(y) ? 0.5 : y) * 1000) + Math.round((isNaN(x) ? 0.5 : x) * 10)
      else
        slot = 0
    }
    let weight = String((w && w.clockWeight) || "light")
    if (weight !== "light" && weight !== "normal" && weight !== "medium")
      weight = "light"
    let dateStyle = String((w && w.dateStyle) || "full")
    if (dateStyle !== "full" && dateStyle !== "short")
      dateStyle = "full"
    let clockColor = String((w && w.clockColor) || "#f5f5f7")
    if (!clockColor.length || clockColor.charAt(0) !== "#")
      clockColor = "#f5f5f7"
    return {
      id: String((w && w.id) || lockWidgetIdNew()),
      type: type,
      label: String(meta.label || type),
      enabled: w && w.enabled === false ? false : true,
      slot: Math.round(slot),
      size: size,
      span: lockWidgetSpanForSize(size),
      showControls: w && w.showControls === false ? false : true,
      showWhenIdle: !!(w && w.showWhenIdle),
      clockWeight: weight,
      clockColor: clockColor,
      showDate: w && w.showDate === false ? false : true,
      dateStyle: dateStyle,
      clockDepth: w && w.clockDepth === false ? false : true
    }
  }

  function compactLockWidgetSlots(list) {
    const clocks = []
    const strip = []
    for (let i = 0; i < list.length; i++) {
      if (list[i].type === "clock")
        clocks.push(list[i])
      else
        strip.push(list[i])
    }
    strip.sort((a, b) => (a.slot - b.slot) || String(a.id).localeCompare(String(b.id)))
    for (let i = 0; i < strip.length; i++) {
      strip[i] = normalizeLockWidget(Object.assign({}, strip[i], {
        slot: i,
        span: lockWidgetSpanForSize(strip[i].size)
      }))
    }
    return clocks.concat(strip)
  }

  function hydrateLockFromRaw(raw) {
    try {
      if (raw && String(raw).trim().length) {
        const d = JSON.parse(String(raw))
        if (Array.isArray(d.lockWidgets)) {
          Config.lockWidgets = compactLockWidgetSlots(d.lockWidgets.map(w => normalizeLockWidget(w)).filter(w => w !== null))
        }
      }
    } catch (e) {
    }
    if (!Array.isArray(Config.lockWidgets))
      Config.lockWidgets = []
    ensureLockClockWidget()
  }

  function hydrateLockWidgetsFromFile() {
    // Prefer Config's FileView text via hydrateLockFromRaw(caller).
    hydrateLockFromRaw("")
  }

  function ensureLockClockWidget() {
    const list = lockWidgetsList.slice()
    for (let i = 0; i < list.length; i++) {
      if (list[i].type === "clock")
        return list[i]
    }
    const enabled = Config.lockShowClock !== false
    const w = normalizeLockWidget({
      id: lockWidgetIdNew(),
      type: "clock",
      enabled: enabled,
      size: "lg",
      slot: 0,
      clockWeight: "light",
      clockColor: "#f5f5f7",
      showDate: true,
      dateStyle: "full",
      clockDepth: true
    })
    list.unshift(w)
    Config.lockWidgets = compactLockWidgetSlots(list)
    Config.lockShowClock = !!enabled
    return w
  }

  function addLockWidget(type, size) {
    const t = String(type || "")
    let found = null
    for (let i = 0; i < lockWidgetCatalog.length; i++) {
      if (lockWidgetCatalog[i].id === t) {
        found = lockWidgetCatalog[i]
        break
      }
    }
    if (!found)
      return null
    let list = lockWidgetsList.slice()
    for (let i = 0; i < list.length; i++) {
      if (String(list[i].type) === t) {
        if (!list[i].enabled)
          setLockWidgetEnabled(list[i].id, true)
        if (size)
          setLockWidgetSize(list[i].id, size)
        return list[i]
      }
    }
    const stripCount = list.filter(w => w.type !== "clock").length
    const w = normalizeLockWidget({
      id: lockWidgetIdNew(),
      type: t,
      enabled: true,
      showControls: true,
      showWhenIdle: t === "media",
      size: size || found.defaultSize || "md",
      slot: stripCount
    })
    list.push(w)
    Config.lockWidgets = compactLockWidgetSlots(list)
    if (t === "clock")
      Config.lockShowClock = true
    Config.flushSettings()
    return w
  }

  function removeLockWidget(id) {
    const sid = String(id || "")
    let target = null
    for (let i = 0; i < lockWidgetsList.length; i++) {
      if (String(lockWidgetsList[i].id) === sid) {
        target = lockWidgetsList[i]
        break
      }
    }
    if (target && target.type === "clock")
      return
    const next = lockWidgetsList.filter(w => String(w.id) !== sid)
    Config.lockWidgets = compactLockWidgetSlots(next)
    Config.lockShowClock = lockHasClockWidget
    Config.flushSettings()
  }

  function setLockWidgetEnabled(id, on) {
    patchLockWidget(id, {
      enabled: !!on
    })
    const list = lockWidgetsList
    for (let i = 0; i < list.length; i++) {
      if (String(list[i].id) === String(id) && list[i].type === "clock") {
        Config.lockShowClock = !!on
        break
      }
    }
  }

  function patchLockWidget(id, patch) {
    const sid = String(id || "")
    const p = patch || {}
    let list = lockWidgetsList.map(w => {
      if (String(w.id) !== sid)
        return w
      return normalizeLockWidget(Object.assign({}, w, p, {
        id: w.id,
        type: w.type
      }))
    }).filter(w => w !== null)
    if (p && ("size" in p || "slot" in p))
      list = compactLockWidgetSlots(list)
    Config.lockWidgets = list
    Config.flushSettings()
  }

  function moveLockWidget(id, x, y) {
    // Map vertical position into strip reorder
    let ny = Number(y)
    if (isNaN(ny))
      ny = Number(x)
    if (isNaN(ny))
      return
    const strip = lockStripWidgets
    const slot = Math.max(0, Math.min(strip.length, Math.round(ny * Math.max(1, strip.length))))
    moveLockWidgetToSlot(id, slot)
  }

  function moveLockWidgetToSlot(id, slot) {
    const sid = String(id || "")
    let list = lockWidgetsList.slice()
    let item = null
    for (let i = 0; i < list.length; i++) {
      if (String(list[i].id) === sid) {
        item = list[i]
        break
      }
    }
    if (!item || item.type === "clock")
      return
    const others = list.filter(w => String(w.id) !== sid && w.type !== "clock")
    others.sort((a, b) => (a.slot - b.slot) || String(a.id).localeCompare(String(b.id)))
    const idx = Math.max(0, Math.min(others.length, Math.round(Number(slot) || 0)))
    others.splice(idx, 0, item)
    for (let i = 0; i < others.length; i++)
      others[i] = normalizeLockWidget(Object.assign({}, others[i], { slot: i }))
    const clocks = list.filter(w => w.type === "clock")
    Config.lockWidgets = clocks.concat(others)
    Config.flushSettings()
  }

  function setLockWidgetSize(id, size) {
    const s = String(size || "md")
    if (s !== "sm" && s !== "md" && s !== "lg")
      return
    patchLockWidget(id, {
      size: s,
      span: lockWidgetSpanForSize(s)
    })
  }

  function cycleLockWidgetSize(id) {
    let w = null
    const wid = String(id)
    for (let i = 0; i < lockWidgetsList.length; i++) {
      if (String(lockWidgetsList[i].id) === wid) {
        w = lockWidgetsList[i]
        break
      }
    }
    if (!w || w.type === "clock")
      return
    const order = ["sm", "md", "lg"]
    const i = order.indexOf(String(w.size || "md"))
    setLockWidgetSize(id, order[(i + 1) % order.length])
  }

  function lockHasWidgetType(type) {
    const t = String(type || "")
    const list = lockWidgetsList
    for (let i = 0; i < list.length; i++) {
      if (String(list[i].type) === t)
        return true
    }
    return false
  }

  function desktopWidgetIdNew() {
    return "dw-" + Math.random().toString(16).slice(2, 9)
  }

  function desktopWidgetSpanForSize(size) {
    return lockWidgetSpanForSize(size)
  }

  function clamp01(v, fallback) {
    const n = Number(v)
    if (isNaN(n))
      return fallback
    return Math.max(0, Math.min(1, n))
  }

  function nextDesktopWidgetPos(list) {
    const n = (list && list.length) ? list.length : 0
    return {
      x: Math.min(0.72, 0.08 + (n % 3) * 0.28),
      y: Math.min(0.68, 0.12 + Math.floor(n / 3) * 0.22)
    }
  }

  function normalizeDesktopWidget(w) {
    const type = String((w && w.type) || "")
    let meta = null
    for (let i = 0; i < desktopWidgetCatalog.length; i++) {
      if (desktopWidgetCatalog[i].id === type) {
        meta = desktopWidgetCatalog[i]
        break
      }
    }
    if (!meta)
      return null
    let size = String((w && w.size) || meta.defaultSize || "md")
    if (size !== "sm" && size !== "md" && size !== "lg")
      size = String(meta.defaultSize || "md")
    let weight = String((w && w.clockWeight) || "light")
    if (weight !== "light" && weight !== "normal" && weight !== "medium")
      weight = "light"
    let dateStyle = String((w && w.dateStyle) || "full")
    if (dateStyle !== "full" && dateStyle !== "short")
      dateStyle = "full"
    let clockColor = String((w && w.clockColor) || "#f5f5f7")
    if (!clockColor.length || clockColor.charAt(0) !== "#")
      clockColor = "#f5f5f7"
    return {
      id: String((w && w.id) || desktopWidgetIdNew()),
      type: type,
      label: String(meta.label || type),
      enabled: w && w.enabled === false ? false : true,
      x: clamp01(w && w.x, 0.5),
      y: clamp01(w && w.y, 0.2),
      size: size,
      span: desktopWidgetSpanForSize(size),
      showControls: w && w.showControls === false ? false : true,
      showWhenIdle: !!(w && w.showWhenIdle),
      clockWeight: weight,
      clockColor: clockColor,
      showDate: w && w.showDate === false ? false : true,
      dateStyle: dateStyle,
      clockDepth: w && w.clockDepth === false ? false : true
    }
  }

  function hydrateDesktopFromRaw(raw) {
    try {
      if (raw && String(raw).trim().length) {
        const d = JSON.parse(String(raw))
        if (Array.isArray(d.desktopWidgets)) {
          Config.desktopWidgets = d.desktopWidgets.map(w => normalizeDesktopWidget(w)).filter(w => w !== null)
          return
        }
      }
    } catch (e) {
    }
    if (!Array.isArray(Config.desktopWidgets))
      Config.desktopWidgets = []
  }

  function hydrateDesktopWidgetsFromFile() {
    hydrateDesktopFromRaw("")
  }

  function addDesktopWidget(type, size) {
    const t = String(type || "")
    let found = null
    for (let i = 0; i < desktopWidgetCatalog.length; i++) {
      if (desktopWidgetCatalog[i].id === t) {
        found = desktopWidgetCatalog[i]
        break
      }
    }
    if (!found)
      return null
    let list = desktopWidgetsList.slice()
    for (let i = 0; i < list.length; i++) {
      if (String(list[i].type) === t) {
        if (!list[i].enabled)
          setDesktopWidgetEnabled(list[i].id, true)
        if (size)
          setDesktopWidgetSize(list[i].id, size)
        return list[i]
      }
    }
    const pos = nextDesktopWidgetPos(list)
    const w = normalizeDesktopWidget({
      id: desktopWidgetIdNew(),
      type: t,
      enabled: true,
      showControls: true,
      showWhenIdle: t === "media",
      size: size || found.defaultSize || "md",
      x: pos.x,
      y: pos.y
    })
    list.push(w)
    Config.desktopWidgets = list
    Config.flushSettings()
    return w
  }

  function removeDesktopWidget(id) {
    const sid = String(id || "")
    Config.desktopWidgets = desktopWidgetsList.filter(w => String(w.id) !== sid)
    Config.flushSettings()
  }

  function setDesktopWidgetEnabled(id, on) {
    patchDesktopWidget(id, {
      enabled: !!on
    })
  }

  function patchDesktopWidget(id, patch) {
    const sid = String(id || "")
    const p = patch || {}
    Config.desktopWidgets = desktopWidgetsList.map(w => {
      if (String(w.id) !== sid)
        return w
      return normalizeDesktopWidget(Object.assign({}, w, p, {
        id: w.id,
        type: w.type
      }))
    }).filter(w => w !== null)
    Config.flushSettings()
  }

  function moveDesktopWidget(id, x, y) {
    patchDesktopWidget(id, {
      x: clamp01(x, 0.5),
      y: clamp01(y, 0.2)
    })
  }

  function setDesktopWidgetSize(id, size) {
    const s = String(size || "md")
    if (s !== "sm" && s !== "md" && s !== "lg")
      return
    patchDesktopWidget(id, {
      size: s,
      span: desktopWidgetSpanForSize(s)
    })
  }

  function cycleDesktopWidgetSize(id) {
    let w = null
    const wid = String(id)
    for (let i = 0; i < desktopWidgetsList.length; i++) {
      if (String(desktopWidgetsList[i].id) === wid) {
        w = desktopWidgetsList[i]
        break
      }
    }
    if (!w)
      return
    const order = ["sm", "md", "lg"]
    const i = order.indexOf(String(w.size || "md"))
    setDesktopWidgetSize(id, order[(i + 1) % order.length])
  }

  function desktopHasWidgetType(type) {
    const t = String(type || "")
    const list = desktopWidgetsList
    for (let i = 0; i < list.length; i++) {
      if (String(list[i].type) === t)
        return true
    }
    return false
  }

}
