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

  // Long-press reorder (macOS-like): middle pins only.
  property bool reorderMode: false
  property int reorderIndex: -1
  property real reorderGrabX: 0
  property real reorderItemX: 0
  property real reorderDragX: 0
  property real reorderDragY: 0
  property bool reorderRemoving: false
  property bool suppressClick: false
  readonly property real removeThreshold: shelfHeight * 0.85

  readonly property real rowWidth: count > 0
      ? count * iconSize + Math.max(0, count - 1) * spacing
      : 0

  readonly property int shelfHeight: iconSize + padTop + padBottom
  readonly property int magHeadroom: (maxIconSize - iconSize) + tipH + tipGap + 12
  // Match SquircleIcon continuous corners — not a stadium pill (was height/2).
  readonly property real plateRadius: shelfHeight * Theme.squircleCornerRatio

  implicitWidth: Math.round(rowWidth + padX * 2)
  implicitHeight: Math.round(shelfHeight + magHeadroom)

  function centerAt(index) {
    return padX + index * (iconSize + spacing) + iconSize * 0.5
  }

  function scaleAt(index) {
    if (reorderMode)
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
    if (reorderMode)
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
    Qt.callLater(() => {
      ctxMenu.x = Math.max(8, Math.min(x - ctxMenu.width * 0.5, root.width - ctxMenu.width - 8))
      ctxMenu.y = Math.max(4, y - ctxMenu.height - 8)
    })
  }

  function closePinMenu() {
    root.menuOpen = false
    root.menuIndex = -1
  }

  function beginReorder(index) {
    if (index < 0 || index >= items.length)
      return
    const entry = items[index]
    if (!DockApps.canReorder(entry))
      return
    root.closePinMenu()
    root.reorderMode = true
    root.reorderIndex = index
    root.reorderItemX = padX + index * (iconSize + spacing)
    root.reorderGrabX = root.mouseX
    root.reorderDragX = root.reorderItemX
    root.reorderDragY = 0
    root.reorderRemoving = false
    root.suppressClick = true
    root.tipIndex = -1
  }

  function endReorder(commit) {
    if (!reorderMode) {
      holdTimer.stop()
      return
    }
    const idx = reorderIndex
    const entry = (idx >= 0 && idx < items.length) ? items[idx] : null
    const removing = reorderRemoving && entry && DockApps.canUnpin(entry)
    const dragX = reorderDragX
    root.reorderMode = false
    root.reorderIndex = -1
    root.reorderRemoving = false
    root.reorderDragY = 0
    holdTimer.stop()

    if (!commit || !entry)
      return
    if (removing) {
      DockApps.unpinEntry(entry)
      return
    }
    const fromPin = DockApps.pinIdList().indexOf(DockApps.normalizeDesktopId(entry.desktopId || entry.id))
    if (fromPin < 0)
      return
    const insertAt = insertPinIndexForX(dragX + iconSize * 0.5)
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
    interval: 450
    repeat: false
    onTriggered: {
      if (root.pressIndex >= 0)
        root.beginReorder(root.pressIndex)
    }
  }

  MouseArea {
    id: dockMa
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: root.reorderMode ? Qt.ClosedHandCursor : Qt.PointingHandCursor
    z: 10
    onEntered: root.hovered = true
    onExited: {
      if (root.menuOpen || root.reorderMode)
        return
      root.hovered = false
      root.mouseX = -1000
      root.tipIndex = -1
    }
    onPositionChanged: mouse => {
      root.hovered = true
      root.setMouse(mouse.x)
      if (root.reorderMode) {
        root.reorderDragX = root.reorderItemX + (mouse.x - root.reorderGrabX)
        // Drag toward desktop (up from bottom shelf) to remove.
        const shelfTop = root.height - root.shelfHeight
        root.reorderDragY = Math.max(0, shelfTop - mouse.y)
        root.reorderRemoving = root.reorderDragY > root.removeThreshold
        root.tipIndex = -1
        return
      }
      root.tipIndex = root.indexAt(mouse.x)
      if (root.pressIndex >= 0 && Math.abs(mouse.x - root.reorderGrabX) > 8)
        holdTimer.stop()
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
      if (root.reorderMode)
        return
      const i = root.indexAt(mouse.x)
      if (i < 0)
        return
      if (mouse.button === Qt.RightButton) {
        root.openPinMenu(i, mouse.x, mouse.y)
        return
      }
      DockApps.focusOrLaunch(root.items[i])
    }
    onPressed: mouse => {
      root.setMouse(mouse.x)
      root.pressIndex = root.indexAt(mouse.x)
      root.reorderGrabX = mouse.x
      holdTimer.stop()
      if (mouse.button === Qt.LeftButton && root.pressIndex >= 0) {
        const e = root.items[root.pressIndex]
        if (DockApps.canReorder(e))
          holdTimer.restart()
      }
    }
    onReleased: mouse => {
      holdTimer.stop()
      if (root.reorderMode)
        root.endReorder(true)
      root.pressIndex = -1
    }
    onCanceled: {
      holdTimer.stop()
      if (root.reorderMode)
        root.endReorder(false)
      root.pressIndex = -1
    }
  }

  // Remove hint while dragging a pin off the shelf
  Text {
    z: 60
    visible: root.reorderMode && root.reorderRemoving
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: plate.top
    anchors.bottomMargin: 8
    text: "Remove"
    color: Qt.rgba(1, 0.35, 0.35, 0.95)
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSizeSm
    font.weight: Font.Medium
  }

  // Context menu — Keep in Dock / Remove from Dock (macOS Options pattern)
  Rectangle {
    id: ctxMenu
    visible: root.menuOpen
    z: 50
    width: Math.max(keepRow.implicitWidth, removeRow.implicitWidth) + 28
    height: (keepRow.visible ? 36 : 0) + (removeRow.visible ? 36 : 0)
    radius: 10
    color: Theme.light ? Qt.rgba(1, 1, 1, 0.96) : Qt.rgba(0.16, 0.16, 0.18, 0.96)
    border.width: 1
    border.color: Theme.light ? Qt.rgba(0, 0, 0, 0.10) : Qt.rgba(1, 1, 1, 0.12)

    Column {
      anchors.fill: parent
      anchors.margins: 0

      Item {
        id: keepRow
        width: parent.width
        height: 36
        visible: {
          const e = root.menuEntry()
          return e && DockApps.canKeepInDock(e)
        }

        Text {
          anchors.centerIn: parent
          text: "Keep in Dock"
          color: Theme.text
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSizeSm
        }
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            const e = root.menuEntry()
            if (e)
              DockApps.pinDesktopId(e.desktopId || e.id)
            root.closePinMenu()
          }
        }
      }

      Rectangle {
        width: parent.width
        height: 1
        visible: keepRow.visible && removeRow.visible
        color: Theme.separator
      }

      Item {
        id: removeRow
        width: parent.width
        height: 36
        visible: {
          const e = root.menuEntry()
          return e && DockApps.canUnpin(e)
        }

        Text {
          anchors.centerIn: parent
          text: "Remove from Dock"
          color: Theme.text
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSizeSm
        }
        MouseArea {
          anchors.fill: parent
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
      readonly property bool tipOn: root.tipIndex === index && !root.menuOpen && !root.reorderMode
      readonly property bool brandIcon: modelData.special === "launcher"
          || modelData.special === "settings"
          || modelData.icon === "proteus-launcher"
          || modelData.icon === "proteus-settings"
      readonly property bool isDragging: root.reorderMode && root.reorderIndex === index
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
        NumberAnimation {
          duration: 70
          easing.type: Easing.OutCubic
        }
      }
      Behavior on displayPress {
        NumberAnimation {
          duration: 90
          easing.type: Easing.OutCubic
        }
      }

      x: isDragging ? root.reorderDragX : restX
      opacity: isDragging && root.reorderRemoving ? 0.45 : 1
      width: root.iconSize
      height: root.iconSize + root.magHeadroom
      anchors.bottom: parent.bottom
      anchors.bottomMargin: root.padBottom
      z: isDragging ? 40 : (tipOn ? 20 : Math.round(10 + index + (displayS - root.restScale) * 40))
      clip: false

      // Soft jiggle cue while a sibling is being reordered; lift while dragging.
      transform: [
        Translate {
          y: isDragging ? -Math.min(root.reorderDragY, root.maxIconSize) : 0
        },
        Rotation {
          origin.x: cell.width * 0.5
          origin.y: cell.height * 0.7
          angle: (!isDragging && root.reorderMode && DockApps.canReorder(modelData))
              ? ((index % 2 === 0) ? -2.5 : 2.5)
              : 0
          Behavior on angle {
            NumberAnimation {
              duration: 120
            }
          }
        }
      ]

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

        transform: Scale {
          origin.x: glyph.width * 0.5
          origin.y: glyph.height
          xScale: cell.displayS * cell.displayPress
          yScale: cell.displayS * cell.displayPress
        }

        SquircleIcon {
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
