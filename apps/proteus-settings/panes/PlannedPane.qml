import Quickshell
import QtQuick
import QtQuick.Layouts
import "../shared"

// Stub category for north-star IA — checklist tracks what still needs building.
ColumnLayout {
  id: root
  Layout.fillWidth: true
  Layout.maximumWidth: 420
  spacing: Theme.spaceMd

  property string summary: ""
  property string status: "planned" // planned | stub
  property var items: []

  readonly property string statusLabel: {
    if (status === "stub")
      return "Stub"
    if (status === "partial")
      return "Partial"
    return "Planned"
  }

  Text {
    visible: root.summary.length > 0
    Layout.fillWidth: true
    text: root.summary
    color: Theme.textDim
    font.family: Theme.fontFamily
    font.pixelSize: 13
    wrapMode: Text.WordWrap
  }

  Rectangle {
    Layout.fillWidth: true
    implicitHeight: listCol.implicitHeight
    radius: Theme.radiusLg
    color: Theme.bgElevated
    clip: true

    ColumnLayout {
      id: listCol
      width: parent.width
      spacing: 0

      Item {
        Layout.fillWidth: true
        Layout.preferredHeight: 36
        Text {
          anchors.left: parent.left
          anchors.leftMargin: Theme.spaceMd
          anchors.verticalCenter: parent.verticalCenter
          text: "Roadmap · " + root.statusLabel
          color: Theme.textMute
          font.family: Theme.fontFamily
          font.pixelSize: 12
        }
        Rectangle {
          anchors.left: parent.left
          anchors.leftMargin: Theme.spaceMd
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: 1
          color: Theme.separator
        }
      }

      Repeater {
        model: root.items

        Item {
          required property var modelData
          required property int index
          Layout.fillWidth: true
          Layout.preferredHeight: 44

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.spaceMd
            anchors.rightMargin: Theme.spaceMd
            spacing: Theme.spaceSm

            Text {
              text: modelData.done ? "✓" : "○"
              color: modelData.done ? Theme.accent : Theme.textMute
              font.family: Theme.fontFamily
              font.pixelSize: 14
              Layout.preferredWidth: 18
            }

            ColumnLayout {
              Layout.fillWidth: true
              spacing: 1
              Text {
                text: modelData.label
                color: modelData.done ? Theme.textDim : Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
              }
              Text {
                visible: !!(modelData.hint && String(modelData.hint).length)
                text: modelData.hint || ""
                color: Theme.textMute
                font.family: Theme.fontFamily
                font.pixelSize: 11
              }
            }
          }

          Rectangle {
            visible: index < root.items.length - 1
            anchors.left: parent.left
            anchors.leftMargin: Theme.spaceMd
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: Theme.separator
          }
        }
      }
    }
  }
}
