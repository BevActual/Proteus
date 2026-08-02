import Quickshell
import Quickshell.Hyprland
import QtQuick
import "../../shared"

// Compact Space strip — quiet Mac-adjacent pills in the menu bar.
// Logical Spaces 1–10 map to per-monitor Hyprland bands via proteus-workspace
// (physical = logical + monitorIndex * 10). Synced mode switches every display;
// perDisplay (or Super+Ctrl) switches this bar's monitor only.
Item {
  id: root

  // Quickshell screen for this TopBar instance (from DesktopShell PanelWindow).
  property var screen: null

  readonly property int cell: Math.max(18, Theme.barHeight - 14)
  readonly property int maxCount: 10
  readonly property int stride: 10

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

  implicitHeight: cell
  implicitWidth: count * cell + (showPlus ? cell : 0) + 2

  function go(id) {
    const target = Math.max(1, Math.min(maxCount, Math.round(id)))
    const perDisplay = Config.workspaceMode === "perDisplay"
    let cmd = "proteus-workspace goto " + target
    if (perDisplay && monitorName.length)
      cmd += " --local --monitor " + monitorName
    Hyprland.dispatch("exec " + cmd)
  }

  function step(delta) {
    const perDisplay = Config.workspaceMode === "perDisplay"
    let cmd = "proteus-workspace " + (delta < 0 ? "prev" : "next")
    if (perDisplay && monitorName.length)
      cmd += " --local --monitor " + monitorName
    Hyprland.dispatch("exec " + cmd)
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

  Rectangle {
    anchors.fill: parent
    radius: height / 2
    color: Theme.light ? Qt.rgba(0, 0, 0, 0.05) : Qt.rgba(1, 1, 1, 0.08)
    visible: !Theme.chromeClear
  }

  WheelHandler {
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    onWheel: event => {
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
    x: 1 + (Math.max(1, Math.min(root.count, root.focusedId)) - 1) * root.cell

    Behavior on x {
      NumberAnimation {
        duration: 180
        easing.type: Easing.OutCubic
      }
    }
  }

  Row {
    anchors.left: parent.left
    anchors.leftMargin: 1
    anchors.verticalCenter: parent.verticalCenter
    spacing: 0

    Repeater {
      model: root.count

      Item {
        id: cell
        required property int index
        readonly property int wsId: index + 1
        readonly property bool focused: root.focusedId === wsId
        readonly property bool occupied: root.occupiedLogical(wsId)

        width: root.cell
        height: root.cell

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.verticalCenter: parent.verticalCenter
          anchors.verticalCenterOffset: cell.occupied && !cell.focused ? -1 : 0
          text: cell.wsId
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
          color: pillMa.containsMouse && !cell.focused
              ? (Theme.light ? Qt.rgba(0, 0, 0, 0.06) : Qt.rgba(1, 1, 1, 0.08))
              : "transparent"
          z: -1
        }

        MouseArea {
          id: pillMa
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.go(cell.wsId)
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
        cursorShape: Qt.PointingHandCursor
        onClicked: root.go(root.count + 1)
      }
    }
  }
}
