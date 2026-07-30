import QtQuick
import QtQuick.Layouts
import "../../shared"

// Control Center notification list — empty / clear / dismiss honesty.
ColumnLayout {
  id: root
  spacing: Theme.spaceSm

  readonly property int count: Notifications.count
  readonly property bool empty: count === 0

  readonly property string emptyTitle: Config.notificationsDnd ? "Do Not Disturb is on" : "No notifications"
  readonly property string emptyHint: Config.notificationsDnd
      ? "Toasts are suppressed · alerts still queue here when apps send them"
      : "Alerts from apps appear here"

  function actionList(n) {
    if (!n)
      return []
    try {
      const a = n.actions
      if (!a)
        return []
      if (a.values)
        return a.values
      if (typeof a.length === "number") {
        const out = []
        for (let i = 0; i < a.length; i++)
          out.push(a[i])
        return out
      }
    } catch (e) {}
    return []
  }

  function invokeAction(n, action) {
    if (!n || !action)
      return
    try {
      if (typeof action.invoke === "function")
        action.invoke()
      else if (typeof n.invokeAction === "function" && action.identifier !== undefined)
        n.invokeAction(action.identifier)
    } catch (e) {}
  }

  RowLayout {
    Layout.fillWidth: true
    Text {
      text: root.empty ? "Notifications" : ("Notifications · " + root.count)
      color: Theme.text
      font.family: Theme.fontFamily
      font.pixelSize: 14
      font.weight: Font.Medium
      Layout.fillWidth: true
    }
    Text {
      visible: !root.empty
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

  // Empty honesty
  Rectangle {
    visible: root.empty
    Layout.fillWidth: true
    Layout.preferredHeight: emptyCol.implicitHeight + Theme.spaceMd * 2
    radius: Theme.radiusLg
    color: Theme.bgHover
    border.width: 1
    border.color: Theme.chromeBorder

    ColumnLayout {
      id: emptyCol
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.margins: Theme.spaceMd
      spacing: 4

      Text {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        text: root.emptyTitle
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: 13
      }
      Text {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        text: root.emptyHint
        color: Theme.textDim
        font.family: Theme.fontFamily
        font.pixelSize: 11
        wrapMode: Text.WordWrap
      }
    }
  }

  Flickable {
    visible: !root.empty
    Layout.fillWidth: true
    Layout.fillHeight: true
    Layout.minimumHeight: 80
    Layout.preferredHeight: Math.min(300, Math.max(88, root.count * 92))
    contentHeight: listCol.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick

    ColumnLayout {
      id: listCol
      width: parent.width
      spacing: Theme.spaceSm

      Repeater {
        model: Notifications.list

        Rectangle {
          id: row
          required property var modelData
          Layout.fillWidth: true
          implicitHeight: bodyCol.implicitHeight + Theme.spaceMd * 2
          radius: Theme.radiusLg
          color: Theme.elevatedFill
          border.width: 1
          border.color: Theme.chromeBorder

          readonly property var actions: root.actionList(modelData)

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
                text: "Dismiss"
                color: Theme.textMute
                font.family: Theme.fontFamily
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

            RowLayout {
              visible: row.actions.length > 0
              Layout.fillWidth: true
              spacing: Theme.spaceSm

              Repeater {
                model: row.actions

                Text {
                  required property var modelData
                  text: {
                    if (!modelData)
                      return "Action"
                    if (modelData.text && String(modelData.text).length)
                      return modelData.text
                    if (modelData.identifier && String(modelData.identifier).length)
                      return modelData.identifier
                    return "Action"
                  }
                  color: Theme.accent
                  font.family: Theme.fontFamily
                  font.pixelSize: 12
                  MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.invokeAction(row.modelData, modelData)
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
