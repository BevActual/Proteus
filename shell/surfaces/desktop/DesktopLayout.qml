import QtQuick

// Free-place frames from normalized x/y (0..1 → top-left within remaining room).
QtObject {
  id: root

  property real surfaceWidth: 400
  property real surfaceHeight: 800
  property var widgets: []

  readonly property real margin: Math.max(12, Math.min(surfaceWidth, surfaceHeight) * 0.02)

  function tileWidth(type, size) {
    const maxW = Math.min(surfaceWidth - margin * 2, 420)
    if (type === "clock") {
      if (size === "sm")
        return Math.min(maxW * 0.55, 240)
      if (size === "md")
        return Math.min(maxW * 0.72, 320)
      return Math.min(maxW, 400)
    }
    if (size === "sm")
      return Math.min(maxW * 0.55, 220)
    if (size === "lg")
      return Math.min(maxW, 360)
    return Math.min(maxW * 0.78, 300)
  }

  function tileHeight(type, size) {
    if (type === "clock") {
      if (size === "sm")
        return 88
      if (size === "md")
        return 120
      return 160
    }
    if (size === "lg")
      return 120
    if (size === "sm")
      return 72
    return 96
  }

  readonly property var frames: {
    const list = widgets || []
    const out = []
    for (let i = 0; i < list.length; i++) {
      const w = list[i]
      if (!w || !w.enabled)
        continue
      const width = tileWidth(w.type, w.size || "md")
      const height = tileHeight(w.type, w.size || "md")
      const maxX = Math.max(0, surfaceWidth - width - margin)
      const maxY = Math.max(0, surfaceHeight - height - margin)
      const nx = Math.max(0, Math.min(1, Number(w.x)))
      const ny = Math.max(0, Math.min(1, Number(w.y)))
      out.push({
        id: String(w.id),
        type: String(w.type),
        x: margin + nx * maxX,
        y: margin + ny * maxY,
        width: width,
        height: height,
        widget: w
      })
    }
    return out
  }
}
