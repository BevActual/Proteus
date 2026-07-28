import QtQuick
import QtQuick.Layouts
import "../../shared"

Rectangle {
  id: root
  height: 48
  radius: 24
  color: Qt.rgba(28 / 255, 28 / 255, 30 / 255, 0.88)
  border.width: 1
  border.color: Qt.rgba(1, 1, 1, 0.12)

  signal changeWallpaper()
  signal addWidget()
  signal done()

  RowLayout {
    anchors.fill: parent
    anchors.leftMargin: 10
    anchors.rightMargin: 10
    spacing: 8

    Rectangle {
      Layout.preferredHeight: 32
      Layout.preferredWidth: wallpaperLabel.implicitWidth + 20
      radius: 16
      color: Qt.rgba(1, 1, 1, 0.1)
      Text {
        id: wallpaperLabel
        anchors.centerIn: parent
        text: "Wallpaper"
        color: "#f5f5f7"
        font.family: Theme.fontFamily
        font.pixelSize: 12
        font.weight: Font.Medium
      }
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.changeWallpaper()
      }
    }

    Rectangle {
      Layout.preferredHeight: 32
      Layout.preferredWidth: addLabel.implicitWidth + 20
      radius: 16
      color: Qt.rgba(1, 1, 1, 0.1)
      Text {
        id: addLabel
        anchors.centerIn: parent
        text: "Add Widget"
        color: "#f5f5f7"
        font.family: Theme.fontFamily
        font.pixelSize: 12
        font.weight: Font.Medium
      }
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.addWidget()
      }
    }

    Item {
      Layout.fillWidth: true
    }

    Rectangle {
      Layout.preferredHeight: 32
      Layout.preferredWidth: doneLabel.implicitWidth + 24
      radius: 16
      color: Theme.accent
      Text {
        id: doneLabel
        anchors.centerIn: parent
        text: "Done"
        color: "#fff"
        font.family: Theme.fontFamily
        font.pixelSize: 12
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
