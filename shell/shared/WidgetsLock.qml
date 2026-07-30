import Quickshell
import QtQuick

QtObject {
  id: lockApi
  property var host

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
    for (let i = 0; i < host.lockWidgetCatalog.length; i++) {
      if (host.lockWidgetCatalog[i].id === type) {
        meta = host.lockWidgetCatalog[i]
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
      if (!list[i])
        continue
      if (list[i].type === "clock")
        clocks.push(list[i])
      else
        strip.push(list[i])
    }
    strip.sort((a, b) => (a.slot - b.slot) || String(a.id).localeCompare(String(b.id)))
    const stripOut = []
    for (let i = 0; i < strip.length; i++) {
      const n = normalizeLockWidget(Object.assign({}, strip[i], {
        slot: i,
        span: lockWidgetSpanForSize(strip[i].size)
      }))
      if (n)
        stripOut.push(n)
    }
    return clocks.concat(stripOut)
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
    const rawList = host.lockWidgetsList
    const list = (rawList && rawList.length !== undefined) ? rawList.slice() : []
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
    for (let i = 0; i < host.lockWidgetCatalog.length; i++) {
      if (host.lockWidgetCatalog[i].id === t) {
        found = host.lockWidgetCatalog[i]
        break
      }
    }
    if (!found)
      return null
    let list = host.lockWidgetsList.slice()
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
    for (let i = 0; i < host.lockWidgetsList.length; i++) {
      if (String(host.lockWidgetsList[i].id) === sid) {
        target = host.lockWidgetsList[i]
        break
      }
    }
    if (target && target.type === "clock")
      return
    const next = host.lockWidgetsList.filter(w => String(w.id) !== sid)
    Config.lockWidgets = compactLockWidgetSlots(next)
    Config.lockShowClock = host.lockHasClockWidget
    Config.flushSettings()
  }

  function setLockWidgetEnabled(id, on) {
    patchLockWidget(id, {
      enabled: !!on
    })
    const list = host.lockWidgetsList
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
    let list = host.lockWidgetsList.map(w => {
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
    const strip = host.lockStripWidgets
    const slot = Math.max(0, Math.min(strip.length, Math.round(ny * Math.max(1, strip.length))))
    moveLockWidgetToSlot(id, slot)
  }

  function moveLockWidgetToSlot(id, slot) {
    const sid = String(id || "")
    let list = host.lockWidgetsList.slice()
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
    for (let i = 0; i < host.lockWidgetsList.length; i++) {
      if (String(host.lockWidgetsList[i].id) === wid) {
        w = host.lockWidgetsList[i]
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
    const list = host.lockWidgetsList
    for (let i = 0; i < list.length; i++) {
      if (String(list[i].type) === t)
        return true
    }
    return false
  }

}
