import Quickshell
import Quickshell.Hyprland
import QtQuick
import "../../shared"

// Compact Space strip — quiet Mac-adjacent pills in the menu bar.
// Logical Spaces 1–10 map to per-monitor Hyprland bands via proteus-workspace
// (physical = logical + monitorIndex * 10). Synced mode switches every display;
// perDisplay (or Super+Ctrl) switches this bar's monitor only.
// Strip visual order: Config.workspaceOrder (Super+N stays logical SoT).
// Scratchpad pill (fixed) + custom special pills (specialWorkspaces, cap =
// SpacesSpecials.maxCustom · Super+Alt+1–8 via special-*-index).
Item {
  id: root

  // Quickshell screen for this TopBar instance (from DesktopShell PanelWindow).
  property var screen: null

  readonly property int cell: Math.max(18, Theme.barHeight - 14)
  readonly property int maxCount: 10
  readonly property int stride: 10
  readonly property string scratchName: "special:scratch"
  readonly property int maxStripSpecials: SpacesSpecials.maxCustom

  readonly property var customSpecials: {
    const _r = SpacesSpecials.rev
    return SpacesSpecials.names().slice(0, root.maxStripSpecials)
  }

  readonly property var hyprMonitor: screen ? Hyprland.monitorFor(screen) : null
  readonly property string monitorName: hyprMonitor ? String(hyprMonitor.name || "") : ""

  readonly property int monitorIndex: {
    const mon = hyprMonitor
    if (!mon)
      return 0
    const list = Hyprland.monitors.values
    let idx = 0
    const mid = mon.id || 0
    for (let i = 0; i < list.length; i++) {
      if ((list[i].id || 0) < mid)
        idx++
    }
    return idx
  }

  readonly property int bandBase: monitorIndex * stride

  function logicalOf(physical) {
    const id = Math.round(physical)
    if (id < 1)
      return 1
    return ((id - 1) % stride) + 1
  }

  readonly property int focusedId: {
    const mon = hyprMonitor
    if (mon && mon.activeWorkspace)
      return logicalOf(mon.activeWorkspace.id)
    const list = Hyprland.workspaces.values
    for (let i = 0; i < list.length; i++) {
      if (list[i].focused)
        return logicalOf(list[i].id)
    }
    return 1
  }

  readonly property int highestLogical: {
    const list = Hyprland.workspaces.values
    let hi = 0
    const synced = Config.workspaceMode !== "perDisplay"
    for (let i = 0; i < list.length; i++) {
      const id = list[i].id
      if (id < 1)
        continue
      if (!synced) {
        if (id <= bandBase || id > bandBase + stride)
          continue
      }
      const logical = logicalOf(id)
      if (logical > hi)
        hi = logical
    }
    return hi
  }

  // At least 4 pills; extend to the highest live logical Space (capped at 10).
  readonly property int count: {
    const base = Math.max(4, highestLogical, focusedId)
    if (focusedId > maxCount)
      return focusedId
    return Math.min(maxCount, base)
  }
  readonly property bool showPlus: count < maxCount
  readonly property bool showScratch: true

  function isScratchWorkspace(ws) {
    if (!ws)
      return false
    const name = String(ws.name || "").toLowerCase()
    if (name === "special:scratch" || name === "scratch")
      return true
    if (name.indexOf("special:scratch") === 0)
      return true
    return false
  }

  readonly property bool scratchActive: {
    const list = Hyprland.workspaces.values
    for (let i = 0; i < list.length; i++) {
      if (root.isScratchWorkspace(list[i]) && list[i].focused)
        return true
    }
    return false
  }

  readonly property bool scratchOccupied: {
    const tops = Hyprland.toplevels.values
    for (let i = 0; i < tops.length; i++) {
      if (root.isScratchWorkspace(tops[i].workspace))
        return true
    }
    // Fallback: special workspace may exist without focused toplevels yet.
    const list = Hyprland.workspaces.values
    for (let j = 0; j < list.length; j++) {
      const w = list[j]
      if (!root.isScratchWorkspace(w))
        continue
      const n = w.lastIpcObject && w.lastIpcObject.windows !== undefined
          ? Number(w.lastIpcObject.windows)
          : -1
      if (n > 0)
        return true
    }
    return false
  }

  // Visual strip: first `count` entries of workspaceOrder permutation.
  readonly property var stripLogicals: {
    const _n = Config.workspaceNames
    const _o = Config.workspaceOrder
    const full = Config.workspaceOrderList()
    return full.slice(0, root.count)
  }

  function stripIndexOf(logical) {
    const ord = root.stripLogicals
    const want = Math.round(Number(logical) || 0)
    for (let i = 0; i < ord.length; i++) {
      if (Math.round(Number(ord[i])) === want)
        return i
    }
    return Math.max(0, Math.min(ord.length - 1, want - 1))
  }

  readonly property int focusedStripIndex: stripIndexOf(focusedId)

  property bool dragging: false
  property int dragFrom: -1
  property int dragOver: -1
  property real pressX: 0
  property real pressY: 0
  readonly property real dragThreshold: 6

  implicitHeight: cell
  implicitWidth: count * cell + (showScratch ? cell : 0)
      + customSpecials.length * cell + (showPlus ? cell : 0) + 2

  function go(id) {
    const target = Math.max(1, Math.min(maxCount, Math.round(id)))
    const perDisplay = Config.workspaceMode === "perDisplay"
    let cmd = "proteus-workspace goto " + target
    if (perDisplay && monitorName.length)
      cmd += " --local --monitor " + monitorName
    Hyprland.dispatch("exec " + cmd)
  }

  function toggleScratch() {
    Hyprland.dispatch("exec proteus-workspace scratch-toggle")
  }

  function isNamedSpecial(ws, name) {
    if (!ws || !name)
      return false
    const n = String(ws.name || "").toLowerCase()
    const want = String(name).toLowerCase()
    return n === want || n === ("special:" + want) || n.indexOf("special:" + want) === 0
  }

  function specialActive(name) {
    const list = Hyprland.workspaces.values
    for (let i = 0; i < list.length; i++) {
      if (root.isNamedSpecial(list[i], name) && list[i].focused)
        return true
    }
    return false
  }

  function specialOccupied(name) {
    const tops = Hyprland.toplevels.values
    for (let i = 0; i < tops.length; i++) {
      if (root.isNamedSpecial(tops[i].workspace, name))
        return true
    }
    const list = Hyprland.workspaces.values
    for (let j = 0; j < list.length; j++) {
      const w = list[j]
      if (!root.isNamedSpecial(w, name))
        continue
      const n = w.lastIpcObject && w.lastIpcObject.windows !== undefined
          ? Number(w.lastIpcObject.windows)
          : -1
      if (n > 0)
        return true
    }
    return false
  }

  function toggleSpecial(name) {
    const s = SpacesSpecials.slugify(name)
    if (!s.length)
      return
    Hyprland.dispatch("exec proteus-workspace special-toggle " + s)
  }

  function specialGlyph(name) {
    const s = String(name || "")
    if (!s.length)
      return "·"
    if (s.length <= 2)
      return s
    return s.slice(0, 2)
  }

  function step(delta) {
    const ord = root.stripLogicals
    if (!ord.length) {
      const perDisplay = Config.workspaceMode === "perDisplay"
      let cmd = "proteus-workspace " + (delta < 0 ? "prev" : "next")
      if (perDisplay && monitorName.length)
        cmd += " --local --monitor " + monitorName
      Hyprland.dispatch("exec " + cmd)
      return
    }
    let i = root.focusedStripIndex + (delta < 0 ? -1 : 1)
    i = Math.max(0, Math.min(ord.length - 1, i))
    root.go(ord[i])
  }

  function occupiedLogical(logical) {
    const tops = Hyprland.toplevels.values
    const synced = Config.workspaceMode !== "perDisplay"
    for (let i = 0; i < tops.length; i++) {
      const w = tops[i].workspace
      if (!w || w.id < 1)
        continue
      if (logicalOf(w.id) !== logical)
        continue
      if (synced)
        return true
      if (w.id > bandBase && w.id <= bandBase + stride)
        return true
    }
    return false
  }

  function stripIndexAt(x) {
    const local = Math.max(0, x - 1)
    const idx = Math.floor(local / root.cell)
    return Math.max(0, Math.min(root.count - 1, idx))
  }

  Rectangle {
    anchors.fill: parent
    radius: height / 2
    color: Theme.light ? Qt.rgba(0, 0, 0, 0.05) : Qt.rgba(1, 1, 1, 0.08)
    visible: !Theme.chromeClear
  }

  WheelHandler {
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    onWheel: event => {
      if (root.dragging)
        return
      const d = event.angleDelta.y
      if (d > 0)
        root.step(-1)
      else if (d < 0)
        root.step(1)
    }
  }

  Rectangle {
    id: focusPill
    width: root.cell - 2
    height: root.cell - 2
    radius: height / 2
    color: Theme.chromeAccentSoft
    y: 1
    x: 1 + Math.max(0, root.focusedStripIndex) * root.cell
    visible: !root.dragging

    Behavior on x {
      NumberAnimation {
        duration: 180
        easing.type: Easing.OutCubic
      }
    }
  }

  Row {
    id: stripRow
    anchors.left: parent.left
    anchors.leftMargin: 1
    anchors.verticalCenter: parent.verticalCenter
    spacing: 0

    Repeater {
      model: root.stripLogicals

      Item {
        id: cell
        required property int index
        required property var modelData
        readonly property int wsId: Math.round(Number(modelData) || (index + 1))
        readonly property bool focused: root.focusedId === wsId
        readonly property bool occupied: root.occupiedLogical(wsId)
        readonly property bool isDragSource: root.dragging && root.dragFrom === index
        readonly property bool isDropTarget: root.dragging && root.dragOver === index && root.dragFrom !== index

        width: root.cell
        height: root.cell
        opacity: cell.isDragSource ? 0.45 : 1
        z: cell.isDragSource ? 2 : 0

        Rectangle {
          anchors.fill: parent
          anchors.margins: 1
          radius: height / 2
          color: cell.isDropTarget ? Theme.chromeAccentSoft : "transparent"
          border.width: cell.isDropTarget ? 1 : 0
          border.color: Theme.accent
          z: -2
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.verticalCenter: parent.verticalCenter
          anchors.verticalCenterOffset: cell.occupied && !cell.focused ? -1 : 0
          text: {
            const _r = SpacesNames.rev
            return SpacesNames.displayForLogical(cell.wsId)
          }
          color: cell.focused
              ? Theme.accent
              : (cell.occupied ? Theme.textDim : Theme.textMute)
          font.family: Theme.fontFamily
          font.pixelSize: Math.max(10, Theme.fontSizeSm - 1)
          font.weight: cell.focused ? Font.DemiBold : Font.Normal
          opacity: cell.focused ? 1 : (cell.occupied ? 0.85 : 0.4)
        }

        Rectangle {
          visible: cell.occupied && !cell.focused
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          anchors.bottomMargin: 3
          width: 3
          height: 3
          radius: 1.5
          color: Theme.textDim
          opacity: 0.8
        }

        Rectangle {
          anchors.fill: parent
          anchors.margins: 1
          radius: height / 2
          color: pillMa.containsMouse && !cell.focused && !root.dragging
              ? (Theme.light ? Qt.rgba(0, 0, 0, 0.06) : Qt.rgba(1, 1, 1, 0.08))
              : "transparent"
          z: -1
        }

        MouseArea {
          id: pillMa
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: root.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
          preventStealing: root.dragging
          onPressed: mouse => {
            root.pressX = mouse.x
            root.pressY = mouse.y
            root.dragFrom = cell.index
            root.dragOver = cell.index
          }
          onPositionChanged: mouse => {
            if (!pressed)
              return
            const dx = mouse.x - root.pressX
            const dy = mouse.y - root.pressY
            if (!root.dragging) {
              if (Math.sqrt(dx * dx + dy * dy) < root.dragThreshold)
                return
              root.dragging = true
            }
            const g = mapToItem(root, mouse.x, mouse.y)
            root.dragOver = root.stripIndexAt(g.x)
          }
          onReleased: {
            if (root.dragging && root.dragFrom >= 0 && root.dragOver >= 0
                && root.dragFrom !== root.dragOver) {
              Config.reorderWorkspaceStrip(root.dragFrom, root.dragOver)
            } else if (!root.dragging) {
              root.go(cell.wsId)
            }
            root.dragging = false
            root.dragFrom = -1
            root.dragOver = -1
          }
          onCanceled: {
            root.dragging = false
            root.dragFrom = -1
            root.dragOver = -1
          }
        }
      }
    }

    Item {
      id: scratchCell
      visible: root.showScratch
      width: root.cell
      height: root.cell

      Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: height / 2
        color: root.scratchActive ? Theme.chromeAccentSoft : "transparent"
        z: -2
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: root.scratchOccupied && !root.scratchActive ? -1 : 0
        text: "◇"
        color: root.scratchActive
            ? Theme.accent
            : (root.scratchOccupied ? Theme.textDim : Theme.textMute)
        font.family: Theme.fontFamily
        font.pixelSize: Math.max(10, Theme.fontSizeSm - 1)
        font.weight: root.scratchActive ? Font.DemiBold : Font.Normal
        opacity: root.scratchActive ? 1 : (root.scratchOccupied ? 0.85 : 0.45)
      }

      Rectangle {
        visible: root.scratchOccupied && !root.scratchActive
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 3
        width: 3
        height: 3
        radius: 1.5
        color: Theme.textDim
        opacity: 0.8
      }

      Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: height / 2
        color: scratchMa.containsMouse && !root.scratchActive && !root.dragging
            ? (Theme.light ? Qt.rgba(0, 0, 0, 0.06) : Qt.rgba(1, 1, 1, 0.08))
            : "transparent"
        z: -1
      }

      MouseArea {
        id: scratchMa
        anchors.fill: parent
        hoverEnabled: true
        enabled: !root.dragging
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggleScratch()
      }
    }

    Repeater {
      model: root.customSpecials

      Item {
        id: specialCell
        required property string modelData
        required property int index
        readonly property bool active: root.specialActive(modelData)
        readonly property bool occupied: root.specialOccupied(modelData)
        width: root.cell
        height: root.cell

        Rectangle {
          anchors.fill: parent
          anchors.margins: 1
          radius: height / 2
          color: specialCell.active ? Theme.chromeAccentSoft : "transparent"
          z: -2
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.verticalCenter: parent.verticalCenter
          anchors.verticalCenterOffset: specialCell.occupied && !specialCell.active ? -1 : 0
          text: root.specialGlyph(modelData)
          color: specialCell.active
              ? Theme.accent
              : (specialCell.occupied ? Theme.textDim : Theme.textMute)
          font.family: Theme.fontFamily
          font.pixelSize: Math.max(9, Theme.fontSizeSm - 2)
          font.weight: specialCell.active ? Font.DemiBold : Font.Normal
          opacity: specialCell.active ? 1 : (specialCell.occupied ? 0.85 : 0.5)
        }

        Rectangle {
          visible: specialCell.occupied && !specialCell.active
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          anchors.bottomMargin: 3
          width: 3
          height: 3
          radius: 1.5
          color: Theme.textDim
          opacity: 0.8
        }

        Rectangle {
          anchors.fill: parent
          anchors.margins: 1
          radius: height / 2
          color: specialMa.containsMouse && !specialCell.active && !root.dragging
              ? (Theme.light ? Qt.rgba(0, 0, 0, 0.06) : Qt.rgba(1, 1, 1, 0.08))
              : "transparent"
          z: -1
        }

        MouseArea {
          id: specialMa
          anchors.fill: parent
          hoverEnabled: true
          enabled: !root.dragging
          cursorShape: Qt.PointingHandCursor
          onClicked: root.toggleSpecial(modelData)
        }
      }
    }

    Item {
      visible: root.showPlus
      width: root.cell
      height: root.cell

      Text {
        anchors.centerIn: parent
        text: "+"
        color: plusMa.containsMouse ? Theme.text : Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSm
        opacity: plusMa.containsMouse ? 1 : 0.5
      }

      Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: height / 2
        color: plusMa.containsMouse
            ? (Theme.light ? Qt.rgba(0, 0, 0, 0.06) : Qt.rgba(1, 1, 1, 0.08))
            : "transparent"
        z: -1
      }

      MouseArea {
        id: plusMa
        anchors.fill: parent
        hoverEnabled: true
        enabled: !root.dragging
        cursorShape: Qt.PointingHandCursor
        onClicked: root.go(root.count + 1)
      }
    }
  }
}
