import Quickshell
import Quickshell.Hyprland
import QtQuick
import "../../shared"

// Compact workspace strip — quiet Mac-adjacent pills in the menu bar.
Item {
  id: root

  readonly property int cell: Math.max(18, Theme.barHeight - 14)
  readonly property int count: 6
  readonly property int focusedId: {
    const list = Hyprland.workspaces.values
    for (let i = 0; i < list.length; i++) {
      if (list[i].focused)
        return list[i].id
    }
    return 1
  }

  implicitHeight: cell
  implicitWidth: count * cell + 2

  Rectangle {
    anchors.fill: parent
    radius: height / 2
    color: Theme.light ? Qt.rgba(0, 0, 0, 0.05) : Qt.rgba(1, 1, 1, 0.08)
    visible: !Theme.chromeClear
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
    anchors.centerIn: parent
    spacing: 0

    Repeater {
      model: root.count

      Item {
        id: cell
        required property int index
        readonly property int wsId: index + 1
        readonly property var ws: {
          const list = Hyprland.workspaces.values
          for (let i = 0; i < list.length; i++) {
            if (list[i].id === wsId)
              return list[i]
          }
          return null
        }
        readonly property bool focused: ws ? ws.focused : false
        readonly property bool occupied: ws !== null

        width: root.cell
        height: root.cell

        Text {
          anchors.centerIn: parent
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
          onClicked: {
            if (cell.ws)
              cell.ws.activate()
            else
              Hyprland.dispatch("workspace " + cell.wsId)
          }
        }
      }
    }
  }
}
