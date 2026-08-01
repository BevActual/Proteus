import QtQuick

// Desktop widget frames — free place by default; optional center-anchored graph snap
// over the usable surface (shell insets exclude menu bar + dock).
QtObject {
  id: root

  property real surfaceWidth: 400
  property real surfaceHeight: 800
  property var widgets: []
  property bool snapToGrid: false

  // Graph-paper pitch (px). 16 keeps stacks lattice-friendly without a
  // full-surface spiral (pitch 8 × halfCols≈120 froze free-drag resolve).
  readonly property real pitch: 16
  readonly property real margin: Math.max(8, Math.min(surfaceWidth, surfaceHeight) * 0.015)
  readonly property real originX: surfaceWidth * 0.5
  readonly property real originY: surfaceHeight * 0.5

  readonly property int halfCols: Math.max(1, Math.floor((surfaceWidth * 0.5 - margin) / pitch))
  readonly property int halfRows: Math.max(1, Math.floor((surfaceHeight * 0.5 - margin) / pitch))
  readonly property int gridCols: halfCols * 2 + 1
  readonly property int gridRows: halfRows * 2 + 1
  readonly property real cellWidth: pitch
  readonly property real cellHeight: pitch
  readonly property real gutter: 0
  // Hard cap on fallback search — resolve runs on every drag move.
  readonly property int maxResolveRings: 12

  function colSpanFor(type, size) {
    // Spans are UI hints only — placement is free / pitch-snapped, not cell-tiled.
    const s = String(size || "md")
    if (s === "sm")
      return 1
    if (s === "lg")
      return 4
    return 2
  }

  function rowSpanFor(type, size) {
    const t = String(type || "")
    const s = String(size || "md")
    if (t === "clock") {
      if (s === "lg")
        return 3
      if (s === "md")
        return 2
      return 2
    }
    if (s === "lg")
      return 2
    return 1
  }

  // Frame widths match what each widget card actually draws (see the width
  // caps in widgets/*.qml) — otherwise frames carry invisible padding and
  // cards can never sit flush against each other.
  readonly property var widthCaps: ({
    weather: { sm: 140, md: 200, lg: 280 },
    battery: { sm: 140, md: 200, lg: 280 },
    system: { sm: 160, md: 220, lg: 300 },
    calendar: { sm: 150, md: 210, lg: 260 },
    notes: { sm: 170, md: 230, lg: 300 },
    worldclock: { sm: 150, md: 200, lg: 280 },
    media: { sm: 220, md: 300, lg: 360 }
  })

  function contentWidth(type, size) {
    const maxW = Math.min(surfaceWidth - margin * 2, 420)
    if (type === "clock") {
      if (size === "sm")
        return Math.min(maxW * 0.55, 240)
      if (size === "md")
        return Math.min(maxW * 0.72, 320)
      return Math.min(maxW, 400)
    }
    const caps = widthCaps[String(type || "")]
    if (caps)
      return Math.min(maxW, caps[String(size || "md")] || caps.md)
    if (size === "sm")
      return Math.min(maxW * 0.55, 220)
    if (size === "lg")
      return Math.min(maxW, 360)
    return Math.min(maxW * 0.78, 300)
  }

  // Heights track the drawn card (body + card padding) so frames don't carry
  // invisible slack below the plate — flush stacks sit card-to-card.
  // Calendar uses the 6-row worst case.
  readonly property var heightCaps: ({
    calendar: { sm: 86, md: 168, lg: 194 },
    notes: { sm: 98, md: 134, lg: 172 },
    system: { sm: 74, md: 96, lg: 126 },
    worldclock: { sm: 84, md: 88, lg: 92 },
    battery: { sm: 72, md: 84, lg: 88 },
    weather: { sm: 78, md: 110, lg: 132 },
    media: { sm: 92, md: 112, lg: 128 }
  })

  function contentHeight(type, size) {
    if (type === "clock") {
      if (size === "sm")
        return 88
      if (size === "md")
        return 120
      return 160
    }
    const caps = heightCaps[String(type || "")]
    if (caps)
      return caps[String(size || "md")] || caps.md
    if (size === "lg")
      return 120
    if (size === "sm")
      return 72
    return 96
  }

  // Keep the whole widget inside the usable surface.
  function clampPixel(px, py, width, height) {
    const minX = margin
    const minY = margin
    const maxX = Math.max(minX, surfaceWidth - width - margin)
    const maxY = Math.max(minY, surfaceHeight - height - margin)
    return {
      x: Math.max(minX, Math.min(maxX, px)),
      y: Math.max(minY, Math.min(maxY, py))
    }
  }

  // 0 = frames may touch edge-to-edge (tight packing) but never overlap.
  readonly property real overlapGap: 0
  readonly property real flushEps: 0.75

  function rectsOverlap(ax, ay, aw, ah, bx, by, bw, bh, gap) {
    const g = gap === undefined ? overlapGap : gap
    return !(ax + aw + g <= bx || bx + bw + g <= ax || ay + ah + g <= by || by + bh + g <= ay)
  }

  function otherFrames(excludeId, othersOverride) {
    if (othersOverride && othersOverride.length !== undefined)
      return othersOverride.filter(o => o && String(o.id) !== String(excludeId || ""))
    const list = widgets || []
    const out = []
    const ex = String(excludeId || "")
    for (let i = 0; i < list.length; i++) {
      const w = list[i]
      if (!w || !w.enabled)
        continue
      if (String(w.id) === ex)
        continue
      const size = w.size || "md"
      const width = contentWidth(w.type, size)
      const height = contentHeight(w.type, size)
      const p = pixelFromFreeNorm(w.x, w.y, width, height)
      out.push({
        id: String(w.id),
        x: p.x,
        y: p.y,
        width: width,
        height: height
      })
    }
    return out
  }

  function collidesAtWith(others, px, py, width, height) {
    for (let i = 0; i < others.length; i++) {
      const o = others[i]
      if (rectsOverlap(px, py, width, height, o.x, o.y, o.width, o.height, overlapGap))
        return true
    }
    return false
  }

  function collidesAt(px, py, width, height, excludeId, othersOverride) {
    return collidesAtWith(otherFrames(excludeId, othersOverride), px, py, width, height)
  }

  // True when the frame already sits flush against a neighbor (edge-to-edge).
  function isFlushAgainst(others, px, py, width, height) {
    const eps = flushEps
    for (let i = 0; i < others.length; i++) {
      const o = others[i]
      const side = Math.abs(px + width - o.x) < eps || Math.abs(o.x + o.width - px) < eps
      const stack = Math.abs(py + height - o.y) < eps || Math.abs(o.y + o.height - py) < eps
      if (!side && !stack)
        continue
      if (side && !(py + height <= o.y || o.y + o.height <= py))
        return true
      if (stack && !(px + width <= o.x || o.x + o.width <= px))
        return true
    }
    return false
  }

  // Flush seats against the given others list (caller caches once per resolve).
  function flushPackCandidatesWith(others, px, py, width, height) {
    const out = []
    const push = (x, y) => {
      out.push({
        x: x,
        y: y
      })
    }
    for (let i = 0; i < others.length; i++) {
      const o = others[i]
      push(px, o.y + o.height)
      push(px, o.y - height)
      push(o.x + o.width, py)
      push(o.x - width, py)
      push(o.x, o.y + o.height)
      push(o.x + o.width - width, o.y + o.height)
      push(o.x + (o.width - width) * 0.5, o.y + o.height)
      push(o.x, o.y - height)
      push(o.x + o.width - width, o.y - height)
      push(o.x + (o.width - width) * 0.5, o.y - height)
      push(o.x + o.width, o.y)
      push(o.x + o.width, o.y + o.height - height)
      push(o.x + o.width, o.y + (o.height - height) * 0.5)
      push(o.x - width, o.y)
      push(o.x - width, o.y + o.height - height)
      push(o.x - width, o.y + (o.height - height) * 0.5)
    }
    return out
  }

  // Min-penetration push to sit flush against overlapping neighbors (O(N)).
  function separateFromOthers(others, px, py, width, height) {
    let x = px
    let y = py
    // A few passes so a seat between two widgets can settle.
    for (let pass = 0; pass < 3; pass++) {
      let moved = false
      for (let i = 0; i < others.length; i++) {
        const o = others[i]
        if (!rectsOverlap(x, y, width, height, o.x, o.y, o.width, o.height, overlapGap))
          continue
        const pushLeft = (x + width) - o.x
        const pushRight = (o.x + o.width) - x
        const pushUp = (y + height) - o.y
        const pushDown = (o.y + o.height) - y
        let best = pushLeft
        let nx = o.x - width
        let ny = y
        if (pushRight < best) {
          best = pushRight
          nx = o.x + o.width
          ny = y
        }
        if (pushUp < best) {
          best = pushUp
          nx = x
          ny = o.y - height
        }
        if (pushDown < best) {
          nx = x
          ny = o.y + o.height
        }
        const c = clampPixel(nx, ny, width, height)
        if (Math.abs(c.x - x) > 0.01 || Math.abs(c.y - y) > 0.01) {
          x = c.x
          y = c.y
          moved = true
        }
      }
      if (!moved)
        break
    }
    return {
      x: x,
      y: y
    }
  }

  // Snap top-left to the graph so edges share a lattice (tighter stacks than
  // center-snap, which left gaps when heights weren't multiples of pitch).
  function snapPixel(px, py, width, height) {
    let ix = Math.round((px - originX) / pitch)
    let iy = Math.round((py - originY) / pitch)
    ix = Math.max(-halfCols, Math.min(halfCols, ix))
    iy = Math.max(-halfRows, Math.min(halfRows, iy))
    return clampPixel(originX + ix * pitch, originY + iy * pitch, width, height)
  }

  function snapPixelIndices(ix, iy, width, height) {
    const cx = Math.max(-halfCols, Math.min(halfCols, ix))
    const cy = Math.max(-halfRows, Math.min(halfRows, iy))
    return clampPixel(originX + cx * pitch, originY + cy * pitch, width, height)
  }

  // Place at desired pixel without overlapping others.
  // Cheap path (cached others + flush + min-penetration) first — must stay
  // O(neighbors) because this runs on every drag move.
  // othersOverride: optional [{id,x,y,width,height}, ...] instead of live Config widgets.
  function resolveNoOverlap(px, py, width, height, excludeId, othersOverride) {
    const others = otherFrames(excludeId, othersOverride)
    let desired = clampPixel(px, py, width, height)
    if (snapToGrid && !isFlushAgainst(others, desired.x, desired.y, width, height))
      desired = snapPixel(desired.x, desired.y, width, height)
    if (!collidesAtWith(others, desired.x, desired.y, width, height))
      return desired

    // 1) Flush pack — closest edge-touching seat near the drag point.
    const flush = flushPackCandidatesWith(others, desired.x, desired.y, width, height)
    let best = null
    let bestDist = Infinity
    for (let i = 0; i < flush.length; i++) {
      const cand = clampPixel(flush[i].x, flush[i].y, width, height)
      if (collidesAtWith(others, cand.x, cand.y, width, height))
        continue
      const dist = Math.abs(cand.x - desired.x) + Math.abs(cand.y - desired.y)
      if (dist < bestDist) {
        bestDist = dist
        best = cand
      }
    }
    if (best)
      return best

    // 2) Min-penetration separate (O(N)) — avoids full-surface spiral freezes.
    const sep = separateFromOthers(others, desired.x, desired.y, width, height)
    if (!collidesAtWith(others, sep.x, sep.y, width, height)) {
      if (!snapToGrid || isFlushAgainst(others, sep.x, sep.y, width, height))
        return sep
      const sn = snapPixel(sep.x, sep.y, width, height)
      if (!collidesAtWith(others, sn.x, sn.y, width, height))
        return sn
      return sep
    }

    // 3) Short capped spiral only — never scan the whole desktop.
    const maxRing = maxResolveRings
    if (snapToGrid) {
      const baseIx = Math.round((desired.x - originX) / pitch)
      const baseIy = Math.round((desired.y - originY) / pitch)
      for (let ring = 1; ring <= maxRing; ring++) {
        for (let dx = -ring; dx <= ring; dx++) {
          for (let dy = -ring; dy <= ring; dy++) {
            if (Math.max(Math.abs(dx), Math.abs(dy)) !== ring)
              continue
            const cand = snapPixelIndices(baseIx + dx, baseIy + dy, width, height)
            if (!collidesAtWith(others, cand.x, cand.y, width, height))
              return cand
          }
        }
      }
      return sep
    }

    const step = pitch
    for (let ring = 1; ring <= maxRing; ring++) {
      for (let dx = -ring; dx <= ring; dx++) {
        for (let dy = -ring; dy <= ring; dy++) {
          if (Math.max(Math.abs(dx), Math.abs(dy)) !== ring)
            continue
          const cand = clampPixel(desired.x + dx * step, desired.y + dy * step, width, height)
          if (!collidesAtWith(others, cand.x, cand.y, width, height))
            return cand
        }
      }
    }
    return sep
  }

  // Alignment: magnetize edges/centers to neighbors + surface center.
  // Slightly generous so stacks catch while dragging; flush resolve keeps them tight.
  readonly property real alignThreshold: 10

  function alignAdjust(px, py, width, height, excludeId) {
    const others = otherFrames(excludeId)
    const vLines = [originX]
    const hLines = [originY]
    for (let i = 0; i < others.length; i++) {
      const o = others[i]
      vLines.push(o.x, o.x + o.width, o.x + o.width / 2)
      hLines.push(o.y, o.y + o.height, o.y + o.height / 2)
    }
    const anchorsX = [0, width / 2, width]
    const anchorsY = [0, height / 2, height]

    let bestDx = null
    let guideX = 0
    for (let i = 0; i < vLines.length; i++) {
      for (let j = 0; j < anchorsX.length; j++) {
        const d = vLines[i] - (px + anchorsX[j])
        if (Math.abs(d) <= alignThreshold && (bestDx === null || Math.abs(d) < Math.abs(bestDx))) {
          bestDx = d
          guideX = vLines[i]
        }
      }
    }

    let bestDy = null
    let guideY = 0
    for (let i = 0; i < hLines.length; i++) {
      for (let j = 0; j < anchorsY.length; j++) {
        const d = hLines[i] - (py + anchorsY[j])
        if (Math.abs(d) <= alignThreshold && (bestDy === null || Math.abs(d) < Math.abs(bestDy))) {
          bestDy = d
          guideY = hLines[i]
        }
      }
    }

    const guides = []
    if (bestDx !== null)
      guides.push({ vertical: true, pos: guideX })
    if (bestDy !== null)
      guides.push({ vertical: false, pos: guideY })
    return {
      x: px + (bestDx !== null ? bestDx : 0),
      y: py + (bestDy !== null ? bestDy : 0),
      guides: guides
    }
  }

  function freeNormFromPixel(px, py, width, height) {
    const spanX = Math.max(1, surfaceWidth - width - 2 * margin)
    const spanY = Math.max(1, surfaceHeight - height - 2 * margin)
    return {
      x: Math.max(0, Math.min(1, (px - margin) / spanX)),
      y: Math.max(0, Math.min(1, (py - margin) / spanY))
    }
  }

  function pixelFromFreeNorm(nx, ny, width, height) {
    const spanX = Math.max(0, surfaceWidth - width - 2 * margin)
    const spanY = Math.max(0, surfaceHeight - height - 2 * margin)
    return {
      x: margin + Math.max(0, Math.min(1, Number(nx))) * spanX,
      y: margin + Math.max(0, Math.min(1, Number(ny))) * spanY
    }
  }

  function snapNorm(nx, ny, width, height) {
    const raw = pixelFromFreeNorm(nx, ny, width, height)
    const snapped = snapPixel(raw.x, raw.y, width, height)
    return freeNormFromPixel(snapped.x, snapped.y, width, height)
  }

  function normFromPixel(px, py, colSpan, rowSpan, width, height) {
    if (snapToGrid) {
      const snapped = snapPixel(px, py, width, height)
      return freeNormFromPixel(snapped.x, snapped.y, width, height)
    }
    return freeNormFromPixel(px, py, width, height)
  }

  function frameForWidget(w) {
    if (!w || !w.enabled)
      return null
    const size = w.size || "md"
    const colSpan = colSpanFor(w.type, size)
    const rowSpan = rowSpanFor(w.type, size)
    const width = contentWidth(w.type, size)
    const height = contentHeight(w.type, size)
    let x
    let y
    if (snapToGrid) {
      const snapped = snapNorm(w.x, w.y, width, height)
      const p = pixelFromFreeNorm(snapped.x, snapped.y, width, height)
      x = p.x
      y = p.y
    } else {
      const p = pixelFromFreeNorm(w.x, w.y, width, height)
      x = p.x
      y = p.y
    }
    return {
      id: String(w.id),
      type: String(w.type),
      x: x,
      y: y,
      width: width,
      height: height,
      colSpan: colSpan,
      rowSpan: rowSpan,
      widget: w
    }
  }

  readonly property var frames: {
    const list = widgets || []
    const out = []
    for (let i = 0; i < list.length; i++) {
      const f = frameForWidget(list[i])
      if (f)
        out.push(f)
    }
    return out
  }
}
