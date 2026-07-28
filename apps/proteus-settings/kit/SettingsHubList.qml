import Quickshell
import QtQuick
import QtQuick.Layouts
import "../shared"

// Apple-style grouped list — continuous rounded card, label-only rows.
ColumnLayout {
  id: root
  Layout.fillWidth: true
  Layout.maximumWidth: 320
  spacing: Theme.spaceLg

  property var items: []
  property var secondaryItems: []
  signal activated(string key)

  Rectangle {
    Layout.fillWidth: true
    implicitHeight: primaryCol.implicitHeight
    radius: Theme.radiusLg
    color: Theme.bgElevated
    clip: true

    ColumnLayout {
      id: primaryCol
      width: parent.width
      spacing: 0

      Repeater {
        model: root.items

        Item {
          required property var modelData
          required property int index
          Layout.fillWidth: true
          Layout.preferredHeight: 38

          Rectangle {
            anchors.fill: parent
            color: rowMa.containsMouse ? Theme.bgHover : "transparent"
          }

          Text {
            anchors.left: parent.left
            anchors.leftMargin: Theme.spaceMd
            anchors.verticalCenter: parent.verticalCenter
            text: modelData.label
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
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

          MouseArea {
            id: rowMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.activated(modelData.key)
          }
        }
      }
    }
  }

  Rectangle {
    visible: root.secondaryItems.length > 0
    Layout.fillWidth: true
    implicitHeight: secondaryCol.implicitHeight
    radius: Theme.radiusLg
    color: Theme.bgElevated
    clip: true

    ColumnLayout {
      id: secondaryCol
      width: parent.width
      spacing: 0

      Repeater {
        model: root.secondaryItems

        Item {
          required property var modelData
          required property int index
          Layout.fillWidth: true
          Layout.preferredHeight: 38

          Rectangle {
            anchors.fill: parent
            color: secMa.containsMouse ? Theme.bgHover : "transparent"
          }

          Text {
            anchors.left: parent.left
            anchors.leftMargin: Theme.spaceMd
            anchors.verticalCenter: parent.verticalCenter
            text: modelData.label
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
          }

          Rectangle {
            visible: index < root.secondaryItems.length - 1
            anchors.left: parent.left
            anchors.leftMargin: Theme.spaceMd
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: Theme.separator
          }

          MouseArea {
            id: secMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.activated(modelData.key)
          }
        }
      }
    }
  }
}
