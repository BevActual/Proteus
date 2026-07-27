import Quickshell
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts
import "../../shared"

Item {
  id: root
  implicitHeight: Theme.barHeight - 10
  implicitWidth: row.implicitWidth

  Row {
    id: row
    anchors.verticalCenter: parent.verticalCenter
    spacing: Theme.spaceXs

    Repeater {
      model: 6

      Rectangle {
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

        width: 28
        height: 24
        radius: Theme.radiusSm
        color: focused ? Theme.accent : (occupied ? Theme.bgHover : "transparent")
        border.width: focused ? 0 : 1
        border.color: occupied ? Theme.border : "transparent"

        Text {
          anchors.centerIn: parent
          text: parent.wsId
          color: parent.focused ? Theme.text : Theme.textDim
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSizeSm
          font.bold: parent.focused
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (parent.ws)
              parent.ws.activate()
            else
              Hyprland.dispatch("workspace " + parent.wsId)
          }
        }

        Behavior on color {
          ColorAnimation {
            duration: 120
          }
        }
      }
    }
  }
}
