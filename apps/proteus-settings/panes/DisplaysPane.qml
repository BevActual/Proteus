import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../shared"

ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: 12

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
  property string revertJson: ""
  property string revertRule: ""
  property int revertIndex: -1
  property int revertSeconds: 0
  readonly property bool canRevert: revertIndex >= 0 && revertSeconds > 0 && revertRule.length > 0

  readonly property var scaleChoices: [1, 1.25, 1.5, 1.75, 2]
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

  function refresh() {
    status = "Loading displays…"
    applyStatus = ""
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
    const scale = m.scaleChoices[m.scaleIndex]
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
          + ". Large change — confirm, then Revert is available for 10s."
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
    root.revertSeconds = 10
    revertTick.restart()

    const nextRule = Displays.monitorRule(next)
    root.applyStatus = "Applying… " + nextRule
    runMonitorRule(nextRule, all, "apply")
    applySpecsToUi(all)
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

  function runMonitorRule(rule, persistList, action) {
    pendingHyprAction = action || ""
    pendingPersist = persistList || []
    const safe = String(rule).replace(/'/g, "'\\''")
    const act = String(action || "set").replace(/'/g, "")
    hyprMonProc.command = [
      "bash",
      "-lc",
      "mkdir -p \"$HOME/.cache\"; "
          + "echo \"$(date -Iseconds) " + act + " => " + safe + "\" >> \"$HOME/.cache/proteus-displays.log\"; "
          + "out=$(hyprctl keyword monitor '" + safe + "' 2>&1); ec=$?; "
          + "echo \"out:$out\" >> \"$HOME/.cache/proteus-displays.log\"; "
          + "echo \"exit:$ec\" >> \"$HOME/.cache/proteus-displays.log\"; "
          + "if [ \"$ec\" -ne 0 ]; then echo \"$out\" >&2; fi; exit $ec"
    ]
    hyprMonProc.running = false
    hyprMonProc.running = true
  }

  function revertLast() {
    const rule = root.revertRule
    const snap = root.revertJson
    if (!(root.revertIndex >= 0) || !rule.length) {
      root.applyStatus = "Nothing to revert."
      return
    }
    let all = []
    try {
      all = JSON.parse(snap)
    } catch (e) {
      all = []
    }
    root.applyStatus = "Reverting… " + rule
    revertTick.stop()
    runMonitorRule(rule, all, "revert")
    if (all.length)
      applySpecsToUi(all)
  }

  function clearRevert() {
    revertJson = ""
    revertRule = ""
    revertIndex = -1
    revertSeconds = 0
    revertTick.stop()
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
        if (persist && persist.length)
          Displays.persistMonitorsConf(persist)
        if (action === "apply") {
          root.applyStatus = "Applied — press Revert within " + root.revertSeconds + "s"
        } else if (action === "revert") {
          root.applyStatus = "Reverted OK"
          root.clearRevert()
          refreshTimer.restart()
        } else {
          root.applyStatus = "Monitor updated"
        }
        return
      }
      root.applyStatus = "hyprctl failed (exit " + exitCode + ") — see ~/.cache/proteus-displays.log"
      if (action === "apply")
        root.clearRevert()
      else if (action === "revert" && root.revertRule.length) {
        root.revertSeconds = Math.max(root.revertSeconds, 8)
        revertTick.restart()
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
          root.applyStatus = "Apply settled."
        return
      }
      root.revertSeconds = root.revertSeconds - 1
      if (root.revertIndex >= 0 && root.revertIndex < root.monitors.length)
        root.applyStatus = "Applied " + root.monitors[root.revertIndex].name
            + " — Revert available for " + root.revertSeconds + "s"
    }
  }

  // —— View ——————————————————————————————————————————————————————————————
  // Presentation only; every spec/apply/revert decision above is unchanged.

  Text {
    Layout.fillWidth: true
    Layout.maximumWidth: 480
    text: "Scale, resolution, and orientation. Large jumps ask for confirm; Revert is offered for 10s."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 12
    wrapMode: Text.WordWrap
  }

  PackagesConfirm {
    open: root.confirming
    title: "Apply large display change?"
    detail: root.pendingDetail
    footnote: "You can Revert for 10 seconds after Apply."
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

      readonly property bool revertable: root.canRevert && root.revertIndex === monGroup.index

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
            ? "Pending changes on this display"
            : "No changes to apply"
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
        hint: "Restore the previous mode — " + root.revertSeconds + "s left"
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
      hint: "Re-read hyprctl monitors"
      showSeparator: true
      interactive: true
      onActivated: {
        root.clearRevert()
        root.refresh()
      }
      Text {
        text: "›"
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
      }
    }

    SettingsFormRow {
      label: "Edit monitors conf…"
      hint: "~/.config/hypr/proteus-monitors.conf"
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
    text: "Fact: hyprctl monitors · Apply: hyprctl keyword monitor … + ~/.config/hypr/proteus-monitors.conf"
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
            return
          }
          root.monitors = parsed.map(m => root.enrichMonitor(m))
          root.status = root.monitors.length ? "" : "No monitors reported."
          Displays.ensureMonitorsConfStub(root.monitors.map(m => root.liveSpec(m)))
        } catch (e) {
          root.monitors = []
          root.status = "Could not read monitors (is Hyprland running?)."
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
      if (root.active)
        root.refresh()
      else {
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
