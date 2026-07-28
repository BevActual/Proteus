import QtQuick
import ".."

// Centered vertical tile stack: clock (chrome) then strip widgets, top → bottom.
QtObject {
  id: root

  property real surfaceWidth: 400
  property real surfaceHeight: 800
  property var stripWidgets: []
  property var clockWidget: null

  readonly property real margin: Math.max(16, surfaceWidth * 0.05)
  readonly property real gap: 12
  // Keep lower band free for unlock UI
  readonly property real stackTop: Math.max(28, surfaceHeight * 0.08)
  readonly property real stackBottom: surfaceHeight * 0.62
  readonly property real maxTileW: Math.min(surfaceWidth - margin * 2, Math.min(420, surfaceWidth * 0.88))

  function tileWidth(size) {
    if (size === "sm")
      return Math.min(maxTileW * 0.62, 260)
    if (size === "lg")
      return maxTileW
    return Math.min(maxTileW * 0.82, 340)
  }

  function tileHeight(type, size) {
    if (type === "clock") {
      if (size === "sm")
        return Math.min(90, surfaceHeight * 0.12)
      if (size === "md")
        return Math.min(120, surfaceHeight * 0.15)
      return Math.min(160, surfaceHeight * 0.2)
    }
    if (size === "lg")
      return Math.min(120, surfaceHeight * 0.14)
    if (size === "sm")
      return Math.min(72, surfaceHeight * 0.09)
    return Math.min(96, surfaceHeight * 0.11)
  }

  readonly property var clockFrame: {
    const w = clockWidget
    if (!w)
      return null
    const width = tileWidth(w.size || "lg")
    const height = tileHeight("clock", w.size || "lg")
    return {
      id: String(w.id),
      type: "clock",
      slot: -1,
      x: (surfaceWidth - width) / 2,
      y: stackTop,
      width: width,
      height: height,
      widget: w
    }
  }

  readonly property var stripFrames: {
    const widgets = stripWidgets || []
    const frames = []
    let y = stackTop
    if (clockFrame)
      y = clockFrame.y + clockFrame.height + gap

    for (let i = 0; i < widgets.length; i++) {
      const w = widgets[i]
      const width = tileWidth(w.size || "md")
      const height = tileHeight(w.type, w.size || "md")
      // Stop before auth band
      if (y + height > stackBottom && i > 0)
        break
      frames.push({
        id: String(w.id),
        type: String(w.type),
        slot: i,
        x: (surfaceWidth - width) / 2,
        y: y,
        width: width,
        height: height,
        widget: w
      })
      y += height + gap
    }
    return frames
  }

  // Alias used by empty-state hint
  readonly property real stripTop: {
    if (clockFrame)
      return clockFrame.y + clockFrame.height + gap
    return stackTop
  }
}
