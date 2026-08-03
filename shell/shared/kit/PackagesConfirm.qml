import QtQuick
import QtQuick.Layouts
import ".."

// Propose → confirm strip. Parent sets title/detail and handles signals.
Rectangle {
  id: root
  property string title: ""
  property string detail: ""
  property string footnote: "Authentication required (polkit). Confirmed here first."
  property string cancelLabel: "Cancel"
  property string confirmLabel: "Continue"
  property bool open: false

  signal cancelled
  signal confirmed

  visible: open
  Layout.fillWidth: true
  Layout.maximumWidth: 520
  Layout.preferredHeight: open ? col.implicitHeight + Theme.spaceMd * 2 : 0
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
    spacing: Theme.spaceSm

    Text {
      Layout.fillWidth: true
      text: root.title
      color: Theme.text
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSize
      font.weight: Font.DemiBold
      wrapMode: Text.WordWrap
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
      Layout.topMargin: 2
      spacing: Theme.spaceSm

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 34
        radius: Theme.radiusSm
        color: cancelMa.containsMouse ? Theme.bgHover : Theme.bgPanel
        border.width: 1
        border.color: Theme.border
        Text {
          anchors.centerIn: parent
          text: root.cancelLabel
          color: Theme.text
          font.family: Theme.fontFamily
          font.pixelSize: 12
        }
        MouseArea {
          id: cancelMa
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.cancelled()
        }
      }

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 34
        radius: Theme.radiusSm
        color: confirmMa.containsMouse ? Theme.accent : Theme.accentSoft
        border.width: 1
        border.color: Theme.accent
        Text {
          anchors.centerIn: parent
          text: root.confirmLabel
          color: confirmMa.containsMouse ? "#ffffff" : Theme.accent
          font.family: Theme.fontFamily
          font.pixelSize: 12
          font.weight: Font.DemiBold
        }
        MouseArea {
          id: confirmMa
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.confirmed()
        }
      }
    }
  }
}
