import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Window
import "../../shared"

// Dock — floating glass shelf; macOS-like pins + running apps + Keep/Remove.
Item {
  id: root
  clip: false

  readonly property real dpr: Math.max(1, Screen.devicePixelRatio || 1)

  readonly property int iconSize: Theme.dockIconSize
  readonly property int maxIconSize: Theme.dockIconMax
  readonly property int spacing: Math.max(6, Math.round(iconSize * 0.14))
  readonly property int padX: Math.max(14, Math.round(iconSize * 0.32))
  readonly property int padTop: Math.max(6, Math.round(iconSize * 0.14))
  readonly property int padBottom: Math.max(8, Math.round(iconSize * 0.18))
  readonly property real magRange: Math.max(110, iconSize * 2.55)

  readonly property real restScale: iconSize / maxIconSize
  readonly property real peakScale: 1.0

  readonly property int bitmapSize: {
    const need = Math.ceil(maxIconSize * dpr)
    const buckets = [64, 96, 128, 192, 256]
    for (let i = 0; i < buckets.length; i++) {
      if (buckets[i] >= need)
        return buckets[i]
    }
    return Math.max(need, 256)
  }

  readonly property var items: DockApps.dockItems
  readonly property int count: items.length
  readonly property int tipH: 22
  readonly property int tipGap: 10
  property int mouseX: -1000
  property bool hovered: false
  property int tipIndex: -1
  property int pressIndex: -1
  property int menuIndex: -1
  property bool menuOpen: false

  // Interaction tiers (macOS + iOS):
  //  1) Click → launch
  //  2) Right-click → Keep in Dock / Remove from Dock
  //  3) Press+drag (threshold) → reorder; drag off shelf → Remove (macOS)
  //  4) Long-press (no move) → edit mode + −/+ (fixed size); Done / empty click exits
  property bool editMode: false
  property bool dragging: false
  property int dragIndex: -1
  property real dragGrabX: 0
  property real dragGrabY: 0
  property real dragItemX: 0
  property real dragX: 0
  property real dragLift: 0
  property bool dragRemoving: false
  property bool suppressClick: false
  property real pressX: 0
  property real pressY: 0
  readonly property real dragThreshold: 7
  readonly property real removeThreshold: shelfHeight * 0.75

  // Separator (pins ‖ transients) is narrower than an icon — layout is a
  // prefix-sum over per-item widths, not index * (iconSize + spacing).
  readonly property int sepW: Math.max(9, Math.round(spacing * 1.5))

  function widthAt(index) {
    const e = items[index]
    return e && e.separator ? sepW : iconSize
  }

  readonly property var cellLefts: {
    const out = []
    let x = padX
    for (let i = 0; i < items.length; i++) {
      out.push(x)
      x += (items[i] && items[i].separator ? sepW : iconSize) + spacing
    }
    return out
  }

  readonly property real rowWidth: {
    let w = 0
    for (let i = 0; i < items.length; i++)
      w += items[i] && items[i].separator ? sepW : iconSize
    if (items.length > 1)
      w += (items.length - 1) * spacing
    return w
  }

  readonly property int shelfHeight: iconSize + padTop + padBottom
  readonly property int magHeadroom: (maxIconSize - iconSize) + tipH + tipGap + 12
  readonly property real plateRadius: shelfHeight * Theme.squircleCornerRatio

  // Window previews — hover-dwell popup with one live thumbnail per window.
  // The band is a FIXED reserve above the shelf: resizing the layer surface on
  // open/close made Hyprland re-anchor mid-frame (dock bottom visibly clipped).
  // Input is masked to `inputZone` so the transparent band never steals clicks.
  property int previewIndex: -1
  readonly property bool previewOpen: previewIndex >= 0
  property var previewWins: []
  property int previewArmIndex: -1
  readonly property int previewThumbW: 168
  // thumb (168·0.62 ≈ 104) + title 22 + plate pad 20 + gap 24
  readonly property int previewReserve: 170
  // Auto-hide state from the panel window — widens the mask to the hover peek.
  property bool autoHidden: false

  readonly property int baseHeight: Math.round(shelfHeight + magHeadroom)
  implicitWidth: Math.round(rowWidth + padX * 2)
  implicitHeight: baseHeight + previewReserve

  // Input region for the panel window mask: shelf + magnify headroom at rest;
  // the full surface while the preview popup is open or the dock is auto-hidden
  // (the hover peek strip lives at the surface top).
  readonly property Item inputZone: maskZone
  Item {
    id: maskZone
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: root.previewOpen || root.autoHidden ? parent.height : root.baseHeight
  }

  function centerAt(index) {
    if (index < 0 || index >= cellLefts.length)
      return 0
    return cellLefts[index] + widthAt(index) * 0.5
  }

  function scaleAt(index) {
    if (items[index] && items[index].separator)
      return restScale
    if (editMode || dragging || menuOpen)
      return restScale
    if (!hovered || mouseX < 0)
      return restScale
    const d = Math.abs(mouseX - centerAt(index))
    if (d >= magRange)
      return restScale
    const t = (Math.cos(Math.PI * d / magRange) + 1) * 0.5
    return restScale + (peakScale - restScale) * t
  }

  function setMouse(x) {
    const qx = Math.round(x)
    if (mouseX >= 0 && Math.abs(qx - mouseX) < 1)
      return
    mouseX = qx
  }

  function indexAt(x) {
    for (let i = 0; i < count; i++) {
      const left = cellLefts[i]
      if (x >= left && x < left + widthAt(i))
        return i
    }
    return -1
  }

  function insertPinIndexForX(x) {
    const pins = DockApps.pinIdList()
    const n = pins.length
    if (n <= 0)
      return 0
    let insertAt = 0
    for (let p = 0; p < n; p++) {
      const dockI = 1 + p
      if (dockI >= count)
        break
      if (x >= centerAt(dockI))
        insertAt = p + 1
    }
    return Math.max(0, Math.min(n, insertAt))
  }

  function menuEntry() {
    if (menuIndex < 0 || menuIndex >= items.length)
      return null
    return items[menuIndex]
  }

  function hasPreviewableWindows(index) {
    const e = items[index]
    if (!e || e.separator || e.special === "launcher")
      return false
    return DockApps.windowsFor(e).length > 0
  }

  function openPreview(index) {
    if (editMode || dragging || menuOpen)
      return
    const e = items[index]
    if (!e || e.separator || e.special === "launcher")
      return
    const wins = DockApps.windowsFor(e)
    if (!wins.length)
      return
    previewWins = wins
    previewIndex = index
    previewCloseTimer.stop()
  }

  function closePreview() {
    previewIndex = -1
    previewArmIndex = -1
    previewWins = []
    previewTimer.stop()
    previewCloseTimer.stop()
  }

  function openPinMenu(index, x, y) {
    if (dragging)
      return
    if (index < 0 || index >= items.length)
      return
    root.closePreview()
    const entry = items[index]
    const keep = DockApps.canKeepInDock(entry)
    const remove = DockApps.canUnpin(entry)
    if (!keep && !remove && !DockApps.canQuit(entry))
      return
    root.menuIndex = index
    root.menuOpen = true
    root.tipIndex = -1
    root.mouseX = -1000
    Qt.callLater(() => {
      const cx = root.centerAt(index)
      ctxMenu.x = Math.max(8, Math.min(cx - ctxMenu.width * 0.5, root.width - ctxMenu.width - 8))
      ctxMenu.y = Math.max(4, root.height - root.shelfHeight - ctxMenu.height - 10)
    })
  }

  function closePinMenu() {
    root.menuOpen = false
    root.menuIndex = -1
  }

  function enterEditMode() {
    root.closePinMenu()
    root.closePreview()
    root.editMode = true
    root.suppressClick = true
    root.tipIndex = -1
    root.hovered = true
    root.pressIndex = -1
  }

  function exitEditMode() {
    root.editMode = false
  }

  function canDragEntry(entry) {
    if (!entry)
      return false
    // Pins reorder/remove; transients can be kept via drag-onto-shelf commit (pin at end).
    if (DockApps.canReorder(entry))
      return true
    if (DockApps.canKeepInDock(entry))
      return true
    return false
  }

  function beginDrag(index) {
    if (index < 0 || index >= items.length)
      return false
    const entry = items[index]
    if (!canDragEntry(entry))
      return false
    root.closePinMenu()
    root.closePreview()
    holdTimer.stop()
    root.dragging = true
    root.dragIndex = index
    // cellLefts accounts for the pins‖running separator width; index * pitch does not.
    root.dragItemX = index < cellLefts.length
        ? cellLefts[index]
        : (padX + index * (iconSize + spacing))
    root.dragGrabX = root.pressX
    root.dragGrabY = root.pressY
    root.dragX = root.dragItemX
    root.dragLift = 0
    root.dragRemoving = false
    root.suppressClick = true
    root.tipIndex = -1
    return true
  }

  function updateDrag(mx, my) {
    if (!dragging)
      return
    root.dragX = root.dragItemX + (mx - root.dragGrabX)
    const shelfTop = root.height - root.shelfHeight
    root.dragLift = Math.max(0, shelfTop - my)
    const entry = (dragIndex >= 0 && dragIndex < items.length) ? items[dragIndex] : null
    // Remove only for pinned apps; transients show "Keep" when lifted back onto shelf.
    if (entry && DockApps.canUnpin(entry))
      root.dragRemoving = root.dragLift > root.removeThreshold
    else
      root.dragRemoving = false
  }

  function endDrag(commit) {
    holdTimer.stop()
    if (!dragging) {
      root.pressIndex = -1
      return
    }
    const idx = dragIndex
    const entry = (idx >= 0 && idx < items.length) ? items[idx] : null
    const removing = dragRemoving
    const wasLifted = dragLift > root.removeThreshold
    const finalX = dragX
    root.dragging = false
    root.dragIndex = -1
    root.dragRemoving = false
    root.dragLift = 0
    root.pressIndex = -1

    if (!commit || !entry)
      return

    if (DockApps.canUnpin(entry) && removing) {
      DockApps.unpinEntry(entry)
      return
    }

    // Transient dragged and released on shelf → Keep in Dock at drop slot.
    if (DockApps.canKeepInDock(entry) && !wasLifted) {
      const id = DockApps.normalizeDesktopId(entry.desktopId || entry.id)
      DockApps.pinDesktopId(id)
      const insertAt = insertPinIndexForX(finalX + iconSize * 0.5)
      DockApps.reorderPinnedDesktopId(id, Math.min(insertAt, DockApps.pinIdList().length - 1))
      return
    }

    if (!DockApps.canReorder(entry))
      return
    const fromPin = DockApps.pinIdList().indexOf(DockApps.normalizeDesktopId(entry.desktopId || entry.id))
    if (fromPin < 0)
      return
    const insertAt = insertPinIndexForX(finalX + iconSize * 0.5)
    let dest = insertAt
    if (dest > fromPin)
      dest -= 1
    if (dest !== fromPin)
      DockApps.reorderPinnedDesktopId(entry.desktopId || entry.id, dest)
  }

  // Soft curve-following rim (behind plate) — continuous glass edge, not a
  // straight specular band (Qt clip can't mask a top strip to the squircle).
  Rectangle {
    anchors.horizontalCenter: plate.horizontalCenter
    anchors.bottom: plate.bottom
    anchors.bottomMargin: -1
    width: plate.width + 2
    height: plate.height + 2
    radius: root.plateRadius + 1
    color: "transparent"
    border.width: Theme.chromeClear || !Theme.blur ? 0 : 1
    border.color: Theme.dockEdgeGlow
    antialiasing: true
    z: 0
    visible: Theme.blur && !Theme.chromeClear
  }

  Rectangle {
    id: plate
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    // 1px lift so the edge-glow rim (plate + 1px on every side) can draw its
    // bottom band inside the surface — flush, it clipped to top+sides only.
    anchors.bottomMargin: 1
    width: parent.width
    height: root.shelfHeight
    radius: root.plateRadius
    color: Theme.dockPlateFill
    antialiasing: true
    // Hairline only when not frosted — blur+edge glow carry the rim instead
    // of a hard 1px stroke that fights the squircle.
    border.width: Theme.chromeClear ? 0 : (Theme.blur ? 0 : 1)
    border.color: Theme.chromeHairline
    z: 1

    Behavior on color {
      ColorAnimation {
        duration: 180
        easing.type: Easing.OutCubic
      }
    }
    Behavior on border.color {
      ColorAnimation {
        duration: 180
        easing.type: Easing.OutCubic
      }
    }
  }

  Timer {
    id: holdTimer
    interval: 480
    repeat: false
    onTriggered: {
      // Long-press without drag → edit mode (− / +; rest sizes).
      if (root.pressIndex >= 0 && !root.dragging)
        root.enterEditMode()
    }
  }

  // Hover dwell before the preview opens (tooltip stays instant).
  Timer {
    id: previewTimer
    interval: 420
    repeat: false
    onTriggered: {
      if (root.previewArmIndex >= 0 && root.hasPreviewableWindows(root.previewArmIndex))
        root.openPreview(root.previewArmIndex)
    }
  }

  // Grace period when the pointer leaves the shelf/popup before closing.
  Timer {
    id: previewCloseTimer
    interval: 260
    repeat: false
    onTriggered: {
      if (!previewHover.hovered && !dockMa.containsMouse)
        root.closePreview()
    }
  }

  MouseArea {
    id: dockMa
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: root.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
    z: 10
    onEntered: root.hovered = true
    onExited: {
      if (root.previewOpen)
        previewCloseTimer.restart()
      if (root.menuOpen || root.dragging)
        return
      if (!root.editMode) {
        root.hovered = false
        root.mouseX = -1000
      }
      root.tipIndex = -1
    }
    onPositionChanged: mouse => {
      root.hovered = true
      root.setMouse(mouse.x)
      if (root.dragging) {
        root.updateDrag(mouse.x, mouse.y)
        return
      }
      if (root.pressIndex >= 0 && mouse.buttons & Qt.LeftButton) {
        const dx = mouse.x - root.pressX
        const dy = mouse.y - root.pressY
        if (Math.sqrt(dx * dx + dy * dy) >= root.dragThreshold) {
          holdTimer.stop()
          root.beginDrag(root.pressIndex)
          root.updateDrag(mouse.x, mouse.y)
          return
        }
      }
      const hi = root.editMode ? -1 : root.indexAt(mouse.x)
      root.tipIndex = (hi >= 0 && root.items[hi] && root.items[hi].separator) ? -1 : hi
      // Preview arm / retarget — instant switch while a popup is already open.
      if (!root.editMode && !root.dragging && !root.menuOpen) {
        if (root.previewOpen) {
          if (hi >= 0 && hi !== root.previewIndex && root.hasPreviewableWindows(hi))
            root.openPreview(hi)
        } else if (hi >= 0 && root.hasPreviewableWindows(hi)) {
          if (root.previewArmIndex !== hi) {
            root.previewArmIndex = hi
            previewTimer.restart()
          }
        } else {
          root.previewArmIndex = -1
          previewTimer.stop()
        }
      }
    }
    onClicked: mouse => {
      if (root.suppressClick) {
        root.suppressClick = false
        return
      }
      if (root.menuOpen) {
        root.closePinMenu()
        return
      }
      if (root.dragging)
        return
      const i = root.indexAt(mouse.x)
      if (mouse.button === Qt.RightButton) {
        if (i >= 0)
          root.openPinMenu(i, mouse.x, mouse.y)
        return
      }
      // Empty shelf / background click exits edit mode (iOS Done-ish).
      // Icon click in edit mode also exits, then launches — stuck edit mode
      // was a common "dock apps won't open" failure after a long-press.
      if (root.editMode) {
        if (i < 0) {
          root.exitEditMode()
          return
        }
        root.exitEditMode()
      }
      if (i < 0)
        return
      root.closePreview()
      DockApps.focusOrLaunch(root.items[i])
    }
    onPressed: mouse => {
      root.setMouse(mouse.x)
      const pi = root.indexAt(mouse.x)
      root.pressIndex = (pi >= 0 && root.items[pi] && root.items[pi].separator) ? -1 : pi
      root.pressX = mouse.x
      root.pressY = mouse.y
      holdTimer.stop()
      if (mouse.button === Qt.LeftButton && root.pressIndex >= 0) {
        const e = root.items[root.pressIndex]
        if (root.canDragEntry(e) || DockApps.canUnpin(e))
          holdTimer.restart()
      }
    }
    onReleased: mouse => {
      holdTimer.stop()
      if (root.dragging)
        root.endDrag(true)
      else
        root.pressIndex = -1
    }
    onCanceled: {
      holdTimer.stop()
      if (root.dragging)
        root.endDrag(false)
      root.pressIndex = -1
    }
  }

  // Drag feedback chip (macOS Remove / Keep) — tooltip plate for wallpaper legibility
  Rectangle {
    z: 60
    visible: root.dragging && dragTipLabel.text.length > 0
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: plate.top
    anchors.bottomMargin: 8
    width: dragTipLabel.implicitWidth + 16
    height: root.tipH
    radius: 6
    color: Theme.light
        ? Qt.rgba(0.15, 0.15, 0.16, 0.92)
        : Qt.rgba(0.18, 0.18, 0.2, 0.94)
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.08)

    Text {
      id: dragTipLabel
      anchors.centerIn: parent
      text: {
        if (root.dragIndex < 0 || root.dragIndex >= root.items.length)
          return ""
        const e = root.items[root.dragIndex]
        if (root.dragRemoving && DockApps.canUnpin(e))
          return "Remove"
        if (DockApps.canKeepInDock(e) && root.dragLift > 4)
          return "Keep in Dock"
        return ""
      }
      color: root.dragRemoving ? Theme.danger : "#f5f5f7"
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSizeSm
      font.weight: Font.Medium
    }
  }

  // Edit-mode Done chip (iOS)
  Rectangle {
    z: 55
    visible: root.editMode && !root.dragging
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: plate.top
    anchors.bottomMargin: 10
    width: doneLabel.implicitWidth + 22
    height: 28
    radius: 14
    color: Theme.accent
    Text {
      id: doneLabel
      anchors.centerIn: parent
      text: "Done"
      color: "#fff"
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSizeSm
      font.weight: Font.Medium
    }
    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: root.exitEditMode()
    }
  }

  // Glass context menu — Keep / Remove (ChromeMenuPlate kit seed)
  ChromeMenuPlate {
    id: ctxMenu
    visible: root.menuOpen
    z: 50
    readonly property int rowH: 34
    readonly property int padX: 14
    readonly property int padY: 6
    readonly property bool showKeep: {
      const e = root.menuEntry()
      return !!(e && DockApps.canKeepInDock(e))
    }
    readonly property bool showRemove: {
      const e = root.menuEntry()
      return !!(e && DockApps.canUnpin(e))
    }
    readonly property bool showQuit: {
      const e = root.menuEntry()
      return !!(e && DockApps.canQuit(e))
    }
    readonly property int sepCount: ((showKeep || showRemove) && showQuit ? 1 : 0)
        + (showKeep && showRemove ? 1 : 0)
    width: Math.max(
          showKeep ? keepMeasure.implicitWidth : 0,
          showRemove ? removeMeasure.implicitWidth : 0,
          showQuit ? quitMeasure.implicitWidth : 0,
          120
        ) + padX * 2
    height: padY * 2
        + (showKeep ? rowH : 0)
        + (showRemove ? rowH : 0)
        + (showQuit ? rowH : 0)
        + sepCount

    Text {
      id: keepMeasure
      visible: false
      text: "Keep in Dock"
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSizeSm
    }
    Text {
      id: removeMeasure
      visible: false
      text: "Remove from Dock"
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSizeSm
    }
    Text {
      id: quitMeasure
      visible: false
      text: "Quit"
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSizeSm
    }

    Column {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.topMargin: ctxMenu.padY
      spacing: 0

      Item {
        width: parent.width
        height: ctxMenu.rowH
        visible: ctxMenu.showKeep

        Rectangle {
          anchors.fill: parent
          anchors.leftMargin: 4
          anchors.rightMargin: 4
          radius: Theme.radiusSm
          color: Theme.chromeAccentSoft
          opacity: keepMa.containsMouse ? 1 : 0
        }
        Text {
          anchors.centerIn: parent
          text: keepMeasure.text
          color: Theme.text
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSizeSm
        }
        MouseArea {
          id: keepMa
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            const e = root.menuEntry()
            if (e)
              DockApps.pinDesktopId(e.desktopId || e.id)
            root.closePinMenu()
          }
        }
      }

      Item {
        width: parent.width
        height: 1
        visible: ctxMenu.showKeep && ctxMenu.showRemove
        Rectangle {
          anchors.horizontalCenter: parent.horizontalCenter
          width: parent.width - 16
          height: 1
          color: Theme.separator
        }
      }

      Item {
        width: parent.width
        height: ctxMenu.rowH
        visible: ctxMenu.showRemove

        Rectangle {
          anchors.fill: parent
          anchors.leftMargin: 4
          anchors.rightMargin: 4
          radius: Theme.radiusSm
          color: Theme.chromeAccentSoft
          opacity: removeMa.containsMouse ? 1 : 0
        }
        Text {
          anchors.centerIn: parent
          text: removeMeasure.text
          color: Theme.danger
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSizeSm
        }
        MouseArea {
          id: removeMa
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            const e = root.menuEntry()
            if (e)
              DockApps.unpinEntry(e)
            root.closePinMenu()
          }
        }
      }

      Item {
        width: parent.width
        height: 1
        visible: (ctxMenu.showKeep || ctxMenu.showRemove) && ctxMenu.showQuit
        Rectangle {
          anchors.horizontalCenter: parent.horizontalCenter
          width: parent.width - 16
          height: 1
          color: Theme.separator
        }
      }

      // Quit — close every window of the app (apps prompt for unsaved work).
      Item {
        width: parent.width
        height: ctxMenu.rowH
        visible: ctxMenu.showQuit

        Rectangle {
          anchors.fill: parent
          anchors.leftMargin: 4
          anchors.rightMargin: 4
          radius: Theme.radiusSm
          color: Theme.chromeAccentSoft
          opacity: quitMa.containsMouse ? 1 : 0
        }
        Text {
          anchors.centerIn: parent
          text: quitMeasure.text
          color: Theme.text
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSizeSm
        }
        MouseArea {
          id: quitMa
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            const e = root.menuEntry()
            if (e)
              DockApps.quitEntry(e)
            root.closePinMenu()
          }
        }
      }
    }
  }

  // Window preview popup — glass plate with live thumbnails; click focuses
  // (restores dock-minimized windows), ✕ closes the window.
  ChromeMenuPlate {
    id: previewPlate
    visible: root.previewOpen
    z: 45
    readonly property int n: root.previewWins.length
    readonly property int cardW: n > 0
        ? Math.max(96, Math.min(root.previewThumbW, Math.floor((root.width - 32 - (n - 1) * 10) / n)))
        : root.previewThumbW
    readonly property int thumbH: Math.round(cardW * 0.62)
    readonly property int cardH: thumbH + 22
    width: Math.max(1, n) * cardW + Math.max(0, n - 1) * 10 + 20
    height: cardH + 20
    x: Math.max(8, Math.min(
          root.centerAt(Math.max(0, root.previewIndex)) - width * 0.5,
          root.width - width - 8))
    y: root.height - root.shelfHeight - height - 12

    HoverHandler {
      id: previewHover
      onHoveredChanged: {
        if (hovered)
          previewCloseTimer.stop()
        else
          previewCloseTimer.restart()
      }
    }

    Row {
      anchors.centerIn: parent
      spacing: 10

      Repeater {
        model: root.previewWins

        Item {
          id: previewCard
          required property var modelData
          required property int index
          width: previewPlate.cardW
          height: previewPlate.cardH

          readonly property bool parked: DockApps.isMinimizedToplevel(modelData)
          readonly property bool cardHot: cardMa.containsMouse || closeMa.containsMouse

          Rectangle {
            id: thumbFrame
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: previewPlate.thumbH
            radius: Theme.radiusSm
            color: Theme.light ? Qt.rgba(0, 0, 0, 0.08) : Qt.rgba(1, 1, 1, 0.06)
            border.width: 1
            border.color: previewCard.cardHot ? Theme.accent : Theme.chromeHairline
            clip: true

            ScreencopyView {
              anchors.fill: parent
              anchors.margins: 1
              captureSource: previewCard.modelData.wayland ? previewCard.modelData.wayland : null
              live: root.previewOpen
              opacity: previewCard.parked ? 0.55 : 1
            }

            // Parked (dock-minimized) hint
            Rectangle {
              visible: previewCard.parked
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.margins: 5
              width: hiddenLabel.implicitWidth + 10
              height: 16
              radius: 8
              color: Qt.rgba(0, 0, 0, 0.55)
              Text {
                id: hiddenLabel
                anchors.centerIn: parent
                text: "Hidden"
                color: "#f5f5f7"
                font.family: Theme.fontFamily
                font.pixelSize: 9
                font.weight: Font.Medium
              }
            }
          }

          Text {
            anchors.top: thumbFrame.bottom
            anchors.topMargin: 4
            anchors.left: parent.left
            anchors.right: parent.right
            text: DockApps.titleOf(previewCard.modelData)
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: 11
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
          }

          MouseArea {
            id: cardMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              DockApps.focusToplevel(previewCard.modelData)
              root.closePreview()
            }
          }

          // ✕ close — only while hovering the card (macOS Exposé-ish)
          Rectangle {
            visible: previewCard.cardHot
            anchors.top: thumbFrame.top
            anchors.left: thumbFrame.left
            anchors.margins: 4
            width: 18
            height: 18
            radius: 9
            color: Qt.rgba(0, 0, 0, 0.6)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.25)
            Text {
              anchors.centerIn: parent
              text: "✕"
              color: "#f5f5f7"
              font.pixelSize: 9
              font.bold: true
            }
            MouseArea {
              id: closeMa
              anchors.fill: parent
              anchors.margins: -3
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                const target = previewCard.modelData
                DockApps.closeToplevel(target)
                const rest = root.previewWins.filter(w => w !== target)
                if (rest.length)
                  root.previewWins = rest
                else
                  root.closePreview()
              }
            }
          }
        }
      }
    }
  }

  Repeater {
    model: root.items

    Item {
      id: cell
      required property var modelData
      required property int index

      readonly property bool isSep: !!modelData.separator
      readonly property real s: root.scaleAt(index)
      property real displayS: s
      property real displayPress: 1
      property real bounceY: 0
      readonly property real rise: root.maxIconSize * (displayS - root.restScale)
      readonly property bool tipOn: !isSep && root.tipIndex === index && !root.menuOpen && !root.editMode && !root.dragging && !root.previewOpen
      readonly property bool brandIcon: modelData.special === "launcher"
          || modelData.special === "settings"
          || modelData.icon === "proteus-launcher"
          || modelData.icon === "proteus-settings"
      readonly property bool launching: DockApps.isLaunching(modelData)
      readonly property bool isDragging: root.dragging && root.dragIndex === index
      readonly property bool showMinus: root.editMode && !isDragging && DockApps.canUnpin(modelData)
      readonly property bool showKeepBadge: root.editMode && !isDragging && DockApps.canKeepInDock(modelData)
      readonly property real restX: index < root.cellLefts.length ? root.cellLefts[index] : 0

      onSChanged: displayS = s
      Connections {
        target: root
        function onPressIndexChanged() {
          cell.displayPress = root.pressIndex === cell.index ? 0.90 : 1
        }
      }
      Component.onCompleted: {
        displayS = s
        displayPress = root.pressIndex === index ? 0.90 : 1
      }

      Behavior on displayS {
        enabled: !root.editMode && !root.dragging && !root.menuOpen
        NumberAnimation {
          duration: 70
          easing.type: Easing.OutCubic
        }
      }
      Behavior on displayPress {
        enabled: !root.editMode
        NumberAnimation {
          duration: 90
          easing.type: Easing.OutCubic
        }
      }

      x: isDragging ? root.dragX : restX
      opacity: isDragging && root.dragRemoving ? 0.45 : 1
      width: isSep ? root.sepW : root.iconSize
      height: root.iconSize + root.magHeadroom
      anchors.bottom: parent.bottom
      anchors.bottomMargin: root.padBottom
      z: isDragging ? 40 : (tipOn ? 20 : Math.round(10 + index + (displayS - root.restScale) * 40))
      clip: false

      // Launch feedback — macOS bounce until the first window appears.
      SequentialAnimation {
        running: cell.launching && !cell.isDragging && !root.editMode
        loops: Animation.Infinite
        onRunningChanged: {
          if (!running)
            cell.bounceY = 0
        }

        NumberAnimation {
          target: cell
          property: "bounceY"
          from: 0
          to: Math.round(root.iconSize * 0.5)
          duration: 300
          easing.type: Easing.OutQuad
        }
        NumberAnimation {
          target: cell
          property: "bounceY"
          to: 0
          duration: 340
          easing.type: Easing.InQuad
        }
        PauseAnimation {
          duration: 320
        }
      }

      // Hairline between pinned and transient (running-only) apps.
      Rectangle {
        visible: cell.isSep
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Math.round(root.iconSize * 0.16)
        width: 1
        height: Math.round(root.iconSize * 0.62)
        color: Theme.light ? Qt.rgba(0, 0, 0, 0.22) : Qt.rgba(1, 1, 1, 0.18)
      }

      // Fixed badge geometry (rest icon size; outside mag Scale)
      readonly property real badgeSize: Math.round(root.iconSize * 0.38)
      readonly property real iconVisual: root.iconSize * Theme.iconFrameScale
      readonly property real iconLeft: (width - iconVisual) * 0.5
      readonly property real iconTop: height - iconVisual

      transform: Translate {
        y: isDragging ? -Math.min(root.dragLift, root.maxIconSize) : -cell.bounceY
      }

      Rectangle {
        visible: cell.tipOn
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height - root.iconSize - cell.rise - root.tipGap - height
        height: root.tipH
        width: tipLabel.implicitWidth + 16
        radius: 6
        color: Theme.light
            ? Qt.rgba(0.15, 0.15, 0.16, 0.92)
            : Qt.rgba(0.18, 0.18, 0.2, 0.94)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.08)
        z: 30

        Text {
          id: tipLabel
          anchors.centerIn: parent
          text: modelData.label || modelData.id
          color: "#f5f5f7"
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSizeSm
          font.weight: Font.Medium
        }
      }

      Item {
        id: glyph
        visible: !cell.isSep
        width: root.maxIconSize
        height: root.maxIconSize
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        clip: false
        z: 15

        transform: Scale {
          origin.x: glyph.width * 0.5
          origin.y: glyph.height
          xScale: cell.displayS * cell.displayPress
          yScale: cell.displayS * cell.displayPress
        }

        SquircleIcon {
          id: squircle
          anchors.centerIn: parent
          width: parent.width * Theme.iconFrameScale
          height: width
          pixelSize: root.bitmapSize
          showBorder: false
          fillCrop: false
          glyphScale: cell.brandIcon ? Theme.iconGlyphScaleBrand : Theme.iconGlyphScaleApp
          plate: Theme.iconPlateFill
          source: DockApps.iconSource(modelData)
        }
      }

      // − / + fixed size on rest squircle corners (no jiggle / no mag scale)
      Rectangle {
        visible: cell.showMinus
        width: cell.badgeSize
        height: cell.badgeSize
        radius: width * 0.5
        z: 60
        x: cell.iconLeft - width * 0.28
        y: cell.iconTop - height * 0.28
        color: Theme.danger
        border.width: 2
        border.color: Qt.rgba(1, 1, 1, 0.95)
        Text {
          anchors.centerIn: parent
          text: "−"
          color: "white"
          font.pixelSize: Math.round(parent.width * 0.72)
          font.bold: true
        }
        MouseArea {
          anchors.fill: parent
          anchors.margins: -4
          cursorShape: Qt.PointingHandCursor
          z: 61
          onClicked: DockApps.unpinEntry(modelData)
        }
      }

      Rectangle {
        visible: cell.showKeepBadge
        width: cell.badgeSize
        height: cell.badgeSize
        radius: width * 0.5
        z: 60
        x: cell.iconLeft + cell.iconVisual - width * 0.72
        y: cell.iconTop - height * 0.28
        color: Theme.accent
        border.width: 2
        border.color: Qt.rgba(1, 1, 1, 0.95)
        Text {
          anchors.centerIn: parent
          text: "+"
          color: "white"
          font.pixelSize: Math.round(parent.width * 0.62)
          font.bold: true
        }
        MouseArea {
          anchors.fill: parent
          anchors.margins: -4
          cursorShape: Qt.PointingHandCursor
          z: 61
          onClicked: DockApps.pinDesktopId(modelData.desktopId || modelData.id)
        }
      }

      // Running = soft disc; active/focused = short accent pill (readable at rest size)
      Rectangle {
        visible: !cell.isSep
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: -4
        width: active ? 8 : 4
        height: active ? 3 : 4
        radius: height / 2
        color: active ? Theme.accent
            : (Theme.light ? Qt.rgba(0.05, 0.05, 0.06, 0.50) : Qt.rgba(1, 1, 1, 0.78))
        opacity: shown ? (active ? 1 : 0.7) : 0
        z: 5
        border.width: active || !shown ? 0 : 1
        border.color: Theme.light ? Qt.rgba(1, 1, 1, 0.35) : Qt.rgba(0, 0, 0, 0.25)

        Behavior on width {
          NumberAnimation {
            duration: 120
            easing.type: Easing.OutCubic
          }
        }
        Behavior on height {
          NumberAnimation {
            duration: 120
            easing.type: Easing.OutCubic
          }
        }
        Behavior on opacity {
          NumberAnimation {
            duration: 140
            easing.type: Easing.OutCubic
          }
        }

        readonly property bool active: DockApps.isActive(modelData)
        readonly property bool shown: modelData.special === "launcher"
            ? ShellState.launcherOpen
            : DockApps.isRunning(modelData)
      }
    }
  }
}
