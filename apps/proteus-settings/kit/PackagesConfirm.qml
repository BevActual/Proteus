import QtQuick
import QtQuick.Layouts
import "../shared"

// Propose → confirm strip. Parent sets title/detail and handles signals.
Rectangle {
  id: root
  property string title: ""
  property string detail: ""
  property string footnote: "Authentication required (polkit). Confirmed here first."
  property bool open: false

  signal cancelled
  signal confirmed

  visible: open
  Layout.fillWidth: true
  Layout.maximumWidth: 520
  Layout.preferredHeight: open ? col.implicitHeight + 24 : 0
  radius: Theme.radiusMd
  color: Theme.bgElevated
  border.width: 1
  border.color: Theme.accent
  clip: true

  ColumnLayout {
    id: col
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: Theme.spaceMd
    spacing: 10

    Text {
      Layout.fillWidth: true
      text: root.title
      color: Theme.text
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSize
      font.bold: true
    }

    Text {
      Layout.fillWidth: true
      visible: root.detail.length > 0
      text: root.detail
      color: Theme.textDim
      font.family: Theme.fontFamily
      font.pixelSize: 12
      wrapMode: Text.WordWrap
    }

    Text {
      Layout.fillWidth: true
      visible: root.footnote.length > 0
      text: root.footnote
      color: Theme.textMute
      font.family: Theme.fontFamily
      font.pixelSize: 11
      wrapMode: Text.WordWrap
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Theme.spaceSm

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 36
        radius: Theme.radius
        color: Theme.bgPanel
        border.width: 1
        border.color: Theme.border
        Text {
          anchors.centerIn: parent
          text: "Cancel"
          color: Theme.text
          font.family: Theme.fontFamily
          font.pixelSize: 12
        }
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.cancelled()
        }
      }

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 36
        radius: Theme.radius
        color: Theme.accentSoft
        border.width: 1
        border.color: Theme.accent
        Text {
          anchors.centerIn: parent
          text: "Continue"
          color: Theme.text
          font.family: Theme.fontFamily
          font.pixelSize: 12
          font.bold: true
        }
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.confirmed()
        }
      }
    }
  }
}
