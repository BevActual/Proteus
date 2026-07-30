import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../shared"
import "../kit"

ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: 12

  // Identify flash lives here (not shell.qml) so Appearance cold-start skips Hyprland layers.
  Loader {
    active: true
    asynchronous: false
    source: Qt.resolvedUrl("../IdentifyFlash.qml")
  }

  // Visibility is owned by Settings.qml — do not gate on SettingsNav here
  property bool active: false
  property var monitors: []
  property string status: "Loading displays…"
  property string applyStatus: ""
  property bool showAllModes: false

  property int pendingIndex: -1
  property string pendingDetail: ""
  readonly property bool confirming: pendingIndex >= 0

  // Snapshot to restore after Apply (10s window). Store as JSON text — QML var arrays are flaky.
  // Full-set snapshot (revertJson) is SoT; revertRule kept for log/status only.
  property string revertJson: ""
  property string revertRule: ""
  property int revertIndex: -1
  property string revertName: ""
  property int revertSeconds: 0
  readonly property bool canRevert: revertName.length > 0 && revertSeconds > 0 && revertJson.length > 0
  // Fingerprint of the post-Apply live topology — drift (sleep/hotplug) cancels Revert.
  property string postApplyFingerprint: ""
  property bool layoutDirty: false
  property int layoutSelected: 0

  readonly property var scaleChoices: [1, 1.25, 1.5, 1.666667, 2]
  readonly property var transformChoices: [
    {
      value: 0,
      label: "Normal"
    },
    {
      value: 1,
      label: "90°"
    },
    {
      value: 2,
      label: "180°"
    },
    {
      value: 3,
      label: "270°"
    }
  ]
  readonly property var preferredSizes: [
    "3840x2160", "2560x1440", "2560x1080", "1920x1200", "1920x1080",
    "1680x1050", "1600x900", "1440x900", "1366x768", "1280x800",
    "1280x720", "1024x768"
  ]

  function specFingerprint(specs) {
    if (!specs || !specs.length)
      return ""
    const parts = []
    for (let i = 0; i < specs.length; i++) {
      const s = specs[i] || {}
      parts.push(String(s.name || "") + ":" + Math.round(s.x || 0) + "," + Math.round(s.y || 0)
          + "," + Math.round(s.width || 0) + "x" + Math.round(s.height || 0)
          + "@" + (Math.round((s.scale || 1) * 1000) / 1000)
          + "t" + Math.round(s.transform || 0))
    }
    parts.sort()
    return parts.join("|")
  }

  function fingerprintFromMonitors(list) {
    if (!list || !list.length)
      return ""
    const specs = []
    for (let i = 0; i < list.length; i++)
      specs.push(liveSpec(list[i]))
    return specFingerprint(specs)
  }

  function indexOfMonitorName(list, name) {
    if (!list || !name)
      return -1
    for (let i = 0; i < list.length; i++) {
      if (list[i] && list[i].name === name)
        return i
    }
    return -1
  }

  function adoptMonitorList(parsed) {
    const prev = root.monitors.slice()
    const prevSelName = (root.layoutSelected >= 0 && root.layoutSelected < prev.length)
        ? String(prev[root.layoutSelected].name || "")
        : ""
    const next = []
    for (let i = 0; i < parsed.length; i++) {
      let row = root.enrichMonitor(parsed[i])
      const oi = root.indexOfMonitorName(prev, row.name)
      if (oi >= 0 && prev[oi].dirty) {
        const old = prev[oi]
        row = Object.assign({}, row, {
          dirty: true,
          x: old.x,
          y: old.y,
          modeIndex: old.modeIndex,
          scaleIndex: old.scaleIndex,
          transformIndex: old.transformIndex
        })
        const modes = root.modesFor(row)
        if (row.modeIndex >= modes.length)
          row.modeIndex = Math.max(0, modes.length - 1)
        if (row.scaleIndex >= (row.scaleChoices || []).length)
          row.scaleIndex = Math.max(0, (row.scaleChoices || []).length - 1)
        if (row.transformIndex >= root.transformChoices.length)
          row.transformIndex = 0
      }
      next.push(row)
    }

    root.monitors = next

    let sel = root.indexOfMonitorName(next, prevSelName)
    if (sel < 0)
      sel = next.length ? 0 : 0
    root.layoutSelected = sel

    // Pending large-jump confirm is index-based — drop on topology change.
    if (root.pendingIndex >= 0)
      root.clearPending()

    if (root.revertName.length) {
      const ri = root.indexOfMonitorName(next, root.revertName)
      if (ri < 0 || !root.revertJson.length) {
        root.cancelRevert("That display is gone — Revert cancelled.")
      } else {
        root.revertIndex = ri
      }
    }

    let anyDirty = false
    for (let i = 0; i < next.length; i++) {
      if (next[i].dirty) {
        anyDirty = true
        break
      }
    }
    root.layoutDirty = anyDirty

    if (prev.length > 0 && prev.length !== next.length && root.active) {
      const msg = next.length > prev.length
          ? ("Display added — now " + next.length)
          : ("Display removed — now " + next.length)
      if (!root.applyStatus.length || root.applyStatus.indexOf("Revert") < 0)
        root.applyStatus = msg
    }

    root.status = next.length ? "" : "No displays reported — is Hyprland running?"
    if (next.length)
      Displays.ensureMonitorsConfStub(next.map(m => root.liveSpec(m)))
  }

  function cancelRevert(reason) {
    const had = root.canRevert
    root.clearRevert()
    if (had && reason && reason.length)
      root.applyStatus = reason
  }

  function refresh(opts) {
    // Re-read live monitors — any pending Revert snapshot is no longer trustworthy.
    const keepStatus = !!(opts && opts.keepStatus)
    const cancelMsg = root.canRevert ? "Refreshed — Revert cancelled." : ""
    root.clearRevert()
    status = "Loading displays…"
    if (!keepStatus)
      applyStatus = cancelMsg
    pendingIndex = -1
    pendingDetail = ""
    monProc.running = false
    monProc.running = true
  }

  function clearPending() {
    pendingIndex = -1
    pendingDetail = ""
  }

  function modeKey(w, h, hz) {
    return Math.round(w) + "x" + Math.round(h) + "@" + Math.round(hz)
  }

  function sizeKey(w, h) {
    return Math.round(w) + "x" + Math.round(h)
  }

  function parseMode(s) {
    const m = String(s).match(/^(\d+)x(\d+)@([\d.]+)Hz?$/i)
    if (!m)
      return null
    return {
      width: parseInt(m[1], 10),
      height: parseInt(m[2], 10),
      refreshRate: parseFloat(m[3])
    }
  }

  function formatMode(p) {
    const hz = Math.round(p.refreshRate * 100) / 100
    return p.width + "x" + p.height + "@" + hz + "Hz"
  }

  function dedupeModes(modeStrings) {
    const best = {}
    for (let i = 0; i < modeStrings.length; i++) {
      const p = parseMode(modeStrings[i])
      if (!p)
        continue
      const sk = sizeKey(p.width, p.height)
      if (!best[sk] || p.refreshRate > best[sk].refreshRate)
        best[sk] = p
    }
    const out = []
    for (const k in best)
      out.push(formatMode(best[k]))
    out.sort((a, b) => {
      const pa = parseMode(a)
      const pb = parseMode(b)
      const aa = pa.width * pa.height
      const ba = pb.width * pb.height
      if (ba !== aa)
        return ba - aa
      return pb.refreshRate - pa.refreshRate
    })
    return out
  }

  function isRecommendedMode(p, curW, curH) {
    if (!p)
      return false
    const sk = sizeKey(p.width, p.height)
    if (sk === sizeKey(curW, curH))
      return true
    if (root.preferredSizes.indexOf(sk) >= 0)
      return true
    // Reasonable desktop band (cuts VirGL oddities like 3048×1651 / 5K)
    if (p.width >= 1280 && p.width <= 2560 && p.height >= 720 && p.height <= 1600)
      return true
    if (p.width === 3840 && p.height === 2160)
      return true
    return false
  }

  function buildModeLists(rawModes, curW, curH, curHz) {
    let all = Array.isArray(rawModes) ? rawModes.slice() : []
    const curKey = modeKey(curW, curH, curHz)
    let hasCur = all.some(s => {
      const p = parseMode(s)
      return p && modeKey(p.width, p.height, p.refreshRate) === curKey
    })
    if (!hasCur)
      all.unshift(formatMode({
        width: curW,
        height: curH,
        refreshRate: curHz || 60
      }))

    all = dedupeModes(all)
    const recommended = all.filter(s => {
      const p = parseMode(s)
      return isRecommendedMode(p, curW, curH)
    })
    // Cap recommended; always keep current first if present
    let rec = recommended.slice(0, 12)
    const curStr = all.find(s => {
      const p = parseMode(s)
      return p && modeKey(p.width, p.height, p.refreshRate) === curKey
    })
    if (curStr && rec.indexOf(curStr) < 0)
      rec = [curStr].concat(rec).slice(0, 12)

    return {
      all: all,
      recommended: rec.length ? rec : all.slice(0, 12)
    }
  }

  function modesFor(m) {
    if (!m)
      return []
    return root.showAllModes ? (m.allModes || []) : (m.recommendedModes || [])
  }

  function modeIndexInList(list, w, h, hz) {
    const key = modeKey(w, h, hz)
    for (let i = 0; i < list.length; i++) {
      const p = parseMode(list[i])
      if (p && modeKey(p.width, p.height, p.refreshRate) === key)
        return i
    }
    return 0
  }

  function enrichMonitor(raw) {
    const lists = buildModeLists(raw.availableModes, raw.width, raw.height, raw.refreshRate)
    const visible = root.showAllModes ? lists.all : lists.recommended
    const modeIdx = modeIndexInList(visible, raw.width, raw.height, raw.refreshRate)

    let scale = Number(raw.scale)
    if (!isFinite(scale) || scale <= 0)
      scale = 1
    scale = Math.round(scale * 100) / 100
    const scales = root.scaleChoices.slice()
    let scaleIdx = -1
    for (let i = 0; i < scales.length; i++) {
      if (Math.abs(scales[i] - scale) < 0.001) {
        scaleIdx = i
        break
      }
    }
    if (scaleIdx < 0) {
      scales.push(scale)
      scales.sort((a, b) => a - b)
      for (let i = 0; i < scales.length; i++) {
        if (Math.abs(scales[i] - scale) < 0.001) {
          scaleIdx = i
          break
        }
      }
    }

    let transform = Math.round(Number(raw.transform))
    if (!isFinite(transform) || transform < 0)
      transform = 0
    transform = transform % 4
    let transformIdx = 0
    for (let i = 0; i < root.transformChoices.length; i++) {
      if (root.transformChoices[i].value === transform) {
        transformIdx = i
        break
      }
    }

    return {
      name: raw.name || raw.id || "?",
      width: raw.width,
      height: raw.height,
      refreshRate: raw.refreshRate,
      scale: scale,
      transform: transform,
      transformIndex: Math.max(0, transformIdx),
      x: raw.x || 0,
      y: raw.y || 0,
      focused: !!raw.focused,
      make: raw.make,
      model: raw.model,
      description: raw.description,
      allModes: lists.all,
      recommendedModes: lists.recommended,
      modeIndex: Math.max(0, modeIdx),
      scaleChoices: scales,
      scaleIndex: Math.max(0, scaleIdx),
      dirty: false
    }
  }

  function reindexModesAfterToggle() {
    const copy = []
    for (let i = 0; i < root.monitors.length; i++) {
      const m = Object.assign({}, root.monitors[i])
      const list = modesFor(m)
      const draft = draftSpec(m)
      m.modeIndex = modeIndexInList(list, draft.width, draft.height, draft.refreshRate)
      copy.push(m)
    }
    root.monitors = copy
  }

  function draftSpec(m) {
    const list = modesFor(m)
    const modeStr = list[m.modeIndex] || ""
    const parsed = parseMode(modeStr) || {
      width: m.width,
      height: m.height,
      refreshRate: m.refreshRate
    }
    const scale = Displays.snapScale(m.scaleChoices[m.scaleIndex])
    const transform = root.transformChoices[m.transformIndex]
        ? root.transformChoices[m.transformIndex].value
        : (m.transform || 0)
    return {
      name: m.name,
      width: parsed.width,
      height: parsed.height,
      refreshRate: parsed.refreshRate,
      x: m.x,
      y: m.y,
      scale: scale,
      transform: transform,
      focused: m.focused
    }
  }

  function liveSpec(m) {
    return {
      name: m.name,
      width: m.width,
      height: m.height,
      refreshRate: m.refreshRate,
      x: m.x,
      y: m.y,
      scale: m.scale,
      transform: m.transform || 0,
      focused: m.focused
    }
  }

  function isLargeJump(from, to) {
    if (!from || !to)
      return false
    const oldA = (from.width || 0) * (from.height || 0)
    const newA = (to.width || 0) * (to.height || 0)
    if (oldA <= 0 || newA <= 0)
      return false
    const ratio = newA / oldA
    if (ratio > 1.4 || ratio < 0.65)
      return true
    if (Math.abs((from.scale || 1) - (to.scale || 1)) >= 0.5)
      return true
    if ((from.transform || 0) !== (to.transform || 0))
      return true
    return false
  }

  function requestApply(index) {
    if (index < 0 || index >= root.monitors.length)
      return
    const m = root.monitors[index]
    const from = liveSpec(m)
    const to = draftSpec(m)
    if (isLargeJump(from, to)) {
      pendingIndex = index
      pendingDetail = from.width + "×" + from.height + " @" + Math.round(from.scale * 100) / 100
          + " → " + to.width + "×" + to.height + " @" + Math.round(to.scale * 100) / 100
          + ((from.transform || 0) !== (to.transform || 0)
              ? (" · orient " + (from.transform || 0) + "→" + (to.transform || 0))
              : "")
          + ". Large jump — confirm to Apply. Revert stays available for 10 seconds."
      return
    }
    applyOne(index)
  }

  function applyOne(index) {
    if (index < 0 || index >= root.monitors.length)
      return
    clearPending()

    const previousAll = []
    for (let i = 0; i < root.monitors.length; i++)
      previousAll.push(liveSpec(root.monitors[i]))

    const all = []
    for (let i = 0; i < root.monitors.length; i++)
      all.push(i === index ? draftSpec(root.monitors[i]) : liveSpec(root.monitors[i]))

    const prev = previousAll[index]
    const next = all[index]
    root.revertJson = JSON.stringify(previousAll)
    root.revertRule = Displays.monitorRule(prev)
    root.revertIndex = index
    root.revertName = String(prev.name || next.name || "")
    root.revertSeconds = 10
    root.postApplyFingerprint = root.specFingerprint(all)
    revertTick.restart()

    // Apply every monitor rule so x/y + siblings stay consistent (VM Revert fix).
    const rules = all.map(s => Displays.monitorRule(s))
    root.applyStatus = "Applying " + (next.name || "display") + "…"
    runMonitorRules(rules, all, "apply")
  }

  function applyLayout() {
    if (!root.monitors.length)
      return
    clearPending()
    const previousAll = []
    const all = []
    for (let i = 0; i < root.monitors.length; i++) {
      previousAll.push(liveSpec(root.monitors[i]))
      all.push(draftSpec(root.monitors[i]))
    }
    root.revertJson = JSON.stringify(previousAll)
    root.revertRule = Displays.monitorRule(previousAll[0] || {})
    root.revertIndex = 0
    root.revertName = String((previousAll[0] && previousAll[0].name) || (all[0] && all[0].name) || "")
    root.revertSeconds = 10
    root.postApplyFingerprint = root.specFingerprint(all)
    revertTick.restart()
    const rules = all.map(s => Displays.monitorRule(s))
    root.applyStatus = "Applying layout…"
    runMonitorRules(rules, all, "apply")
  }

  function applySpecsToUi(all) {
    if (!all || !all.length || !root.monitors.length)
      return
    const copy = root.monitors.slice()
    for (let i = 0; i < copy.length && i < all.length; i++) {
      const spec = all[i]
      const row = Object.assign({}, copy[i], {
        dirty: false,
        width: spec.width,
        height: spec.height,
        refreshRate: spec.refreshRate,
        scale: spec.scale,
        transform: spec.transform || 0,
        x: spec.x,
        y: spec.y
      })
      row.modeIndex = modeIndexInList(modesFor(row), spec.width, spec.height, spec.refreshRate)
      let si = 0
      for (let s = 0; s < row.scaleChoices.length; s++) {
        if (Math.abs(row.scaleChoices[s] - spec.scale) < 0.001)
          si = s
      }
      row.scaleIndex = si
      let ti = 0
      for (let t = 0; t < root.transformChoices.length; t++) {
        if (root.transformChoices[t].value === (spec.transform || 0))
          ti = t
      }
      row.transformIndex = ti
      copy[i] = row
    }
    root.monitors = copy
  }

  property string pendingHyprAction: "" // apply | revert
  property var pendingPersist: []

  function runMonitorRules(rules, persistList, action) {
    pendingHyprAction = action || ""
    pendingPersist = persistList || []
    const list = rules || []
    if (!list.length) {
      root.applyStatus = "Nothing to apply."
      return
    }
    const act = String(action || "set").replace(/'/g, "")
    let script = "mkdir -p \"$HOME/.cache\"; ec=0; "
    for (let i = 0; i < list.length; i++) {
      const safe = String(list[i]).replace(/'/g, "'\\''")
      script += "echo \"$(date -Iseconds) " + act + " => " + safe + "\" >> \"$HOME/.cache/proteus-displays.log\"; "
      script += "out=$(hyprctl keyword monitor '" + safe + "' 2>&1); ec=$?; "
      script += "echo \"out:$out\" >> \"$HOME/.cache/proteus-displays.log\"; "
      script += "echo \"exit:$ec\" >> \"$HOME/.cache/proteus-displays.log\"; "
      script += "if [ \"$ec\" -ne 0 ]; then echo \"$out\" >&2; exit $ec; fi; "
    }
    script += "exit 0"
    hyprMonProc.command = ["bash", "-lc", script]
    hyprMonProc.running = false
    hyprMonProc.running = true
  }

  function revertLast() {
    const snap = root.revertJson
    if (!root.revertName.length || !snap.length) {
      root.applyStatus = "Nothing to revert."
      return
    }
    // Rebind index by connector name — hotplug must not target a shifted row.
    const ri = root.indexOfMonitorName(root.monitors, root.revertName)
    if (ri < 0) {
      root.cancelRevert("That display is gone — Revert cancelled.")
      return
    }
    root.revertIndex = ri
    let all = []
    try {
      all = JSON.parse(snap)
    } catch (e) {
      all = []
    }
    if (!all.length) {
      root.applyStatus = "Revert snapshot empty — Refresh, then Apply again."
      return
    }
    // Drop snapshot rows for connectors that vanished; keep known names.
    const liveNames = {}
    for (let i = 0; i < root.monitors.length; i++)
      liveNames[root.monitors[i].name] = true
    const filtered = []
    for (let i = 0; i < all.length; i++) {
      if (all[i] && all[i].name && liveNames[all[i].name])
        filtered.push(all[i])
    }
    // Also restore any live connectors missing from snapshot using current liveSpec.
    for (let i = 0; i < root.monitors.length; i++) {
      const n = root.monitors[i].name
      let found = false
      for (let j = 0; j < filtered.length; j++) {
        if (filtered[j].name === n) {
          found = true
          break
        }
      }
      if (!found)
        filtered.push(root.liveSpec(root.monitors[i]))
    }
    if (!filtered.length) {
      root.applyStatus = "Revert snapshot empty — Refresh, then Apply again."
      return
    }
    const rules = []
    for (let i = 0; i < filtered.length; i++)
      rules.push(Displays.monitorRule(filtered[i]))
    root.applyStatus = "Reverting " + filtered.length + " display(s)…"
    revertTick.stop()
    // UI updates only after hyprctl succeeds (VM reliability).
    runMonitorRules(rules, filtered, "revert")
  }

  function layoutBounds() {
    let minX = 0, minY = 0, maxX = 1, maxY = 1
    if (!root.monitors.length)
      return { minX: 0, minY: 0, maxX: 1920, maxY: 1080 }
    minX = Infinity
    minY = Infinity
    maxX = -Infinity
    maxY = -Infinity
    for (let i = 0; i < root.monitors.length; i++) {
      const s = draftSpec(root.monitors[i])
      minX = Math.min(minX, s.x)
      minY = Math.min(minY, s.y)
      maxX = Math.max(maxX, s.x + s.width)
      maxY = Math.max(maxY, s.y + s.height)
    }
    if (!isFinite(minX))
      return { minX: 0, minY: 0, maxX: 1920, maxY: 1080 }
    return { minX: minX, minY: minY, maxX: maxX, maxY: maxY }
  }

  function snapLayout(index, nx, ny) {
    const thresh = 24
    let x = Math.round(nx)
    let y = Math.round(ny)
    for (let i = 0; i < root.monitors.length; i++) {
      if (i === index)
        continue
      const o = draftSpec(root.monitors[i])
      const self = draftSpec(root.monitors[index])
      // Snap left/right edges
      if (Math.abs(x - o.x) < thresh)
        x = o.x
      if (Math.abs(x - (o.x + o.width)) < thresh)
        x = o.x + o.width
      if (Math.abs((x + self.width) - o.x) < thresh)
        x = o.x - self.width
      if (Math.abs((x + self.width) - (o.x + o.width)) < thresh)
        x = o.x + o.width - self.width
      // Snap top/bottom
      if (Math.abs(y - o.y) < thresh)
        y = o.y
      if (Math.abs(y - (o.y + o.height)) < thresh)
        y = o.y + o.height
      if (Math.abs((y + self.height) - o.y) < thresh)
        y = o.y - self.height
      if (Math.abs((y + self.height) - (o.y + o.height)) < thresh)
        y = o.y + o.height - self.height
    }
    return { x: x, y: y }
  }

  function setMonitorPos(index, x, y) {
    if (index < 0 || index >= root.monitors.length)
      return
    const snapped = snapLayout(index, x, y)
    const copy = root.monitors.slice()
    const row = Object.assign({}, copy[index])
    row.x = snapped.x
    row.y = snapped.y
    row.dirty = true
    copy[index] = row
    root.monitors = copy
    root.layoutDirty = true
    root.layoutSelected = index
  }

  function clearRevert() {
    revertJson = ""
    revertRule = ""
    revertIndex = -1
    revertName = ""
    revertSeconds = 0
    postApplyFingerprint = ""
    revertTick.stop()
    driftWatch.stop()
  }

  function clearLayoutDirty() {
    layoutDirty = false
  }

  Timer {
    id: refreshTimer
    interval: 450
    repeat: false
    onTriggered: {
      monProc.running = false
      monProc.running = true
    }
  }

  Process {
    id: hyprMonProc
    command: ["true"]
    stdout: StdioCollector {
      onStreamFinished: {
        // unused — hyprctl keyword is quiet on success
      }
    }
    stderr: StdioCollector {
      onStreamFinished: {
        if (text && text.trim().length)
          root.applyStatus = (root.pendingHyprAction || "monitor") + " err: " + text.trim().split("\n")[0]
      }
    }
    onExited: (exitCode, exitStatus) => {
      const action = root.pendingHyprAction
      const persist = root.pendingPersist
      root.pendingHyprAction = ""
      root.pendingPersist = []
      if (exitCode === 0) {
        if (persist && persist.length) {
          Displays.persistMonitorsConf(persist)
          root.applySpecsToUi(persist)
          root.clearLayoutDirty()
        }
        if (action === "apply") {
          root.applyStatus = "Applied — Revert available for " + root.revertSeconds + "s"
          if (root.canRevert)
            driftWatch.restart()
        } else if (action === "revert") {
          root.applyStatus = "Reverted."
          root.clearRevert()
          refreshTimer.restart()
        } else {
          root.applyStatus = "Display updated."
        }
        return
      }
      root.applyStatus = "Apply failed — check ~/.cache/proteus-displays.log"
      if (action === "apply") {
        // Keep revert window so the user can still try Revert / Refresh.
        root.revertSeconds = Math.max(root.revertSeconds, 8)
        revertTick.restart()
        if (root.canRevert)
          driftWatch.restart()
      } else if (action === "revert" && root.revertJson.length) {
        root.revertSeconds = Math.max(root.revertSeconds, 8)
        revertTick.restart()
        if (root.canRevert)
          driftWatch.restart()
      }
    }
  }

  Timer {
    id: revertTick
    interval: 1000
    repeat: true
    onTriggered: {
      if (root.revertSeconds <= 1) {
        root.clearRevert()
        if (root.applyStatus.indexOf("Revert") >= 0)
          root.applyStatus = "Apply settled — Revert window closed."
        return
      }
      root.revertSeconds = root.revertSeconds - 1
      if (root.revertName.length) {
        const ri = root.indexOfMonitorName(root.monitors, root.revertName)
        const label = ri >= 0 ? root.monitors[ri].name : root.revertName
        root.applyStatus = "Applied " + label + " — " + root.revertSeconds + "s to Revert"
      }
    }
  }

  // While Revert is armed, watch for sleep/resume or external topology drift.
  Timer {
    id: driftWatch
    interval: 2000
    repeat: true
    running: false
    onTriggered: {
      if (!root.canRevert || !root.active) {
        stop()
        return
      }
      if (!driftProc.running)
        driftProc.running = true
    }
  }

  Process {
    id: driftProc
    command: ["hyprctl", "monitors", "-j"]
    stdout: StdioCollector {
      onStreamFinished: {
        if (!root.canRevert || !root.postApplyFingerprint.length)
          return
        try {
          const parsed = JSON.parse(text.trim() || "[]")
          if (!Array.isArray(parsed))
            return
          const live = parsed.map(m => root.enrichMonitor(m))
          const fp = root.fingerprintFromMonitors(live)
          if (fp !== root.postApplyFingerprint) {
            root.cancelRevert("Displays changed — Revert cancelled.")
            root.refresh({ keepStatus: true })
          }
        } catch (e) {
          // Ignore transient parse errors during sleep/resume.
        }
      }
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!root.active)
        return
      const n = event && event.name ? String(event.name) : ""
      if (n === "monitoradded" || n === "monitorremoved"
          || n === "monitoraddedv2" || n === "monitorremovedv2"
          || n === "configreloaded") {
        if (root.canRevert)
          root.cancelRevert("Displays changed — Revert cancelled.")
        root.refresh({ keepStatus: root.applyStatus.indexOf("Revert cancelled") >= 0 })
      }
    }
  }

  // —— View ——————————————————————————————————————————————————————————————
  // Presentation only; every spec/apply/revert decision above is unchanged.

  Text {
    Layout.fillWidth: true
    Layout.maximumWidth: 480
    text: "Drag the layout canvas, then set scale and mode per display. Apply writes Hyprland + proteus-monitors.conf. After Apply you get 10 seconds to Revert."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 12
    wrapMode: Text.WordWrap
  }

  PackagesConfirm {
    open: root.confirming
    title: "Apply large display change?"
    detail: root.pendingDetail
    footnote: "Revert stays available for 10 seconds if the result looks wrong."
    Layout.maximumWidth: 520
    onCancelled: root.clearPending()
    onConfirmed: {
      const i = root.pendingIndex
      root.clearPending()
      root.applyOne(i)
    }
  }

  Text {
    Layout.fillWidth: true
    Layout.maximumWidth: 480
    text: root.status
    color: Theme.textDim
    font.family: Theme.fontFamily
    font.pixelSize: 12
    wrapMode: Text.WordWrap
    visible: root.monitors.length === 0 && !root.confirming
  }

  SettingsGroup {
    visible: root.monitors.length > 0 && !root.confirming
    title: "Layout"

    Item {
      id: canvasHost
      Layout.fillWidth: true
      Layout.preferredHeight: 200
      Layout.maximumWidth: 520

      readonly property var bounds: root.layoutBounds()
      readonly property real worldW: Math.max(1, bounds.maxX - bounds.minX)
      readonly property real worldH: Math.max(1, bounds.maxY - bounds.minY)
      readonly property real pad: 12
      readonly property real scale: Math.min(
            (width - pad * 2) / worldW,
            (height - pad * 2) / worldH)

      Rectangle {
        anchors.fill: parent
        radius: Theme.radiusSm
        color: Theme.bgElevated
        border.width: 1
        border.color: Theme.border
      }

      Repeater {
        model: root.monitors

        Rectangle {
          id: monRect
          required property var modelData
          required property int index

          readonly property var spec: root.draftSpec(monRect.modelData)
          x: canvasHost.pad + (spec.x - canvasHost.bounds.minX) * canvasHost.scale
          y: canvasHost.pad + (spec.y - canvasHost.bounds.minY) * canvasHost.scale
          width: Math.max(36, spec.width * canvasHost.scale)
          height: Math.max(24, spec.height * canvasHost.scale)
          radius: 4
          color: monRect.index === root.layoutSelected ? Theme.accentSoft : Theme.bg
          border.width: monRect.index === root.layoutSelected ? 2 : 1
          border.color: monRect.index === root.layoutSelected ? Theme.accent : Theme.border

          Text {
            anchors.centerIn: parent
            width: parent.width - 8
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: monRect.modelData.name + (monRect.modelData.focused ? " ·" : "")
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: 11
          }

          MouseArea {
            id: dragArea
            anchors.fill: parent
            cursorShape: Qt.SizeAllCursor
            property real grabDX: 0
            property real grabDY: 0
            property bool didDrag: false
            onPressed: mouse => {
              root.layoutSelected = monRect.index
              grabDX = mouse.x
              grabDY = mouse.y
              didDrag = false
            }
            onPositionChanged: mouse => {
              if (!pressed)
                return
              const p = mapToItem(canvasHost, mouse.x, mouse.y)
              const nx = p.x - grabDX
              const ny = p.y - grabDY
              if (Math.abs(nx - monRect.x) > 2 || Math.abs(ny - monRect.y) > 2)
                didDrag = true
              monRect.x = nx
              monRect.y = ny
            }
            onReleased: {
              if (!didDrag)
                return
              const b = canvasHost.bounds
              const sc = Math.max(0.0001, canvasHost.scale)
              const wx = b.minX + (monRect.x - canvasHost.pad) / sc
              const wy = b.minY + (monRect.y - canvasHost.pad) / sc
              root.setMonitorPos(monRect.index, wx, wy)
            }
            onClicked: {
              if (didDrag)
                return
              root.layoutSelected = monRect.index
              Displays.identifyMonitor(monRect.modelData.name)
            }
          }
        }
      }
    }

    SettingsFormRow {
      label: "Apply layout"
      hint: root.layoutDirty ? "Write pending positions to Hyprland" : "Canvas matches live layout"
      showSeparator: true
      interactive: root.layoutDirty || root.monitors.length > 1
      labelColor: root.layoutDirty ? Theme.accent : Theme.textMute
      onActivated: root.applyLayout()
      Text {
        text: root.layoutDirty ? "›" : ""
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
      }
    }

    SettingsFormRow {
      visible: root.canRevert
      label: "Revert"
      hint: "Undo last Apply — " + root.revertSeconds + "s left"
      showSeparator: false
      interactive: true
      labelColor: Theme.danger
      onActivated: root.revertLast()
      Text {
        text: root.revertSeconds + "s"
        color: Theme.danger
        font.family: Theme.fontFamily
        font.pixelSize: 12
      }
    }
  }

  SettingsGroup {
    visible: root.monitors.length > 0 && !root.confirming
    title: "Modes"

    SettingsFormRow {
      label: "Show all modes"
      hint: root.showAllModes
          ? ((root.monitors[0] && root.monitors[0].allModes ? root.monitors[0].allModes.length : "?") + " reported by the display")
          : "Recommended only — hides odd virtual modes"
      showSeparator: false
      Switch {
        checked: root.showAllModes
        onToggled: {
          root.showAllModes = checked
          root.reindexModesAfterToggle()
        }
      }
    }
  }

  Repeater {
    model: root.monitors

    SettingsGroup {
      id: monGroup
      required property var modelData
      required property int index
      visible: !root.confirming
      title: monGroup.modelData.name + (monGroup.modelData.focused ? " · active" : "")

      readonly property bool revertable: root.canRevert && monGroup.modelData.name === root.revertName

      SettingsFormRow {
        visible: !!(monGroup.modelData.description || monGroup.modelData.make)
        label: "Display"
        hint: [monGroup.modelData.make, monGroup.modelData.model, monGroup.modelData.description]
            .filter(s => s && String(s).length).join(" · ")
        showSeparator: true
      }

      SettingsFormRow {
        label: "Resolution"
        showSeparator: true
        ComboBox {
          Layout.preferredWidth: 180
          model: root.modesFor(monGroup.modelData)
          currentIndex: monGroup.modelData.modeIndex
          onActivated: idx => {
            const copy = root.monitors.slice()
            const row = Object.assign({}, copy[monGroup.index])
            row.modeIndex = idx
            row.dirty = true
            copy[monGroup.index] = row
            root.monitors = copy
          }
        }
      }

      SettingsFormRow {
        label: "Scale"
        showSeparator: true
        ComboBox {
          Layout.preferredWidth: 120
          model: monGroup.modelData.scaleChoices.map(s => Number(s).toFixed(2))
          currentIndex: monGroup.modelData.scaleIndex
          onActivated: idx => {
            const copy = root.monitors.slice()
            const row = Object.assign({}, copy[monGroup.index])
            row.scaleIndex = idx
            row.dirty = true
            copy[monGroup.index] = row
            root.monitors = copy
          }
        }
      }

      SettingsFormRow {
        label: "Orientation"
        showSeparator: true
        ComboBox {
          Layout.preferredWidth: 120
          model: root.transformChoices.map(t => t.label)
          currentIndex: monGroup.modelData.transformIndex
          onActivated: idx => {
            const copy = root.monitors.slice()
            const row = Object.assign({}, copy[monGroup.index])
            row.transformIndex = idx
            row.transform = root.transformChoices[idx].value
            row.dirty = true
            copy[monGroup.index] = row
            root.monitors = copy
          }
        }
      }

      SettingsFormRow {
        label: "Identify"
        hint: "Flash this display and focus it"
        showSeparator: true
        interactive: true
        onActivated: Displays.identifyMonitor(monGroup.modelData.name)
        Text {
          text: "Flash"
          color: Theme.accent
          font.family: Theme.fontFamily
          font.pixelSize: 12
        }
      }

      // `dirty` was tracked but never surfaced — Apply now reflects it.
      SettingsFormRow {
        label: "Apply"
        hint: monGroup.modelData.dirty
            ? "Write mode / scale / orientation for this display"
            : "No pending changes"
        showSeparator: monGroup.revertable
        interactive: monGroup.modelData.dirty
        labelColor: monGroup.modelData.dirty ? Theme.accent : Theme.textMute
        onActivated: root.requestApply(monGroup.index)
        Text {
          text: monGroup.modelData.dirty ? "›" : ""
          color: Theme.textMute
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSize
        }
      }

      SettingsFormRow {
        visible: monGroup.revertable
        label: "Revert"
        hint: "Undo last Apply — " + root.revertSeconds + "s left"
        showSeparator: false
        interactive: true
        labelColor: Theme.danger
        onActivated: root.revertLast()
        Text {
          text: root.revertSeconds + "s"
          color: Theme.danger
          font.family: Theme.fontFamily
          font.pixelSize: 12
        }
      }
    }
  }

  Text {
    Layout.fillWidth: true
    Layout.maximumWidth: 480
    visible: root.applyStatus.length > 0 && !root.confirming
    text: root.applyStatus
    color: Theme.textDim
    font.family: Theme.fontFamily
    font.pixelSize: 12
    wrapMode: Text.WordWrap
  }

  SettingsGroup {
    visible: !root.confirming

    SettingsFormRow {
      label: "Refresh"
      hint: "Re-read live monitors (cancels an open Revert)"
      showSeparator: true
      interactive: true
      onActivated: root.refresh()
      Text {
        text: "›"
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
      }
    }

    SettingsFormRow {
      label: "Edit monitors conf…"
      hint: "Escape hatch · ~/.config/hypr/proteus-monitors.conf"
      showSeparator: false
      interactive: true
      onActivated: Displays.openMonitorsConfInEditor()
      Text {
        text: "›"
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
      }
    }
  }

  Text {
    Layout.fillWidth: true
    Layout.maximumWidth: 480
    text: "Fact: hyprctl monitors -j · Apply persists live monitor= lines to proteus-monitors.conf."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 11
    wrapMode: Text.WordWrap
  }

  Process {
    id: monProc
    command: ["hyprctl", "monitors", "-j"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const parsed = JSON.parse(text.trim() || "[]")
          if (!Array.isArray(parsed)) {
            root.monitors = []
            root.status = "Unexpected hyprctl output."
            root.clearPending()
            if (root.revertName.length)
              root.cancelRevert("Could not read displays — Revert cancelled.")
            return
          }
          root.adoptMonitorList(parsed)
        } catch (e) {
          root.monitors = []
          root.status = "Could not read monitors (is Hyprland running?)."
          root.clearPending()
          if (root.revertName.length)
            root.cancelRevert("Could not read displays — Revert cancelled.")
        }
      }
    }
    stderr: StdioCollector {
      onStreamFinished: {
        if (text.trim().length && root.monitors.length === 0)
          root.status = "hyprctl: " + text.trim().split("\n")[0]
      }
    }
  }

  Connections {
    target: root
    function onActiveChanged() {
      if (root.active) {
        // Re-entry (and post-sleep navigate-back) must not keep a stale Revert.
        root.refresh()
      } else {
        root.clearPending()
        root.clearRevert()
      }
    }
  }

  Component.onCompleted: {
    if (root.active)
      root.refresh()
  }
}
