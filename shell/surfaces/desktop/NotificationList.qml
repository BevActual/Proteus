import QtQuick
import QtQuick.Layouts
import "../../shared"

ColumnLayout {
  id: root
  spacing: Theme.spaceSm

  RowLayout {
    Layout.fillWidth: true
    Text {
      text: "Notifications"
      color: Theme.text
      font.family: Theme.fontFamily
      font.pixelSize: 14
      font.weight: Font.Medium
      Layout.fillWidth: true
    }
    Text {
      visible: Notifications.count > 0
      text: "Clear all"
      color: Theme.accent
      font.family: Theme.fontFamily
      font.pixelSize: 12
      MouseArea {
        anchors.fill: parent
        anchors.margins: -6
        cursorShape: Qt.PointingHandCursor
        onClicked: Notifications.clearAll()
      }
    }
  }

  Text {
    visible: Notifications.count === 0
    Layout.fillWidth: true
    Layout.preferredHeight: 72
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    text: Config.notificationsDnd ? "Do Not Disturb is on" : "No notifications"
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 13
  }

  Flickable {
    visible: Notifications.count > 0
    Layout.fillWidth: true
    Layout.fillHeight: true
    Layout.minimumHeight: 80
    Layout.preferredHeight: Math.min(280, Math.max(80, Notifications.count * 78))
    contentHeight: listCol.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    ColumnLayout {
      id: listCol
      width: parent.width
      spacing: Theme.spaceSm

      Repeater {
        model: Notifications.list

        Rectangle {
          required property var modelData
          Layout.fillWidth: true
          implicitHeight: bodyCol.implicitHeight + 20
          radius: Theme.radiusLg
          color: Theme.bgHover

          ColumnLayout {
            id: bodyCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Theme.spaceMd
            spacing: 4

            RowLayout {
              Layout.fillWidth: true
              Text {
                text: modelData.appName && String(modelData.appName).length ? modelData.appName : "App"
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: 11
                Layout.fillWidth: true
                elide: Text.ElideRight
              }
              Text {
                text: "✕"
                color: Theme.textMute
                font.pixelSize: 12
                MouseArea {
                  anchors.fill: parent
                  anchors.margins: -8
                  cursorShape: Qt.PointingHandCursor
                  onClicked: Notifications.dismiss(modelData)
                }
              }
            }

            Text {
              visible: !!(modelData.summary && String(modelData.summary).length)
              text: modelData.summary || ""
              color: Theme.text
              font.family: Theme.fontFamily
              font.pixelSize: 13
              font.weight: Font.Medium
              wrapMode: Text.Wrap
              Layout.fillWidth: true
            }

            Text {
              visible: !!(modelData.body && String(modelData.body).length)
              text: modelData.body || ""
              color: Theme.textDim
              font.family: Theme.fontFamily
              font.pixelSize: 12
              wrapMode: Text.Wrap
              maximumLineCount: 3
              elide: Text.ElideRight
              Layout.fillWidth: true
            }
          }
        }
      }
    }
  }
}
