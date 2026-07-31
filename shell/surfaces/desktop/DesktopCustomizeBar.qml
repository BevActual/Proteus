import QtQuick
import QtQuick.Layouts
import "../../shared"

Rectangle {
  id: root
  height: 48
  radius: Theme.radiusPill
  color: Theme.elevatedFill
  border.width: 1
  border.color: Theme.chromeBorder

  signal addWidget()
  signal done()
  signal toggleSnapGrid()

  property bool snapToGrid: false

  RowLayout {
    anchors.fill: parent
    anchors.leftMargin: Theme.spaceSm + 2
    anchors.rightMargin: Theme.spaceSm + 2
    spacing: Theme.spaceSm

    Text {
      text: "Customize"
      color: Theme.textMute
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSizeSm
      Layout.leftMargin: Theme.spaceXs + 2
    }

    Rectangle {
      Layout.preferredHeight: 32
      Layout.preferredWidth: addLabel.implicitWidth + 20
      radius: Theme.radiusPill - 8
      color: Theme.bgHover
      Text {
        id: addLabel
        anchors.centerIn: parent
        text: "Add Widget"
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSm
        font.weight: Font.Medium
      }
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.addWidget()
      }
    }

    Rectangle {
      Layout.preferredHeight: 32
      Layout.preferredWidth: snapLabel.implicitWidth + 20
      radius: Theme.radiusPill - 8
      color: root.snapToGrid ? Theme.accentSoft : Theme.bgHover
      border.width: root.snapToGrid ? 1 : 0
      border.color: Theme.accent
      Text {
        id: snapLabel
        anchors.centerIn: parent
        text: root.snapToGrid ? "Snap on" : "Snap to Grid"
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSm
        font.weight: Font.Medium
      }
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggleSnapGrid()
      }
    }

    Item {
      Layout.fillWidth: true
    }

    Rectangle {
      Layout.preferredHeight: 32
      Layout.preferredWidth: doneLabel.implicitWidth + 24
      radius: Theme.radiusPill - 8
      color: Theme.accent
      Text {
        id: doneLabel
        anchors.centerIn: parent
        text: "Done"
        color: "#ffffff"
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSm
        font.weight: Font.Medium
      }
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.done()
      }
    }
  }
}
