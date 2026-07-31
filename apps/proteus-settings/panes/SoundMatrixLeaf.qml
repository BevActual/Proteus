import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../shared"
import "../kit"
import ".." // root module — SettingsNav singleton

// Sound → Mixer — Wave Link–style grid; channels are folders of system apps.
ColumnLayout {
  id: root
  property Item host
  width: parent ? parent.width : implicitWidth
  Layout.fillWidth: true
  // Fill the Settings content area so the outer ScrollView has nothing left to scroll.
  Layout.fillHeight: true
  Layout.preferredHeight: root.mixerViewportH
  Layout.minimumHeight: 320
  spacing: Theme.spaceSm

  readonly property int mixerViewportH: {
    const win = root.Window.window
    const h = (win && win.height) ? win.height : 800
    return Math.max(320, h - 160)
  }

  property bool didAutoSetup: false
  property string expandedIds: ""
  property string pickerChannelId: ""
  property string pickerFilter: ""
  property bool addChannelOpen: false
  property string addChannelName: ""
  property bool addInputOpen: false
  property string addInputFilter: ""
  property bool addMixOpen: false
  property string addMixName: ""
  property bool addMixHear: false
  property bool addRowMenuOpen: false
  property string renameKind: ""
  property string renameId: ""
  property string renameDraft: ""
  property string pendingRemoveKind: ""
  property string pendingRemoveId: ""
  property string pendingRemoveLabel: ""

  readonly property bool removeConfirmOpen: root.pendingRemoveId.length > 0

  function requestRemoveChannel(channelId, label) {
    if (!channelId || Audio.mixBusy)
      return
    if (String(channelId) === "proteus_mix_system")
      return
    root.pendingRemoveKind = "channel"
    root.pendingRemoveId = String(channelId)
    root.pendingRemoveLabel = String(label || channelId)
  }

  function requestRemoveInput(inputId, label) {
    if (!inputId || Audio.mixBusy)
      return
    root.pendingRemoveKind = "input"
    root.pendingRemoveId = String(inputId)
    root.pendingRemoveLabel = String(label || inputId)
  }

  function requestRemoveMix(mixId, label) {
    if (!mixId || Audio.mixBusy)
      return
    root.pendingRemoveKind = "mix"
    root.pendingRemoveId = String(mixId)
    root.pendingRemoveLabel = String(label || mixId)
  }

  function cancelRemove() {
    root.pendingRemoveKind = ""
    root.pendingRemoveId = ""
    root.pendingRemoveLabel = ""
  }

  function confirmRemove() {
    const kind = root.pendingRemoveKind
    const id = root.pendingRemoveId
    root.cancelRemove()
    if (!id.length)
      return
    if (kind === "mix")
      root.removeMix(id)
    else if (kind === "input")
      root.removeInput(id)
    else if (kind === "channel")
      root.removeChannel(id)
  }

  function isRenaming(kind, id) {
    return root.renameKind === kind && root.renameId === id
  }

  function beginRename(kind, id, label) {
    root.renameKind = kind
    root.renameId = String(id || "")
    root.renameDraft = String(label || "")
  }

  function cancelRename() {
    root.renameKind = ""
    root.renameId = ""
    root.renameDraft = ""
  }

  function commitRename() {
    const name = String(root.renameDraft || "").trim()
    const id = root.renameId
    const kind = root.renameKind
    root.cancelRename()
    if (!name || !id || Audio.mixBusy)
      return
    if (kind === "mix")
      Audio.renameMixBus(id, name)
    else if (kind === "input")
      Audio.renameMixInput(id, name)
    else
      Audio.renameMixChannel(id, name)
  }

  function closeAddForms() {
    root.addChannelOpen = false
    root.addChannelName = ""
    root.addInputOpen = false
    root.addInputFilter = ""
    root.addRowMenuOpen = false
  }

  function openAddChannel() {
    root.addRowMenuOpen = false
    root.addInputOpen = false
    root.addInputFilter = ""
    root.addChannelOpen = true
    root.addChannelName = ""
  }

  function openAddInput() {
    root.addRowMenuOpen = false
    root.addChannelOpen = false
    root.addChannelName = ""
    root.addInputOpen = true
    root.addInputFilter = ""
    Audio.refreshMix()
  }

  readonly property int channelIdentityW: 158
  readonly property int masterStripW: 128
  readonly property int mixColW: 128
  readonly property int rowH: 44
  readonly property int headerH: 32
  // Room between cells so drop lines read clearly while dragging.
  readonly property int gutter: 10
  readonly property int folderRowH: 32
  readonly property int ctrlBtn: 22
  readonly property int iconSz: 22
  readonly property int routeIcon: iconSz
  readonly property int listenChipW: 118
  readonly property int dropLine: 4
  readonly property int dropCap: 8
  property string dragKind: ""
  property string dragId: ""
  property string dragOverId: ""
  // true = drop line before overId; false = after (needed for rightward/downward moves).
  property bool dragPlaceBefore: true
  property var dragSnapshot: []
  readonly property bool isDragging: root.dragId.length > 0

  function isDragSource(kind, id) {
    return root.dragKind === kind && root.dragId === String(id || "")
  }

  function isDragHot(kind, id) {
    return root.dragKind === kind
        && root.dragOverId === String(id || "")
        && root.dragId !== String(id || "")
  }

  function canDragRow(ch) {
    if (!ch || !ch.id)
      return false
    if (root.isInput(ch))
      return true
    return String(ch.id) !== "proteus_mix_system"
  }

  function _idsOf(list) {
    const out = []
    for (let i = 0; i < (list || []).length; i++) {
      if (list[i] && list[i].id)
        out.push(list[i].id)
    }
    return out
  }

  // placeBefore: insert immediately before overId; false → immediately after.
  // Always-before breaks rightward/downward drags (first over second never moves).
  function _moveIdTo(list, fromId, overId, placeBefore) {
    const src = list || []
    const from = src.findIndex(x => x && x.id === fromId)
    const to = src.findIndex(x => x && x.id === overId)
    if (from < 0 || to < 0 || from === to)
      return src
    const next = src.slice()
    const [item] = next.splice(from, 1)
    let insertAt = next.findIndex(x => x && x.id === overId)
    if (insertAt < 0)
      return src
    if (!placeBefore)
      insertAt += 1
    next.splice(insertAt, 0, item)
    return next
  }

  function beginDrag(kind, id) {
    root.dragKind = kind
    root.dragId = id
    root.dragOverId = id
    root.dragPlaceBefore = true
    Audio.mixDragging = true
    mixFlick.interactive = false
    if (kind === "mix")
      root.dragSnapshot = (Audio.mixMixes || []).slice()
    else if (kind === "channel")
      root.dragSnapshot = (Audio.mixChannels || []).filter(c => c && c.id !== "proteus_mix_system")
    else if (kind === "input") {
      const inn = Audio.mixInputs || []
      // Prefer live inputs; fall back to mixRows if dump lag left mixInputs empty.
      if (inn.length)
        root.dragSnapshot = inn.slice()
      else
        root.dragSnapshot = (root.mixRows || []).filter(c => root.isInput(c))
    } else
      root.dragSnapshot = []
  }

  function setDragOver(kind, id, placeBefore) {
    if (!root.dragId.length || root.dragKind !== kind || !id || id === root.dragId)
      return
    if (kind === "channel" && id === "proteus_mix_system")
      return
    const before = placeBefore !== false
    if (root.dragOverId === id && root.dragPlaceBefore === before)
      return
    root.dragOverId = id
    root.dragPlaceBefore = before
    // Snapshot tracks intended order; UI model stays stable so the pressed grip isn't destroyed.
    root.dragSnapshot = root._moveIdTo(root.dragSnapshot, root.dragId, id, before)
  }

  function cancelDrag() {
    root.dragKind = ""
    root.dragId = ""
    root.dragOverId = ""
    root.dragPlaceBefore = true
    root.dragSnapshot = []
    Audio.mixDragging = false
    mixFlick.interactive = true
  }

  function endDrag() {
    const kind = root.dragKind
    const from = root.dragId
    const snap = root.dragSnapshot.slice()
    root.dragKind = ""
    root.dragId = ""
    root.dragOverId = ""
    root.dragPlaceBefore = true
    root.dragSnapshot = []
    Audio.mixDragging = false
    mixFlick.interactive = true
    if (!kind || !from || !snap.length || Audio.mixBusy)
      return
    const order = root._idsOf(snap)
    const idx = order.indexOf(from)
    if (idx < 0)
      return
    if (kind === "mix") {
      const before = root._idsOf(Audio.mixMixes || [])
      if (before.join("\n") === order.join("\n"))
        return
      Audio.applyMixOrder("mix", order)
      Audio.moveMixBus(from, idx)
      return
    }
    if (kind === "channel") {
      const before = root._idsOf((Audio.mixChannels || []).filter(c => c && c.id !== "proteus_mix_system"))
      if (before.join("\n") === order.join("\n"))
        return
      Audio.applyMixOrder("channel", ["proteus_mix_system"].concat(order))
      Audio.moveMixChannel(from, idx)
      return
    }
    if (kind === "input") {
      const before = root._idsOf(Audio.mixInputs || [])
      if (before.join("\n") === order.join("\n"))
        return
      Audio.applyMixOrder("input", order)
      Audio.moveMixInput(from, idx)
    }
  }

  function trackDragAt(globalX, globalY) {
    if (!root.dragKind.length)
      return
    if (root.dragKind === "mix") {
      const p = listenRow.mapFromGlobal(globalX, globalY)
      root.dragOverMixAt(p.x)
      return
    }
    root.dragOverRowAt(globalX, globalY)
  }

  function dragOverMixAt(xInListenRow) {
    const mixes = root.mixColumns || []
    let cx = root.channelIdentityW + root.gutter + root.masterStripW + root.gutter
    for (let i = 0; i < mixes.length; i++) {
      const left = cx - root.gutter / 2
      const right = cx + root.mixColW + root.gutter / 2
      if (xInListenRow >= left && xInListenRow < right) {
        const mid = cx + root.mixColW / 2
        root.setDragOver("mix", mixes[i].id, xInListenRow < mid)
        return
      }
      cx += root.mixColW + root.gutter
    }
  }

  readonly property int labelPrimary: 13
  readonly property int labelSecondary: 11
  readonly property int labelHeader: 12
  readonly property int labelGlyph: 11
  readonly property int gridW: {
    const mixes = root.mixColumns || []
    return root.channelIdentityW
        + root.gutter + root.masterStripW
        + mixes.length * (root.gutter + root.mixColW)
        + root.gutter + root.headerH
  }

  readonly property var peakDeviceList: {
    const rows = root.mixRows || []
    const out = []
    for (let i = 0; i < rows.length; i++) {
      const id = rows[i] && rows[i].id
      if (id && rows[i].present !== false)
        out.push(id)
    }
    return out
  }

  readonly property var mixColumns: {
    const m = Audio.mixMixes || []
    if (m.length)
      return m
    return Audio.mixMixCatalog
  }

  readonly property var mixRows: {
    const channels = Audio.mixChannels || []
    const inn = Audio.mixInputs || []
    if (!channels.length && !inn.length)
      return Audio.mixChannelCatalog
    return channels.concat(inn)
  }

  readonly property bool mixChannelsReady: {
    // Catalog placeholders have no `present` — don't treat them as live sinks.
    const channels = Audio.mixChannels || []
    if (!channels.length)
      return false
    for (let i = 0; i < channels.length; i++) {
      if (channels[i].present === false)
        return false
    }
    return true
  }

  readonly property var inputCandidates: {
    if (!root.addInputOpen)
      return []
    const q = String(root.addInputFilter || "").trim().toLowerCase()
    const srcs = Audio.mixAvailableSources || []
    const out = []
    for (let i = 0; i < srcs.length; i++) {
      const s = srcs[i]
      if (!s || !s.id)
        continue
      if (q.length) {
        const hay = (String(s.label || "") + " " + String(s.id || "")).toLowerCase()
        if (hay.indexOf(q) < 0)
          continue
      }
      out.push(s)
      if (out.length >= 40)
        break
    }
    return out
  }

  readonly property var assignedLookup: {
    const map = Object.create(null)
    const ch = Audio.mixChannels || []
    for (let i = 0; i < ch.length; i++) {
      const apps = ch[i].apps || []
      for (let j = 0; j < apps.length; j++) {
        const a = apps[j]
        if (!a)
          continue
        if (a.key)
          map[String(a.key).toLowerCase()] = ch[i].id
        if (a.desktopId)
          map[String(a.desktopId).toLowerCase()] = ch[i].id
        if (a.name)
          map[String(a.name).toLowerCase()] = ch[i].id
      }
    }
    return map
  }

  readonly property var pickerCandidates: {
    if (!root.pickerChannelId.length)
      return []
    const q = String(root.pickerFilter || "").trim().toLowerCase()
    const apps = DesktopEntries.applications.values
    const out = []
    const seen = Object.create(null)
    for (let i = 0; i < apps.length; i++) {
      const a = apps[i]
      if (!a || !a.name)
        continue
      const id = String(a.id || "").replace(/\.desktop$/i, "")
      if (!id.length || seen[id])
        continue
      // Skip hidden / non-app entries when the API exposes the flag
      if (a.noDisplay === true)
        continue
      seen[id] = true
      const name = String(a.name)
      const key = name.toLowerCase()
      const already = root.assignedLookup[key] || root.assignedLookup[id.toLowerCase()]
      if (already === root.pickerChannelId)
        continue
      if (q.length) {
        const hay = (name + " " + String(a.genericName || "") + " " + id).toLowerCase()
        if (hay.indexOf(q) < 0)
          continue
      }
      out.push({
        id: id,
        name: name,
        key: key,
        icon: EnvGate.resolveAppIcon(a),
        elsewhere: already && already.length ? already : ""
      })
    }
    out.sort((x, y) => String(x.name).localeCompare(String(y.name)))
    return out.slice(0, q.length ? 100 : 60)
  }

  function isExpanded(id) {
    if (!id)
      return false
    return ("," + root.expandedIds + ",").indexOf("," + id + ",") >= 0
  }

  function setExpanded(id, on) {
    if (!id)
      return
    const parts = root.expandedIds.length ? root.expandedIds.split(",") : []
    const next = []
    for (let i = 0; i < parts.length; i++) {
      if (parts[i] && parts[i] !== id)
        next.push(parts[i])
    }
    if (on)
      next.push(id)
    root.expandedIds = next.join(",")
  }

  function toggleExpanded(id) {
    root.setExpanded(id, !root.isExpanded(id))
  }

  function openPicker(channelId) {
    root.setExpanded(channelId, true)
    root.pickerChannelId = channelId
    root.pickerFilter = ""
  }

  function closePicker() {
    root.pickerChannelId = ""
    root.pickerFilter = ""
  }

  function cellFor(ch, mixId) {
    const cells = (ch && ch.cells) ? ch.cells : null
    if (cells && cells[mixId])
      return cells[mixId]
    return { on: false, volume: 100, muted: false }
  }

  function isInput(ch) {
    if (!ch)
      return false
    if (ch.kind === "input")
      return true
    // Fallback — optimistic rows / older dumps may omit kind.
    return String(ch.id || "").startsWith("proteus_in_")
  }

  function dragOverRowAt(globalX, globalY) {
    if (!channelRepeater || !root.dragKind.length)
      return
    for (let i = 0; i < channelRepeater.count; i++) {
      const item = channelRepeater.itemAt(i)
      if (!item)
        continue
      // Prefer the controls strip (exposed by the delegate) so expanded folders
      // don't steal hit-tests from rows below.
      const host = item.controlsHost || item
      const local = host.mapFromGlobal(globalX, globalY)
      const rowH = host === item ? root.rowH : Math.max(1, host.height)
      if (local.y < -root.gutter / 2 || local.y > rowH + root.gutter / 2)
        continue
      if (local.x < -8 || local.x > root.gridW)
        continue
      const rows = root.mixRows || []
      const ch = rows[i]
      if (!ch || !ch.id)
        continue
      const placeBefore = local.y < rowH / 2
      if (root.dragKind === "input") {
        // Skip channels (and self) — keep scanning for another input row.
        if (!root.isInput(ch) || ch.id === root.dragId)
          continue
        root.setDragOver("input", ch.id, placeBefore)
        return
      }
      if (root.dragKind === "channel") {
        if (root.isInput(ch) || ch.id === "proteus_mix_system" || ch.id === root.dragId)
          continue
        root.setDragOver("channel", ch.id, placeBefore)
        return
      }
    }
  }

  function channelLetter(ch) {
    if (root.isInput(ch))
      return "M"
    const s = (ch && (ch.short || ch.label)) ? String(ch.short || ch.label) : "?"
    return s.charAt(0).toUpperCase()
  }

  function channelLabelForId(id) {
    const ch = Audio.mixChannels || []
    for (let i = 0; i < ch.length; i++) {
      if (ch[i].id === id)
        return ch[i].label
    }
    return "channel"
  }

  function appIcon(app) {
    if (app && app.desktopId) {
      const desk = DesktopEntries.heuristicLookup(app.desktopId)
      if (desk)
        return EnvGate.resolveAppIcon(desk)
    }
    if (app && app.name) {
      const desk = DesktopEntries.heuristicLookup(app.name)
      if (desk)
        return EnvGate.resolveAppIcon(desk)
    }
    return "application-x-executable"
  }

  function maybeAutoSetup() {
    if (root.didAutoSetup || Audio.mixBusy || root.mixChannelsReady)
      return
    root.didAutoSetup = true
    Audio.ensureMixChannels()
  }

  function pickApp(candidate) {
    if (!candidate || !root.pickerChannelId.length)
      return
    if (!root.mixChannelsReady)
      Audio.ensureMixChannels()
    Audio.assignAppToSink(
          candidate.key || candidate.name,
          root.pickerChannelId,
          "",
          candidate.name,
          candidate.id)
    root.pickerFilter = ""
  }

  function submitAddChannel() {
    const name = String(root.addChannelName || "").trim()
    if (!name || Audio.mixBusy)
      return
    Audio.addMixChannel(name)
    root.addChannelName = ""
    root.addChannelOpen = false
  }

  function removeChannel(channelId) {
    if (!channelId || Audio.mixBusy)
      return
    if (root.pickerChannelId === channelId)
      root.closePicker()
    root.setExpanded(channelId, false)
    Audio.removeMixChannel(channelId)
  }

  function removeInput(inputId) {
    if (!inputId || Audio.mixBusy)
      return
    root.setExpanded(inputId, false)
    Audio.removeMixInput(inputId)
  }

  function pickInput(src) {
    if (!src || !src.id || Audio.mixBusy)
      return
    Audio.addMixInput(src.id, src.label || "")
    root.addInputFilter = ""
    root.addInputOpen = false
  }

  function submitAddMix() {
    const name = String(root.addMixName || "").trim()
    if (!name || Audio.mixBusy)
      return
    Audio.addMixBus(name, root.addMixHear)
    root.addMixName = ""
    root.addMixHear = false
    root.addMixOpen = false
  }

  function removeMix(mixId) {
    if (!mixId || Audio.mixBusy)
      return
    Audio.removeMixBus(mixId)
  }

  function listenMix(mixId) {
    if (!mixId || Audio.mixBusy)
      return
    Audio.listenMixBus(mixId)
  }

  readonly property bool listeningSystem: {
    const m = root.mixColumns || []
    for (let i = 0; i < m.length; i++) {
      if (m[i] && m[i].hear)
        return false
    }
    return true
  }

  readonly property bool peaksWanted: !!host && host.page === "sound-matrix"
  property bool peaksSubscribed: false

  function syncMixPeaks() {
    if (root.peaksWanted) {
      if (!root.peaksSubscribed) {
        Audio.subscribeMixPeaks(root.peakDeviceList)
        root.peaksSubscribed = true
      } else {
        Audio.refreshMixPeakDevices(root.peakDeviceList)
      }
    } else if (root.peaksSubscribed) {
      Audio.unsubscribeMixPeaks()
      root.peaksSubscribed = false
    }
  }

  onPeaksWantedChanged: root.syncMixPeaks()

  Component.onCompleted: {
    Audio.refreshMix()
    Audio.refreshGraphEditor()
    root.maybeAutoSetup()
    root.syncMixPeaks()
  }

  Component.onDestruction: {
    if (root.peaksSubscribed) {
      Audio.unsubscribeMixPeaks()
      root.peaksSubscribed = false
    }
    if (Audio.mixDragging)
      Audio.mixDragging = false
  }

  Connections {
    target: Audio
    function onMixChannelsChanged() {
      root.maybeAutoSetup()
      if (root.peaksWanted)
        Audio.refreshMixPeakDevices(root.peakDeviceList)
    }
    function onMixInputsChanged() {
      if (root.peaksWanted)
        Audio.refreshMixPeakDevices(root.peakDeviceList)
    }
    function onMixMixesChanged() {
      if (root.peaksWanted)
        Audio.refreshMixPeakDevices(root.peakDeviceList)
    }
  }

  Text {
    Layout.fillWidth: true
    text: "Channels → mixes. Speakers / mix headers choose what you hear. Double-click a name to rename."
    color: Theme.textDim
    font.family: Theme.fontFamily
    font.pixelSize: 12
    wrapMode: Text.WordWrap
  }

  PackagesConfirm {
    open: root.removeConfirmOpen
    title: "Remove “" + root.pendingRemoveLabel + "”?"
    detail: {
      if (root.pendingRemoveKind === "mix")
        return "This mix and its routes go away."
      if (root.pendingRemoveKind === "input")
        return "This capture strip is removed."
      return "Apps on it return to Speakers."
    }
    footnote: ""
    confirmLabel: "Remove"
    onCancelled: root.cancelRemove()
    onConfirmed: root.confirmRemove()
  }

  MouseArea {
    visible: !root.mixChannelsReady
    Layout.fillWidth: false
    Layout.preferredWidth: root.gridW
    Layout.preferredHeight: 28
    Layout.alignment: Qt.AlignLeft
    cursorShape: Qt.PointingHandCursor
    enabled: !Audio.mixBusy
    onClicked: Audio.ensureMixChannels()
    Rectangle {
      anchors.fill: parent
      radius: Theme.radiusSm
      color: Theme.accentSoft
      border.width: 1
      border.color: Theme.accent
      Text {
        anchors.centerIn: parent
        text: Audio.mixBusy ? "Setting up…" : "Set up mixer sinks"
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: 12
        font.weight: Font.DemiBold
      }
    }
  }

  // ── Mix grid: clipped viewport + explicit content size (H/V scroll) ────────
  Item {
    id: mixViewport
    Layout.fillWidth: true
    Layout.fillHeight: true
    Layout.minimumHeight: 260
    Layout.preferredHeight: Math.max(260, root.height > 0 ? root.height - 24 : root.mixerViewportH)
    clip: true

    Flickable {
      id: mixFlick
      anchors.fill: parent
      contentWidth: root.gridW
      contentHeight: Math.max(mixBody.implicitHeight, mixBody.height)
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      flickableDirection: Flickable.HorizontalAndVerticalFlick
      interactive: contentWidth > width + 2 || contentHeight > height + 2
      // Keep scroll position stable when content shrinks
      onContentWidthChanged: contentX = Math.min(contentX, Math.max(0, contentWidth - width))
      onContentHeightChanged: contentY = Math.min(contentY, Math.max(0, contentHeight - height))

      readonly property bool needV: contentHeight > height + 2
      readonly property bool needH: contentWidth > width + 2

      ScrollBar.vertical: ScrollBar {
        id: vBar
        policy: ScrollBar.AsNeeded
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        // Leave the corner for the horizontal bar when both are needed
        anchors.bottomMargin: mixFlick.needH ? 8 : 0
        background: Item {}
        contentItem: Rectangle {
          implicitWidth: 6
          radius: 3
          color: Theme.textMute
          opacity: vBar.active || vBar.pressed ? 0.75 : 0
          Behavior on opacity {
            NumberAnimation {
              duration: 140
            }
          }
        }
      }
      ScrollBar.horizontal: ScrollBar {
        id: hBar
        policy: ScrollBar.AsNeeded
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: mixFlick.needV ? 8 : 0
        background: Item {}
        contentItem: Rectangle {
          implicitHeight: 6
          radius: 3
          color: Theme.textMute
          opacity: hBar.active || hBar.pressed ? 0.75 : 0
          Behavior on opacity {
            NumberAnimation {
              duration: 140
            }
          }
        }
      }

      WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
          const dx = event.angleDelta.x || (event.pixelDelta ? event.pixelDelta.x : 0)
          const dy = event.angleDelta.y || (event.pixelDelta ? event.pixelDelta.y : 0)
          let used = false
          if (Math.abs(dx) > Math.abs(dy) && mixFlick.contentWidth > mixFlick.width + 2) {
            mixFlick.contentX = Math.max(0, Math.min(mixFlick.contentWidth - mixFlick.width, mixFlick.contentX - dx))
            used = true
          } else if (mixFlick.contentHeight > mixFlick.height + 2) {
            mixFlick.contentY = Math.max(0, Math.min(mixFlick.contentHeight - mixFlick.height, mixFlick.contentY - dy))
            used = true
          } else if (mixFlick.contentWidth > mixFlick.width + 2 && Math.abs(dy) > 0) {
            // Shift-less vertical wheel pans horizontally when only H overflow
            mixFlick.contentX = Math.max(0, Math.min(mixFlick.contentWidth - mixFlick.width, mixFlick.contentX - dy))
            used = true
          }
          event.accepted = used
        }
      }

      ColumnLayout {
        id: mixBody
        width: root.gridW
        spacing: root.gutter

    // Listen group — Speakers sits in the Channels/Level band; mixes align with cells
    RowLayout {
      id: listenRow
      Layout.fillWidth: false
      Layout.alignment: Qt.AlignLeft
      spacing: root.gutter

      Item {
        Layout.preferredWidth: root.channelIdentityW + root.gutter + root.masterStripW
        Layout.preferredHeight: root.headerH

        Text {
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left
          anchors.leftMargin: 4
          text: "Listen"
          color: Theme.textMute
          font.family: Theme.fontFamily
          font.pixelSize: root.labelHeader
          font.weight: Font.DemiBold
        }

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          anchors.right: parent.right
          width: root.listenChipW
          height: root.headerH
          radius: Theme.radiusSm
          color: root.listeningSystem
              ? Theme.accentSoft
              : (sysListenMa.containsMouse ? Theme.bgHover : "transparent")
          border.width: root.listeningSystem ? 1 : 0
          border.color: Theme.accent

          MouseArea {
            id: sysListenMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            enabled: !Audio.mixBusy && !root.listeningSystem
            onClicked: root.listenMix("system")
          }

          // Same chrome rhythm as mix chips (grip + icon + label + trailing slot)
          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 4
            anchors.rightMargin: 4
            spacing: 2

            Item {
              Layout.preferredWidth: 12
              Layout.preferredHeight: root.headerH
            }

            Rectangle {
              Layout.preferredWidth: root.iconSz
              Layout.preferredHeight: root.iconSz
              radius: width * Theme.squircleCornerRatio
              color: root.listeningSystem ? Theme.accent : Theme.accentSoft
              Text {
                anchors.centerIn: parent
                text: root.listeningSystem ? "◎" : "◉"
                color: root.listeningSystem ? "#ffffff" : Theme.accent
                font.pixelSize: root.labelGlyph
              }
            }
            Text {
              Layout.fillWidth: true
              text: "Speakers"
              color: Theme.text
              font.family: Theme.fontFamily
              font.pixelSize: root.labelHeader
              font.weight: Font.DemiBold
              elide: Text.ElideRight
            }
            Item {
              Layout.preferredWidth: root.ctrlBtn
              Layout.preferredHeight: root.ctrlBtn
            }
          }
        }
      }

      Repeater {
        model: root.mixColumns
        Rectangle {
          id: mixHeaderChip
          required property var modelData
          Layout.preferredWidth: root.mixColW
          Layout.preferredHeight: root.headerH
          Layout.fillWidth: false
          radius: Theme.radiusSm
          clip: false
          readonly property bool dragHot: root.isDragHot("mix", modelData.id)
          readonly property bool dragSource: root.isDragSource("mix", modelData.id)
          opacity: dragSource ? 0.55 : (root.dragKind === "mix" && !dragHot && !dragSource ? 0.72 : 1)
          scale: dragSource ? 0.97 : 1
          Behavior on opacity {
            NumberAnimation {
              duration: 90
            }
          }
          color: dragHot
              ? Theme.accentSoft
              : (dragSource
                  ? Theme.accentSoft
                  : (modelData.hear
                      ? Theme.accentSoft
                      : (headerMa.containsMouse ? Theme.bgHover : "transparent")))
          border.width: dragHot || dragSource ? 2 : (modelData.hear ? 1 : 0)
          border.color: Theme.accent

          // Vertical drop line — before (left) or after (right) this mix column
          Item {
            visible: mixHeaderChip.dragHot
            anchors.verticalCenter: parent.verticalCenter
            x: root.dragPlaceBefore
                ? (-Math.ceil(root.gutter / 2) - 1)
                : (parent.width - root.dropLine + Math.ceil(root.gutter / 2) + 1)
            width: root.dropLine
            height: parent.height + root.gutter
            z: 5

            Rectangle {
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              width: root.dropLine
              radius: root.dropLine / 2
              color: Theme.accent
            }
            Rectangle {
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.top: parent.top
              anchors.topMargin: -2
              width: root.dropCap
              height: root.dropCap
              radius: root.dropCap / 2
              color: Theme.accent
            }
            Rectangle {
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.bottom: parent.bottom
              anchors.bottomMargin: -2
              width: root.dropCap
              height: root.dropCap
              radius: root.dropCap / 2
              color: Theme.accent
            }
          }

          MouseArea {
            id: headerMa
            anchors.fill: parent
            z: 0
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            enabled: !Audio.mixBusy && !root.isRenaming("mix", modelData.id) && !root.dragId.length
            onClicked: {
              if (modelData.hear)
                root.listenMix("system")
              else
                root.listenMix(modelData.id)
            }
            onDoubleClicked: {
              root.beginRename("mix", modelData.id, modelData.label)
            }
          }

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 4
            anchors.rightMargin: 4
            spacing: 2
            z: 1

            Item {
              Layout.preferredWidth: 20
              Layout.preferredHeight: root.headerH
              Text {
                anchors.centerIn: parent
                text: "⠿"
                color: root.dragId === modelData.id ? Theme.accent : Theme.textMute
                font.pixelSize: 11
              }
              MouseArea {
                id: mixDragMa
                anchors.fill: parent
                cursorShape: Qt.SizeAllCursor
                preventStealing: true
                enabled: !Audio.mixBusy
                onPressed: root.beginDrag("mix", modelData.id)
                onPositionChanged: mouse => {
                  if (!pressed || root.dragKind !== "mix")
                    return
                  const g = mapToGlobal(mouse.x, mouse.y)
                  root.trackDragAt(g.x, g.y)
                }
                onReleased: root.endDrag()
                onCanceled: root.cancelDrag()
              }
            }

            Rectangle {
              Layout.preferredWidth: root.iconSz
              Layout.preferredHeight: root.iconSz
              radius: width * Theme.squircleCornerRatio
              color: modelData.hear ? Theme.accent : Theme.accentSoft
              Text {
                anchors.centerIn: parent
                text: modelData.hear ? "◎" : "◉"
                color: modelData.hear ? "#ffffff" : Theme.accent
                font.pixelSize: root.labelGlyph
              }
            }
            Text {
              Layout.fillWidth: true
              visible: !root.isRenaming("mix", modelData.id)
              text: modelData.label
              color: Theme.text
              font.family: Theme.fontFamily
              font.pixelSize: root.labelPrimary
              font.weight: Font.DemiBold
              elide: Text.ElideRight
            }
            TextField {
              Layout.fillWidth: true
              visible: root.isRenaming("mix", modelData.id)
              focus: visible
              color: Theme.text
              font.family: Theme.fontFamily
              font.pixelSize: root.labelPrimary
              font.weight: Font.DemiBold
              background: Item {}
              text: root.renameDraft
              onTextChanged: {
                if (root.isRenaming("mix", modelData.id))
                  root.renameDraft = text
              }
              Keys.onReturnPressed: root.commitRename()
              Keys.onEnterPressed: root.commitRename()
              Keys.onEscapePressed: root.cancelRename()
              onVisibleChanged: if (visible)
                forceActiveFocus()
              onEditingFinished: {
                if (root.isRenaming("mix", modelData.id))
                  root.commitRename()
              }
            }
            MouseArea {
              Layout.preferredWidth: root.ctrlBtn
              Layout.preferredHeight: root.ctrlBtn
              cursorShape: Qt.PointingHandCursor
              enabled: !Audio.mixBusy
              onClicked: root.requestRemoveMix(modelData.id, modelData.label)
              Text {
                anchors.centerIn: parent
                text: "×"
                color: Theme.textMute
                font.pixelSize: root.labelHeader
              }
            }
          }
        }
      }

      MouseArea {
        Layout.preferredWidth: root.headerH
        Layout.preferredHeight: root.headerH
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          root.addMixOpen = !root.addMixOpen
          if (!root.addMixOpen) {
            root.addMixName = ""
            root.addMixHear = false
          }
        }
        Rectangle {
          anchors.fill: parent
          radius: Theme.radiusSm
          color: parent.containsMouse ? Theme.bgHover : "transparent"
          border.width: 1
          border.color: Theme.separator
          Text {
            anchors.centerIn: parent
            text: root.addMixOpen ? "⌃" : "+"
            color: Theme.accent
            font.pixelSize: root.labelPrimary
            font.weight: Font.DemiBold
          }
        }
      }
    }

    RowLayout {
      Layout.fillWidth: false
      Layout.alignment: Qt.AlignLeft
      spacing: root.gutter

      Item {
        Layout.preferredWidth: root.channelIdentityW
        Layout.preferredHeight: 18
        Text {
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left
          anchors.leftMargin: 4
          text: "Channels"
          color: Theme.textMute
          font.family: Theme.fontFamily
          font.pixelSize: root.labelSecondary
          font.weight: Font.DemiBold
        }
      }

      Item {
        Layout.preferredWidth: root.masterStripW
        Layout.preferredHeight: 18
        Text {
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left
          anchors.leftMargin: 4
          text: "Level"
          color: Theme.textMute
          font.family: Theme.fontFamily
          font.pixelSize: root.labelSecondary
          font.weight: Font.DemiBold
        }
      }
    }

    Rectangle {
      visible: root.addMixOpen
      Layout.preferredWidth: root.gridW
      Layout.preferredHeight: root.rowH
      Layout.alignment: Qt.AlignLeft
      radius: Theme.radiusSm
      color: Theme.bgElevated
      border.width: 1
      border.color: Theme.border

      RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 6
        spacing: 6

        TextField {
          Layout.fillWidth: true
          placeholderText: "Mix name"
          color: Theme.text
          placeholderTextColor: Theme.textMute
          font.family: Theme.fontFamily
          font.pixelSize: root.labelPrimary
          background: Item {}
          text: root.addMixName
          onTextChanged: root.addMixName = text
          Keys.onReturnPressed: root.submitAddMix()
          Keys.onEnterPressed: root.submitAddMix()
        }

        MouseArea {
          Layout.preferredWidth: 56
          Layout.preferredHeight: 24
          cursorShape: Qt.PointingHandCursor
          enabled: !Audio.mixBusy
          onClicked: root.addMixHear = !root.addMixHear
          Rectangle {
            anchors.fill: parent
            radius: Theme.radiusSm
            color: root.addMixHear ? Theme.accentSoft : "transparent"
            border.width: 1
            border.color: root.addMixHear ? Theme.accent : Theme.separator
            Text {
              anchors.centerIn: parent
              text: root.addMixHear ? "◎ Hear" : "Hear"
              color: root.addMixHear ? Theme.accent : Theme.textMute
              font.family: Theme.fontFamily
              font.pixelSize: 11
              font.weight: Font.DemiBold
            }
          }
        }

        MouseArea {
          Layout.preferredWidth: 44
          Layout.preferredHeight: 24
          cursorShape: Qt.PointingHandCursor
          enabled: !Audio.mixBusy && String(root.addMixName || "").trim().length > 0
          onClicked: root.submitAddMix()
          Rectangle {
            anchors.fill: parent
            radius: Theme.radiusSm
            color: parent.enabled ? Theme.accentSoft : "transparent"
            border.width: 1
            border.color: parent.enabled ? Theme.accent : Theme.separator
            Text {
              anchors.centerIn: parent
              text: "Add"
              color: parent.parent.enabled ? Theme.accent : Theme.textMute
              font.family: Theme.fontFamily
              font.pixelSize: 11
              font.weight: Font.DemiBold
            }
          }
        }
      }
    }

    Repeater {
      id: channelRepeater
      model: root.mixRows

      ColumnLayout {
        id: chBlock
        required property var modelData
        required property int index
        Layout.fillWidth: true
        spacing: root.gutter
        readonly property bool isInput: root.isInput(modelData)
        readonly property bool expanded: root.isExpanded(modelData.id)
        readonly property bool picking: !chBlock.isInput && root.pickerChannelId === modelData.id
        // Exposed for drag hit-testing (skip expanded folder body).
        readonly property alias controlsHost: mixControlsHost

        // Mix controls row
        Item {
          id: mixControlsHost
          Layout.fillWidth: false
          Layout.alignment: Qt.AlignLeft
          Layout.preferredWidth: root.channelIdentityW + root.gutter + root.masterStripW
              + root.mixColumns.length * (root.gutter + root.mixColW)
          Layout.preferredHeight: root.rowH
          readonly property bool rowDragHot: {
            const kind = chBlock.isInput ? "input" : "channel"
            return root.isDragHot(kind, chBlock.modelData.id)
          }
          readonly property bool rowDragSource: {
            const kind = chBlock.isInput ? "input" : "channel"
            return root.isDragSource(kind, chBlock.modelData.id)
          }
          opacity: {
            if (mixControlsHost.rowDragSource)
              return 0.55
            if (root.isDragging && (root.dragKind === "channel" || root.dragKind === "input")
                && !mixControlsHost.rowDragHot && !mixControlsHost.rowDragSource)
              return 0.72
            return 1
          }
          Behavior on opacity {
            NumberAnimation {
              duration: 90
            }
          }

          // Soft target plate behind the whole row while dropping here
          Rectangle {
            anchors.fill: parent
            anchors.margins: -3
            radius: Theme.radiusMd
            visible: mixControlsHost.rowDragHot || mixControlsHost.rowDragSource
            color: Theme.accentSoft
            border.width: mixControlsHost.rowDragSource ? 2 : 0
            border.color: Theme.accent
            opacity: mixControlsHost.rowDragHot ? 1 : 0.55
            z: 0
          }

          // Full-width drop line — before (above) or after (below) this row
          Item {
            visible: mixControlsHost.rowDragHot
            anchors.left: parent.left
            anchors.right: parent.right
            y: root.dragPlaceBefore
                ? (-Math.ceil(root.gutter / 2) - 1)
                : (parent.height - root.dropLine + Math.ceil(root.gutter / 2) + 1)
            height: root.dropLine
            z: 6

            Rectangle {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              height: root.dropLine
              radius: root.dropLine / 2
              color: Theme.accent
            }
            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              anchors.left: parent.left
              anchors.leftMargin: -2
              width: root.dropCap
              height: root.dropCap
              radius: root.dropCap / 2
              color: Theme.accent
            }
            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              anchors.right: parent.right
              anchors.rightMargin: -2
              width: root.dropCap
              height: root.dropCap
              radius: root.dropCap / 2
              color: Theme.accent
            }
          }

          RowLayout {
            anchors.fill: parent
            spacing: root.gutter
            z: 1

          // Channel identity — click toggles folder; × removes without opening
          Rectangle {
            id: identityCell
            Layout.preferredWidth: root.channelIdentityW
            Layout.preferredHeight: root.rowH
            radius: Theme.radiusSm
            clip: false
            readonly property bool dragHot: mixControlsHost.rowDragHot
            readonly property bool dragSource: mixControlsHost.rowDragSource
            color: Theme.bgElevated
            border.width: dragSource || chBlock.expanded ? 2 : 1
            border.color: (dragSource || chBlock.expanded) ? Theme.accent : Theme.border
            readonly property real peak: Audio.mixPeakFor(chBlock.modelData.id)
            readonly property string rowKind: chBlock.isInput ? "input" : "channel"
            readonly property bool draggable: root.canDragRow(chBlock.modelData)

            MouseArea {
              anchors.fill: parent
              z: 0
              cursorShape: Qt.PointingHandCursor
              enabled: !root.isRenaming(chBlock.isInput ? "input" : "channel", chBlock.modelData.id)
                  && !root.dragId.length
              onClicked: root.toggleExpanded(chBlock.modelData.id)
              onDoubleClicked: {
                root.beginRename(
                    chBlock.isInput ? "input" : "channel",
                    chBlock.modelData.id,
                    chBlock.modelData.label)
              }
            }

            RowLayout {
              anchors.fill: parent
              anchors.margins: 4
              anchors.bottomMargin: 8
              spacing: 4
              z: 1

              // Grip hit target wider than glyph for easier drag start
              Item {
                Layout.preferredWidth: 20
                Layout.preferredHeight: root.rowH - 8
                Text {
                  anchors.centerIn: parent
                  visible: identityCell.draggable
                  text: "⠿"
                  color: root.dragId === chBlock.modelData.id ? Theme.accent : Theme.textMute
                  font.pixelSize: 11
                }
                MouseArea {
                  anchors.fill: parent
                  cursorShape: identityCell.draggable ? Qt.SizeAllCursor : Qt.ArrowCursor
                  preventStealing: true
                  enabled: !Audio.mixBusy && identityCell.draggable
                  onPressed: root.beginDrag(identityCell.rowKind, chBlock.modelData.id)
                  onPositionChanged: mouse => {
                    if (!pressed || !root.dragKind.length)
                      return
                    const g = mapToGlobal(mouse.x, mouse.y)
                    root.trackDragAt(g.x, g.y)
                  }
                  onReleased: root.endDrag()
                  onCanceled: root.cancelDrag()
                }
              }

              Rectangle {
                Layout.preferredWidth: root.iconSz
                Layout.preferredHeight: root.iconSz
                radius: width * Theme.squircleCornerRatio
                color: Theme.accentSoft
                Text {
                  anchors.centerIn: parent
                  text: root.channelLetter(chBlock.modelData)
                  color: Theme.accent
                  font.family: Theme.fontFamily
                  font.pixelSize: root.labelHeader
                  font.weight: Font.DemiBold
                }
              }

              ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Text {
                  Layout.fillWidth: true
                  visible: !root.isRenaming(chBlock.isInput ? "input" : "channel", chBlock.modelData.id)
                  text: chBlock.modelData.label
                  color: Theme.text
                  font.family: Theme.fontFamily
                  font.pixelSize: root.labelPrimary
                  font.weight: Font.DemiBold
                  elide: Text.ElideRight
                }
                TextField {
                  Layout.fillWidth: true
                  visible: root.isRenaming(chBlock.isInput ? "input" : "channel", chBlock.modelData.id)
                  focus: visible
                  color: Theme.text
                  font.family: Theme.fontFamily
                  font.pixelSize: root.labelPrimary
                  font.weight: Font.DemiBold
                  background: Item {}
                  text: root.renameDraft
                  onTextChanged: {
                    if (root.isRenaming(chBlock.isInput ? "input" : "channel", chBlock.modelData.id))
                      root.renameDraft = text
                  }
                  Keys.onReturnPressed: root.commitRename()
                  Keys.onEnterPressed: root.commitRename()
                  Keys.onEscapePressed: root.cancelRename()
                  onVisibleChanged: if (visible)
                    forceActiveFocus()
                  onEditingFinished: {
                    if (root.isRenaming(chBlock.isInput ? "input" : "channel", chBlock.modelData.id))
                      root.commitRename()
                  }
                }
                Text {
                  Layout.fillWidth: true
                  visible: !root.isRenaming(chBlock.isInput ? "input" : "channel", chBlock.modelData.id)
                  text: {
                    if (chBlock.isInput)
                      return "Input"
                    const n = chBlock.modelData.count || 0
                    if (!n)
                      return "Empty"
                    return n + (n === 1 ? " app" : " apps")
                  }
                  color: Theme.textMute
                  font.family: Theme.fontFamily
                  font.pixelSize: root.labelSecondary
                  elide: Text.ElideRight
                }
              }

              Text {
                text: chBlock.expanded ? "▾" : "▸"
                color: Theme.textMute
                font.pixelSize: root.labelSecondary
              }

              MouseArea {
                Layout.preferredWidth: root.ctrlBtn
                Layout.preferredHeight: root.ctrlBtn
                z: 2
                visible: chBlock.isInput || String(chBlock.modelData.id) !== "proteus_mix_system"
                cursorShape: Qt.PointingHandCursor
                enabled: !Audio.mixBusy
                onClicked: {
                  if (chBlock.isInput)
                    root.requestRemoveInput(chBlock.modelData.id, chBlock.modelData.label)
                  else
                    root.requestRemoveChannel(chBlock.modelData.id, chBlock.modelData.label)
                }
                Text {
                  anchors.centerIn: parent
                  text: "×"
                  color: Theme.textMute
                  font.pixelSize: root.labelHeader
                }
              }
            }

            // Peak fill only when active — no idle track strip
            Rectangle {
              visible: identityCell.peak > 1.5
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.margins: 4
              height: 3
              radius: 1.5
              color: "transparent"
              Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.width * Math.max(0, Math.min(1, identityCell.peak / 100))
                radius: 1.5
                color: Theme.accent
                opacity: 0.85
              }
            }
          }

          Rectangle {
            Layout.preferredWidth: root.masterStripW
            Layout.preferredHeight: root.rowH
            radius: Theme.radiusSm
            color: Theme.bgElevated
            border.width: 1
            border.color: Theme.border

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: 6
              anchors.rightMargin: 6
              spacing: 4

              MouseArea {
                Layout.preferredWidth: root.ctrlBtn
                Layout.preferredHeight: root.ctrlBtn
                cursorShape: Qt.PointingHandCursor
                enabled: !Audio.mixBusy && !!chBlock.modelData.present
                onClicked: Audio.setMixChannelMute(chBlock.modelData.id, !chBlock.modelData.muted)
                MixMuteGlyph {
                  anchors.centerIn: parent
                  muted: !!chBlock.modelData.muted
                }
              }

              ThemeSlider {
                id: masterSlider
                property int slideVol: -1
                Layout.fillWidth: true
                from: 0
                to: 100
                stepSize: 1
                wheelEnabled: false
                value: {
                  if (masterSlider.slideVol >= 0)
                    return masterSlider.slideVol
                  return chBlock.modelData.volume !== undefined ? chBlock.modelData.volume : 100
                }
                // Volume stays live during route/mute mutations (busy only gates writes that conflict).
                enabled: !!chBlock.modelData.present && !chBlock.modelData.muted
                onMoved: {
                  masterSlider.slideVol = Math.round(value)
                  Audio.setMixChannelVolume(chBlock.modelData.id, masterSlider.slideVol)
                }
                onPressedChanged: {
                  Audio.mixVolumeDragging = pressed
                  if (!pressed)
                    masterSlider.slideVol = -1
                }
              }
            }
          }

          Repeater {
            model: root.mixColumns

            Rectangle {
              id: mixCell
              required property var modelData
              Layout.preferredWidth: root.mixColW
              Layout.fillWidth: false
              Layout.preferredHeight: root.rowH
              radius: Theme.radiusSm
              readonly property var cell: root.cellFor(chBlock.modelData, modelData.id)
              readonly property bool active: !!cell.on
              readonly property bool colDragHot: root.isDragHot("mix", modelData.id)
              readonly property bool colDragSource: root.isDragSource("mix", modelData.id)
              opacity: {
                if (mixCell.colDragSource)
                  return 0.55
                if (root.dragKind === "mix" && !mixCell.colDragHot && !mixCell.colDragSource)
                  return 0.72
                return 1
              }
              color: {
                if (mixCell.colDragHot)
                  return Theme.accentSoft
                if (mixCell.active)
                  return Theme.bgElevated
                return emptyMa.containsMouse ? Theme.bgHover : "transparent"
              }
              border.width: mixCell.colDragHot || mixCell.colDragSource ? 2 : 1
              border.color: (mixCell.colDragHot || mixCell.colDragSource)
                  ? Theme.accent
                  : (mixCell.active ? Theme.border : Theme.separator)

              // Column drop line continues through the cell grid
              Item {
                visible: mixCell.colDragHot
                anchors.verticalCenter: parent.verticalCenter
                x: root.dragPlaceBefore
                    ? (-Math.ceil(root.gutter / 2) - 1)
                    : (parent.width - root.dropLine + Math.ceil(root.gutter / 2) + 1)
                width: root.dropLine
                height: parent.height + root.gutter
                z: 5
                Rectangle {
                  anchors.horizontalCenter: parent.horizontalCenter
                  anchors.top: parent.top
                  anchors.bottom: parent.bottom
                  width: root.dropLine
                  radius: root.dropLine / 2
                  color: Theme.accent
                }
              }

              MouseArea {
                id: emptyMa
                anchors.fill: parent
                visible: !mixCell.active
                hoverEnabled: true
                cursorShape: Audio.mixBusy ? Qt.BusyCursor : Qt.PointingHandCursor
                enabled: !Audio.mixBusy && !root.isDragging
                onClicked: {
                  if (!root.mixChannelsReady)
                    Audio.ensureMixChannels()
                  Audio.setMixRoute(chBlock.modelData.id, modelData.id, true)
                }
                Text {
                  anchors.centerIn: parent
                  text: "+"
                  color: Theme.textMute
                  font.family: Theme.fontFamily
                  font.pixelSize: root.labelPrimary
                }
              }

              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 6
                anchors.rightMargin: 4
                spacing: 4
                visible: mixCell.active

                MouseArea {
                  Layout.preferredWidth: root.ctrlBtn
                  Layout.preferredHeight: root.ctrlBtn
                  cursorShape: Qt.PointingHandCursor
                  enabled: !Audio.mixBusy
                  onClicked: Audio.setMixCellMute(chBlock.modelData.id, modelData.id, !mixCell.cell.muted)
                  MixMuteGlyph {
                    anchors.centerIn: parent
                    muted: !!mixCell.cell.muted
                  }
                }

                ThemeSlider {
                  id: cellSlider
                  property int slideVol: -1
                  Layout.fillWidth: true
                  from: 0
                  to: 100
                  stepSize: 1
                  wheelEnabled: false
                  value: {
                    if (cellSlider.slideVol >= 0)
                      return cellSlider.slideVol
                    return mixCell.cell.volume !== undefined ? mixCell.cell.volume : 100
                  }
                  enabled: !mixCell.cell.muted
                  onMoved: {
                    cellSlider.slideVol = Math.round(value)
                    Audio.setMixCellVolume(chBlock.modelData.id, modelData.id, cellSlider.slideVol)
                  }
                  onPressedChanged: {
                    Audio.mixVolumeDragging = pressed
                    if (!pressed)
                      cellSlider.slideVol = -1
                  }
                }

                MouseArea {
                  Layout.preferredWidth: root.ctrlBtn
                  Layout.preferredHeight: root.ctrlBtn
                  cursorShape: Qt.PointingHandCursor
                  enabled: !Audio.mixBusy
                  onClicked: Audio.setMixRoute(chBlock.modelData.id, modelData.id, false)
                  Text {
                    anchors.centerIn: parent
                    text: "×"
                    color: Theme.textMute
                    font.pixelSize: root.labelHeader
                  }
                }
              }
            }
          }
          }  // RowLayout mix controls
        }  // mixControlsHost

        // Folder contents
        Rectangle {
          visible: chBlock.expanded
          Layout.preferredWidth: root.gridW - 12
          Layout.maximumWidth: root.gridW - 12
          Layout.leftMargin: 12
          Layout.preferredHeight: {
            if (chBlock.isInput)
              return 40
            const n = (chBlock.modelData.apps || []).length
            const rows = Math.max(1, n) * 26 + 24
            return Math.min(160, rows + 8)
          }
          radius: Theme.radiusSm
          color: Theme.bgElevated
          border.width: 1
          border.color: Theme.border
          clip: true

          Flickable {
            anchors.fill: parent
            anchors.margins: 4
            contentWidth: width
            contentHeight: folderCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height + 2
            // Keep wheel on the folder when it can scroll (don't pan the grid).
            WheelHandler {
              enabled: parent.interactive
              onWheel: event => {
                const f = parent
                const next = Math.max(0, Math.min(f.contentHeight - f.height,
                    f.contentY - event.angleDelta.y))
                f.contentY = next
                event.accepted = true
              }
            }
            ColumnLayout {
              id: folderCol
              width: parent.width
              spacing: 0

              Text {
                visible: !chBlock.isInput && !(chBlock.modelData.apps && chBlock.modelData.apps.length)
                Layout.fillWidth: true
                Layout.preferredHeight: 22
                text: "No apps yet — add below."
                color: Theme.textMute
                font.family: Theme.fontFamily
                font.pixelSize: 11
                elide: Text.ElideRight
              }

              Repeater {
                model: chBlock.modelData.apps || []

                Rectangle {
                  required property var modelData
                  required property int index
                  Layout.fillWidth: true
                  Layout.preferredHeight: 26
                  color: folderMa.containsMouse ? Theme.bgHover : "transparent"
                  radius: Theme.radiusSm

                  RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 4
                    anchors.rightMargin: 4
                    spacing: 6

                    SquircleIcon {
                      Layout.preferredWidth: 18
                      Layout.preferredHeight: 18
                      pixelSize: 32
                      fillCrop: false
                      showBorder: false
                      glyphScale: Theme.iconGlyphScaleApp
                      plate: Theme.iconPlateFill
                      source: EnvGate.iconSource(root.appIcon(modelData))
                    }

                    Text {
                      Layout.preferredWidth: 8
                      text: modelData.playing ? "●" : ""
                      color: Theme.accent
                      font.pixelSize: 9
                    }

                    Text {
                      Layout.fillWidth: true
                      text: modelData.name || modelData.key
                      color: Theme.text
                      font.family: Theme.fontFamily
                      font.pixelSize: 12
                      elide: Text.ElideRight
                    }

                    MouseArea {
                      Layout.preferredWidth: 18
                      Layout.preferredHeight: 18
                      cursorShape: Qt.PointingHandCursor
                      enabled: !Audio.mixBusy
                      onClicked: Audio.unassignApp(modelData.key || modelData.name)
                      Text {
                        anchors.centerIn: parent
                        text: "×"
                        color: Theme.textMute
                        font.pixelSize: 12
                      }
                    }
                  }

                  MouseArea {
                    id: folderMa
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                  }
                }
              }

              Text {
                visible: chBlock.isInput
                Layout.fillWidth: true
                text: chBlock.modelData.sourceLabel || chBlock.modelData.source || "Capture device"
                color: Theme.textMute
                font.family: Theme.fontFamily
                font.pixelSize: 11
                elide: Text.ElideRight
              }

              MouseArea {
                visible: !chBlock.isInput
                Layout.fillWidth: true
                Layout.preferredHeight: 24
                cursorShape: Qt.PointingHandCursor
                hoverEnabled: true
                onClicked: {
                  if (chBlock.picking)
                    root.closePicker()
                  else
                    root.openPicker(chBlock.modelData.id)
                }
                Rectangle {
                  anchors.fill: parent
                  radius: Theme.radiusSm
                  color: parent.containsMouse ? Theme.bgHover : "transparent"
                }
                RowLayout {
                  anchors.fill: parent
                  anchors.leftMargin: 6
                  anchors.rightMargin: 6
                  spacing: 6
                  Text {
                    text: "+"
                    color: Theme.accent
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                  }
                  Text {
                    Layout.fillWidth: true
                    text: chBlock.picking ? "Hide apps" : "Add app"
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                  }
                }
              }
            }
          }
        }

        // System app picker for this channel
        Rectangle {
          visible: chBlock.picking
          Layout.preferredWidth: root.gridW - 12
          Layout.maximumWidth: root.gridW - 12
          Layout.leftMargin: 12
          Layout.preferredHeight: 168
          radius: Theme.radiusSm
          color: Theme.bgElevated
          border.width: 1
          border.color: Theme.border
          clip: true

          ColumnLayout {
            anchors.fill: parent
            anchors.margins: 4
            spacing: 2

            TextField {
              Layout.fillWidth: true
              Layout.preferredHeight: 26
              placeholderText: "Search apps…"
              color: Theme.text
              placeholderTextColor: Theme.textMute
              font.family: Theme.fontFamily
              font.pixelSize: root.labelPrimary
              background: Item {}
              text: root.pickerFilter
              onTextChanged: root.pickerFilter = text
            }

            Flickable {
              Layout.fillWidth: true
              Layout.fillHeight: true
              contentWidth: width
              contentHeight: pickerCol.implicitHeight
              clip: true
              boundsBehavior: Flickable.StopAtBounds
              interactive: contentHeight > height + 2
              WheelHandler {
                enabled: parent.interactive
                onWheel: event => {
                  const f = parent
                  f.contentY = Math.max(0, Math.min(f.contentHeight - f.height,
                      f.contentY - event.angleDelta.y))
                  event.accepted = true
                }
              }

              ColumnLayout {
                id: pickerCol
                width: parent.width
                spacing: 0

                Repeater {
                  model: root.pickerCandidates

                  MouseArea {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: 28
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    enabled: !Audio.mixBusy
                    onClicked: root.pickApp(modelData)
                    Rectangle {
                      anchors.fill: parent
                      radius: Theme.radiusSm
                      color: parent.containsMouse ? Theme.bgHover : "transparent"
                    }
                    RowLayout {
                      anchors.fill: parent
                      anchors.leftMargin: 4
                      anchors.rightMargin: 4
                      spacing: 6
                      SquircleIcon {
                        Layout.preferredWidth: 18
                        Layout.preferredHeight: 18
                        pixelSize: 32
                        fillCrop: false
                        showBorder: false
                        glyphScale: Theme.iconGlyphScaleApp
                        plate: Theme.iconPlateFill
                        source: EnvGate.iconSource(modelData.icon)
                      }
                      Text {
                        Layout.fillWidth: true
                        text: modelData.name
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        elide: Text.ElideRight
                      }
                      Text {
                        visible: !!modelData.elsewhere
                        text: "move"
                        color: Theme.textMute
                        font.pixelSize: 10
                      }
                    }
                  }
                }

                Text {
                  visible: root.pickerCandidates.length === 0
                  Layout.fillWidth: true
                  Layout.preferredHeight: 24
                  text: root.pickerFilter.length ? "No matching apps." : "No apps found."
                  color: Theme.textMute
                  font.family: Theme.fontFamily
                  font.pixelSize: 11
                }
              }
            }
          }
        }
      }
    }

    // Add channel / input — same + affordance as add-mix, with a choose popup
    RowLayout {
      Layout.fillWidth: false
      Layout.alignment: Qt.AlignLeft
      spacing: root.gutter

      MouseArea {
        id: addRowBtn
        Layout.preferredWidth: root.headerH
        Layout.preferredHeight: root.headerH
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true
        onClicked: {
          if (root.addChannelOpen || root.addInputOpen) {
            root.closeAddForms()
            addRowPopup.close()
            return
          }
          if (addRowPopup.opened)
            addRowPopup.close()
          else
            addRowPopup.open()
        }

        Rectangle {
          anchors.fill: parent
          radius: Theme.radiusSm
          color: (addRowBtn.containsMouse || addRowPopup.opened || root.addChannelOpen || root.addInputOpen)
              ? Theme.bgHover
              : "transparent"
          border.width: 1
          border.color: Theme.separator
          Text {
            anchors.centerIn: parent
            text: (root.addChannelOpen || root.addInputOpen || addRowPopup.opened) ? "⌃" : "+"
            color: Theme.accent
            font.pixelSize: 13
            font.weight: Font.DemiBold
          }
        }

        Popup {
          id: addRowPopup
          parent: addRowBtn
          x: 0
          y: addRowBtn.height + 4
          width: 148
          padding: 4
          modal: false
          focus: true
          closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
          onOpened: root.addRowMenuOpen = true
          onClosed: root.addRowMenuOpen = false

          background: Rectangle {
            radius: Theme.radiusSm
            color: Theme.bgElevated
            border.width: 1
            border.color: Theme.border
          }

          contentItem: ColumnLayout {
            spacing: 1

            MouseArea {
              Layout.fillWidth: true
              Layout.preferredHeight: 30
              cursorShape: Qt.PointingHandCursor
              hoverEnabled: true
              onClicked: {
                addRowPopup.close()
                root.openAddChannel()
              }
              Rectangle {
                anchors.fill: parent
                radius: Theme.radiusSm
                color: parent.containsMouse ? Theme.bgHover : "transparent"
              }
              Text {
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: "Channel"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 12
                font.weight: Font.DemiBold
              }
            }

            MouseArea {
              Layout.fillWidth: true
              Layout.preferredHeight: 30
              cursorShape: Qt.PointingHandCursor
              hoverEnabled: true
              onClicked: {
                addRowPopup.close()
                root.openAddInput()
              }
              Rectangle {
                anchors.fill: parent
                radius: Theme.radiusSm
                color: parent.containsMouse ? Theme.bgHover : "transparent"
              }
              Text {
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: "Input"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 12
                font.weight: Font.DemiBold
              }
            }
          }
        }
      }
    }

    Rectangle {
      visible: root.addChannelOpen
      Layout.preferredWidth: root.gridW
      Layout.preferredHeight: root.rowH
      Layout.alignment: Qt.AlignLeft
      radius: Theme.radiusSm
      color: Theme.bgElevated
      border.width: 1
      border.color: Theme.border

      RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 6
        spacing: 6

        TextField {
          id: addChannelField
          Layout.fillWidth: true
          placeholderText: "Channel name"
          color: Theme.text
          placeholderTextColor: Theme.textMute
          font.family: Theme.fontFamily
          font.pixelSize: root.labelPrimary
          background: Item {}
          text: root.addChannelName
          onTextChanged: root.addChannelName = text
          Keys.onReturnPressed: root.submitAddChannel()
          Keys.onEnterPressed: root.submitAddChannel()
        }

        MouseArea {
          Layout.preferredWidth: 44
          Layout.preferredHeight: 24
          cursorShape: Qt.PointingHandCursor
          enabled: !Audio.mixBusy && String(root.addChannelName || "").trim().length > 0
          onClicked: root.submitAddChannel()
          Rectangle {
            anchors.fill: parent
            radius: Theme.radiusSm
            color: parent.enabled ? Theme.accentSoft : "transparent"
            border.width: 1
            border.color: parent.enabled ? Theme.accent : Theme.separator
            Text {
              anchors.centerIn: parent
              text: "Add"
              color: parent.parent.enabled ? Theme.accent : Theme.textMute
              font.family: Theme.fontFamily
              font.pixelSize: 11
              font.weight: Font.DemiBold
            }
          }
        }
      }
    }

    Rectangle {
      visible: root.addInputOpen
      Layout.preferredWidth: Math.min(root.gridW, 340)
      Layout.preferredHeight: Math.min(132, 34 + Math.max(26, root.inputCandidates.length * 26))
      Layout.alignment: Qt.AlignLeft
      radius: Theme.radiusSm
      color: Theme.bgElevated
      border.width: 1
      border.color: Theme.border
      clip: true

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: 4
        spacing: 2

        TextField {
          Layout.fillWidth: true
          Layout.preferredHeight: 26
          placeholderText: "Search capture…"
          color: Theme.text
          placeholderTextColor: Theme.textMute
          font.family: Theme.fontFamily
          font.pixelSize: root.labelPrimary
          background: Item {}
          text: root.addInputFilter
          onTextChanged: root.addInputFilter = text
        }

        Flickable {
          Layout.fillWidth: true
          Layout.fillHeight: true
          contentWidth: width
          contentHeight: addInputList.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height + 2
          WheelHandler {
            enabled: parent.interactive
            onWheel: event => {
              const f = parent
              f.contentY = Math.max(0, Math.min(f.contentHeight - f.height,
                  f.contentY - event.angleDelta.y))
              event.accepted = true
            }
          }

          ColumnLayout {
            id: addInputList
            width: parent.width
            spacing: 0

            Repeater {
              model: root.inputCandidates
              MouseArea {
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredHeight: 26
                cursorShape: Qt.PointingHandCursor
                hoverEnabled: true
                enabled: !Audio.mixBusy
                onClicked: root.pickInput(modelData)
                Rectangle {
                  anchors.fill: parent
                  radius: Theme.radiusSm
                  color: parent.containsMouse ? Theme.bgHover : "transparent"
                }
                RowLayout {
                  anchors.fill: parent
                  anchors.leftMargin: 6
                  anchors.rightMargin: 6
                  Text {
                    Layout.fillWidth: true
                    text: modelData.label
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    elide: Text.ElideRight
                  }
                  Text {
                    text: "+"
                    color: Theme.accent
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                  }
                }
              }
            }

            Text {
              visible: root.inputCandidates.length === 0
              Layout.fillWidth: true
              Layout.preferredHeight: 22
              text: root.addInputFilter.length ? "No matching inputs." : "No unused capture devices."
              color: Theme.textMute
              font.family: Theme.fontFamily
              font.pixelSize: 11
            }
          }
        }
      }
    }
  }
  } // mixFlick
  } // mixViewport

  Text {
    Layout.fillWidth: true
    visible: Audio.mixError.length > 0
    text: Audio.mixError
    color: Theme.danger
    font.family: Theme.fontFamily
    font.pixelSize: 12
    wrapMode: Text.WordWrap
  }

  // Quiet escape — full PipeWire graph when the Mixer model isn’t enough.
  SettingsFormRow {
    label: "Graph editor"
    hint: Audio.graphEditorHint
    showSeparator: false
    interactive: true
    onActivated: {
      if (Audio.graphEditorAvailable)
        Audio.openGraphEditor()
      else
        SettingsNav.goInstallSearch("qpwgraph")
    }
    Text {
      text: Audio.graphEditorAvailable ? "Open" : "Install…"
      color: Theme.accent
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSize
    }
  }

  Text {
    Layout.fillWidth: true
    Layout.maximumWidth: 520
    text: "Fact: ~/.config/proteus/audio-mix.json · pactl null sinks / loopbacks. Full patchbay: qpwgraph (Install… → Software)."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 11
    wrapMode: Text.WordWrap
  }
}
