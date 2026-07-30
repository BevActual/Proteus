import Quickshell
import QtQuick
import QtQuick.Layouts
import "../shared"

// Labeled color preset grid + ColorGraphPicker (optional debounce for wallpaper paths).
SettingsGroup {
  id: root
  title: "Color"

  property var model: []
  property string selectedColor: ""
  property bool selectionActive: true
  property string graphHex: ""
  property int debounceMs: 80

  signal presetClicked(string color)
  signal customHexEdited(string hex)
  signal customHexCommitted(string hex)

  Item {
    Layout.fillWidth: true
    Layout.preferredHeight: colorFlow.implicitHeight + Theme.spaceMd * 2
    Flow {
      id: colorFlow
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Theme.spaceMd
      spacing: Theme.spaceSm
      Repeater {
        model: root.model
        Column {
          required property var modelData
          spacing: 4
          width: 48
          Rectangle {
            width: 36
            height: 36
            radius: 18
            anchors.horizontalCenter: parent.horizontalCenter
            color: modelData.color
            border.width: root.selectionActive && root.selectedColor === modelData.color ? 3 : 1
            border.color: root.selectedColor === modelData.color ? Theme.text : Theme.separator
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.presetClicked(modelData.color)
            }
          }
          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: modelData.label
            color: Theme.textMute
            font.family: Theme.fontFamily
            font.pixelSize: 10
            elide: Text.ElideRight
          }
        }
      }
    }
  }

  Rectangle {
    Layout.fillWidth: true
    Layout.preferredHeight: 1
    color: Theme.separator
    opacity: 0.6
  }

  Item {
    Layout.fillWidth: true
    Layout.preferredHeight: graph.implicitHeight + Theme.spaceMd
    ColorGraphPicker {
      id: graph
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Theme.spaceMd
      hex: root.graphHex
      commitDebounceMs: root.debounceMs
      onHexEdited: h => root.customHexEdited(h)
      onHexCommitted: h => root.customHexCommitted(h)
    }
  }
}
