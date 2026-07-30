pragma Singleton

import Quickshell
import QtQuick

// Lock + desktop applet catalog and CRUD.
//
// Extracted from Config.qml. Instance arrays stay in Config (one FileView owns
// settings.json); this singleton is behaviour + derived lists only.
Singleton {
  id: root

  WidgetsLock { id: lockApi; host: root }
  WidgetsDesktop { id: deskApi; host: root }


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
    if (!list || !list.length)
      return false
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
    const list = lockWidgetsList
    if (!list || !list.length)
      return []
    return list.filter(w => !!w.enabled)
  }

  readonly property var lockClockWidget: {
    const list = lockWidgetsEnabledList
    if (!list || !list.length)
      return null
    for (let i = 0; i < list.length; i++) {
      if (list[i].type === "clock")
        return list[i]
    }
    return null
  }

  readonly property var lockStripWidgets: {
    const enabled = lockWidgetsEnabledList
    if (!enabled || !enabled.length)
      return []
    const list = enabled.filter(w => w.type !== "clock")
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

  // Forwarders
  function lockWidgetIdNew() { return lockApi.lockWidgetIdNew() }
  function lockWidgetSpanForSize(size) { return lockApi.lockWidgetSpanForSize(size) }
  function normalizeLockWidget(w) { return lockApi.normalizeLockWidget(w) }
  function compactLockWidgetSlots(list) { return lockApi.compactLockWidgetSlots(list) }
  function hydrateLockFromRaw(raw) { return lockApi.hydrateLockFromRaw(raw) }
  function hydrateLockWidgetsFromFile() { return lockApi.hydrateLockWidgetsFromFile() }
  function ensureLockClockWidget() { return lockApi.ensureLockClockWidget() }
  function addLockWidget(type, size) { return lockApi.addLockWidget(type, size) }
  function removeLockWidget(id) { return lockApi.removeLockWidget(id) }
  function setLockWidgetEnabled(id, on) { return lockApi.setLockWidgetEnabled(id, on) }
  function patchLockWidget(id, patch) { return lockApi.patchLockWidget(id, patch) }
  function moveLockWidget(id, x, y) { return lockApi.moveLockWidget(id, x, y) }
  function moveLockWidgetToSlot(id, slot) { return lockApi.moveLockWidgetToSlot(id, slot) }
  function setLockWidgetSize(id, size) { return lockApi.setLockWidgetSize(id, size) }
  function cycleLockWidgetSize(id) { return lockApi.cycleLockWidgetSize(id) }
  function lockHasWidgetType(type) { return lockApi.lockHasWidgetType(type) }
  function desktopWidgetIdNew() { return deskApi.desktopWidgetIdNew() }
  function desktopWidgetSpanForSize(size) { return deskApi.desktopWidgetSpanForSize(size) }
  function clamp01(v, fallback) { return deskApi.clamp01(v, fallback) }
  function nextDesktopWidgetPos(list) { return deskApi.nextDesktopWidgetPos(list) }
  function normalizeDesktopWidget(w) { return deskApi.normalizeDesktopWidget(w) }
  function hydrateDesktopFromRaw(raw) { return deskApi.hydrateDesktopFromRaw(raw) }
  function hydrateDesktopWidgetsFromFile() { return deskApi.hydrateDesktopWidgetsFromFile() }
  function addDesktopWidget(type, size) { return deskApi.addDesktopWidget(type, size) }
  function removeDesktopWidget(id) { return deskApi.removeDesktopWidget(id) }
  function setDesktopWidgetEnabled(id, on) { return deskApi.setDesktopWidgetEnabled(id, on) }
  function patchDesktopWidget(id, patch) { return deskApi.patchDesktopWidget(id, patch) }
  function moveDesktopWidget(id, x, y) { return deskApi.moveDesktopWidget(id, x, y) }
  function snapAllDesktopWidgetsToGrid(layout) { return deskApi.snapAllDesktopWidgetsToGrid(layout) }
  function setDesktopWidgetSize(id, size) { return deskApi.setDesktopWidgetSize(id, size) }
  function cycleDesktopWidgetSize(id) { return deskApi.cycleDesktopWidgetSize(id) }
  function desktopHasWidgetType(type) { return deskApi.desktopHasWidgetType(type) }
}
