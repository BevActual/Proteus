import Quickshell
import QtQuick
import QtQuick.Layouts
import "../shared"

// Apple-style segmented control.
// Height must be concrete: Layout.preferredHeight alone is ignored when this
// control is parented with anchors (Appearance Chrome/Icons used that pattern).
Rectangle {
  id: root
  Layout.fillWidth: true
  Layout.preferredHeight: 32
  implicitHeight: 32
  height: 32
  radius: Theme.radiusMd
  color: Theme.bgHover
  clip: true

  property var options: []
  property string selected: ""
  signal activated(string id)

  Row {
    id: row
    anchors.fill: parent
    anchors.margins: 2
    spacing: 2

    Repeater {
      model: root.options

      Rectangle {
        required property var modelData
        width: Math.max(48, (row.width - Math.max(0, root.options.length - 1) * 2) / Math.max(1, root.options.length))
        height: row.height
        radius: Theme.radiusSm
        color: root.selected === modelData.id ? Theme.bgElevated : "transparent"

        Text {
          anchors.centerIn: parent
          text: modelData.label
          color: root.selected === modelData.id ? Theme.text : Theme.textDim
          font.family: Theme.fontFamily
          font.pixelSize: 12
          font.bold: root.selected === modelData.id
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.activated(modelData.id)
        }
      }
    }
  }
}
