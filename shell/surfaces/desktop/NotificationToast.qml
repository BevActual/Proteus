import QtQuick
import QtQuick.Layouts
import "../../shared"

// Transient toast — suppressed when DND or Control Center open (Notifications.showToast).
Item {
  id: root
  anchors.fill: parent
  visible: Notifications.showToast
  z: 30

  readonly property var n: Notifications.toastNotification
  readonly property alias cardItem: card

  Rectangle {
    id: card
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.topMargin: Theme.barHeight + 12
    anchors.rightMargin: 12
    width: Math.min(340, parent.width - 24)
    implicitHeight: col.implicitHeight + Theme.spaceMd * 2
    radius: Theme.radiusXl
    color: Theme.elevatedFill
    border.width: 1
    border.color: Theme.chromeBorder
    opacity: root.visible ? 1 : 0

    Behavior on opacity {
      NumberAnimation {
        duration: 160
      }
    }

    ColumnLayout {
      id: col
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Theme.spaceMd
      spacing: 4

      RowLayout {
        Layout.fillWidth: true
        Text {
          text: (root.n && root.n.appName) ? root.n.appName : "Notification"
          color: Theme.textDim
          font.family: Theme.fontFamily
          font.pixelSize: 11
          Layout.fillWidth: true
          elide: Text.ElideRight
        }
        Text {
          text: "Dismiss"
          color: Theme.textMute
          font.family: Theme.fontFamily
          font.pixelSize: 12
          MouseArea {
            anchors.fill: parent
            anchors.margins: -6
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              if (root.n)
                Notifications.dismiss(root.n)
              else
                Notifications.clearToast()
            }
          }
        }
      }
      Text {
        visible: !!(root.n && root.n.summary && String(root.n.summary).length)
        text: root.n ? (root.n.summary || "") : ""
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: 13
        font.weight: Font.Medium
        wrapMode: Text.Wrap
        Layout.fillWidth: true
      }
      Text {
        visible: !!(root.n && root.n.body && String(root.n.body).length)
        text: root.n ? (root.n.body || "") : ""
        color: Theme.textDim
        font.family: Theme.fontFamily
        font.pixelSize: 12
        wrapMode: Text.Wrap
        maximumLineCount: 2
        elide: Text.ElideRight
        Layout.fillWidth: true
      }
      Text {
        Layout.fillWidth: true
        text: "Open Control Center"
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: 11
      }
    }

    MouseArea {
      anchors.fill: parent
      z: -1
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        Notifications.clearToast()
        ShellState.openControlCenter()
      }
    }
  }

  Timer {
    id: hideTimer
    interval: 4500
    running: root.visible
    onTriggered: Notifications.clearToast()
  }

  Connections {
    target: Notifications
    function onToastSeqChanged() {
      if (Notifications.toastNotification)
        hideTimer.restart()
    }
  }
}
