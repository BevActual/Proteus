import Quickshell
import QtQuick

QtObject {
  id: deskApi
  property var host

  function desktopWidgetIdNew() {
    return "dw-" + Math.random().toString(16).slice(2, 9)
  }

  function desktopWidgetSpanForSize(size) {
    return host.lockWidgetSpanForSize(size)
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
    for (let i = 0; i < host.desktopWidgetCatalog.length; i++) {
      if (host.desktopWidgetCatalog[i].id === type) {
        meta = host.desktopWidgetCatalog[i]
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
    for (let i = 0; i < host.desktopWidgetCatalog.length; i++) {
      if (host.desktopWidgetCatalog[i].id === t) {
        found = host.desktopWidgetCatalog[i]
        break
      }
    }
    if (!found)
      return null
    let list = host.desktopWidgetsList.slice()
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
    Config.desktopWidgets = host.desktopWidgetsList.filter(w => String(w.id) !== sid)
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
    Config.desktopWidgets = host.desktopWidgetsList.map(w => {
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

  function snapAllDesktopWidgetsToGrid(layout) {
    if (!layout)
      return
    const list = host.desktopWidgetsList.slice()
    const peers = []
    const out = []
    for (let i = 0; i < list.length; i++) {
      const w = list[i]
      if (!w)
        continue
      const width = layout.contentWidth(w.type, w.size || "md")
      const height = layout.contentHeight(w.type, w.size || "md")
      const raw = layout.pixelFromFreeNorm(w.x, w.y, width, height)
      const resolved = layout.resolveNoOverlap(raw.x, raw.y, width, height, w.id, peers)
      const n = layout.freeNormFromPixel(resolved.x, resolved.y, width, height)
      peers.push({
        id: String(w.id),
        x: resolved.x,
        y: resolved.y,
        width: width,
        height: height
      })
      out.push(Object.assign({}, w, {
        x: n.x,
        y: n.y
      }))
    }
    Config.desktopWidgets = out
    if (!Config.deferSettingsWrites)
      Config.flushSettings()
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
    for (let i = 0; i < host.desktopWidgetsList.length; i++) {
      if (String(host.desktopWidgetsList[i].id) === wid) {
        w = host.desktopWidgetsList[i]
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
    const list = host.desktopWidgetsList
    for (let i = 0; i < list.length; i++) {
      if (String(list[i].type) === t)
        return true
    }
    return false
  }

}
