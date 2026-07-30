import Quickshell
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

  readonly property real rowWidth: count > 0
      ? count * iconSize + Math.max(0, count - 1) * spacing
      : 0

  readonly property int shelfHeight: iconSize + padTop + padBottom
  readonly property int magHeadroom: (maxIconSize - iconSize) + tipH + tipGap + 12
  readonly property real plateRadius: shelfHeight * Theme.squircleCornerRatio

  implicitWidth: Math.round(rowWidth + padX * 2)
  implicitHeight: Math.round(shelfHeight + magHeadroom)

  function centerAt(index) {
    return padX + index * (iconSize + spacing) + iconSize * 0.5
  }

  function scaleAt(index) {
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
      const left = padX + i * (iconSize + spacing)
      if (x >= left && x < left + iconSize)
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

  function openPinMenu(index, x, y) {
    if (dragging)
      return
    if (index < 0 || index >= items.length)
      return
    const entry = items[index]
    const keep = DockApps.canKeepInDock(entry)
    const remove = DockApps.canUnpin(entry)
    if (!keep && !remove)
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
    holdTimer.stop()
    root.dragging = true
    root.dragIndex = index
    root.dragItemX = padX + index * (iconSize + spacing)
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

  Rectangle {
    id: plate
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    width: parent.width
    height: root.shelfHeight
    radius: root.plateRadius
    color: Theme.dockPlateFill
    antialiasing: true
    // No child specular — Qt clip on radius does not mask children to the
    // curve, which left a hard straight highlight across the top edge.
    border.width: Theme.chromeClear ? 0 : 1
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

  MouseArea {
    id: dockMa
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: root.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
    z: 10
    onEntered: root.hovered = true
    onExited: {
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
      root.tipIndex = root.editMode ? -1 : root.indexAt(mouse.x)
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
      if (root.editMode) {
        if (i < 0)
          root.exitEditMode()
        return
      }
      if (i < 0)
        return
      DockApps.focusOrLaunch(root.items[i])
    }
    onPressed: mouse => {
      root.setMouse(mouse.x)
      root.pressIndex = root.indexAt(mouse.x)
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

  // Drag feedback label (macOS Remove / Keep)
  Text {
    z: 60
    visible: root.dragging
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: plate.top
    anchors.bottomMargin: 8
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
    color: root.dragRemoving ? Qt.rgba(1, 0.35, 0.35, 0.95) : Qt.rgba(0.85, 0.95, 0.85, 0.95)
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSizeSm
    font.weight: Font.Medium
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

  // Context menu — Keep / Remove (one opaque plate; width from labels)
  Rectangle {
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
    width: Math.max(
          showKeep ? keepMeasure.implicitWidth : 0,
          showRemove ? removeMeasure.implicitWidth : 0,
          120
        ) + padX * 2
    height: padY * 2
        + (showKeep ? rowH : 0)
        + (showRemove ? rowH : 0)
        + (showKeep && showRemove ? 1 : 0)
    radius: Theme.radiusMd
    color: Theme.light ? Qt.rgba(0.98, 0.98, 0.99, 0.97) : Qt.rgba(0.17, 0.17, 0.19, 0.97)
    border.width: 1
    border.color: Theme.chromeHairline

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
          color: Theme.accent
          opacity: keepMa.containsMouse ? 0.18 : 0
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
          color: Theme.accent
          opacity: removeMa.containsMouse ? 0.18 : 0
        }
        Text {
          anchors.centerIn: parent
          text: removeMeasure.text
          color: Theme.text
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
    }
  }

  Repeater {
    model: root.items

    Item {
      id: cell
      required property var modelData
      required property int index

      readonly property real s: root.scaleAt(index)
      property real displayS: s
      property real displayPress: 1
      readonly property real rise: root.maxIconSize * (displayS - root.restScale)
      readonly property bool tipOn: root.tipIndex === index && !root.menuOpen && !root.editMode && !root.dragging
      readonly property bool brandIcon: modelData.special === "launcher"
          || modelData.special === "settings"
          || modelData.icon === "proteus-launcher"
          || modelData.icon === "proteus-settings"
      readonly property bool isDragging: root.dragging && root.dragIndex === index
      readonly property bool showMinus: root.editMode && !isDragging && DockApps.canUnpin(modelData)
      readonly property bool showKeepBadge: root.editMode && !isDragging && DockApps.canKeepInDock(modelData)
      readonly property real restX: root.padX + index * (root.iconSize + root.spacing)

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
      width: root.iconSize
      height: root.iconSize + root.magHeadroom
      anchors.bottom: parent.bottom
      anchors.bottomMargin: root.padBottom
      z: isDragging ? 40 : (tipOn ? 20 : Math.round(10 + index + (displayS - root.restScale) * 40))
      clip: false

      // Fixed badge geometry (rest icon size; outside mag Scale)
      readonly property real badgeSize: Math.round(root.iconSize * 0.38)
      readonly property real iconVisual: root.iconSize * Theme.iconFrameScale
      readonly property real iconLeft: (width - iconVisual) * 0.5
      readonly property real iconTop: height - iconVisual

      transform: Translate {
        y: isDragging ? -Math.min(root.dragLift, root.maxIconSize) : 0
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
        color: Qt.rgba(0.72, 0.18, 0.18, 0.98)
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
