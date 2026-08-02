import Quickshell
import QtQuick
import QtQuick.Layouts
import "../../shared"

// Control Center notification list — empty / clear / dismiss honesty.
ColumnLayout {
  id: root
  spacing: Theme.spaceSm

  readonly property int count: Notifications.count
  readonly property bool empty: count === 0

  // Ticks the relative "2m ago" labels while the list is on screen.
  property int nowTick: 0

  Timer {
    interval: 30000
    running: root.visible && !root.empty
    repeat: true
    onTriggered: root.nowTick++
  }

  function timeLabel(n) {
    const _t = root.nowTick
    const at = Notifications.receivedAt(n)
    if (!at)
      return ""
    const s = Math.max(0, Math.round((Date.now() - at) / 1000))
    if (s < 60)
      return "now"
    const m = Math.floor(s / 60)
    if (m < 60)
      return m + "m"
    const h = Math.floor(m / 60)
    if (h < 24)
      return h + "h"
    return Math.floor(h / 24) + "d"
  }

  function appIconSource(n) {
    if (!n)
      return ""
    const raw = String(n.appIcon || "")
    if (raw.length) {
      if (raw.indexOf("file:") === 0)
        return raw
      if (raw.indexOf("/") === 0)
        return "file://" + raw
      const p = Quickshell.iconPath(raw, true)
      if (p && p.length)
        return p
    }
    const de = DesktopEntries.heuristicLookup(String(n.appName || ""))
    if (de && de.icon) {
      const p2 = Quickshell.iconPath(String(de.icon), true)
      if (p2 && p2.length)
        return p2
    }
    return ""
  }

  readonly property string emptyTitle: {
    if (Config.notificationsDnd)
      return "Do Not Disturb is on"
    if (FocusMode.active)
      return "Focus is on"
    return "No notifications"
  }
  readonly property string emptyHint: {
    if (Config.notificationsDnd)
      return "Hard quiet · toasts suppressed · alerts still queue here"
    if (FocusMode.active)
      return "Only allowed apps toast · alerts still queue here"
    return "Alerts from apps appear here"
  }

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

  // Flat rows: section headers + notification cards (grouped by app).
  readonly property var displayRows: {
    const groups = Notifications.groupedList()
    const out = []
    for (let i = 0; i < groups.length; i++) {
      const g = groups[i]
      out.push({ kind: "section", appName: g.appName, notification: null })
      const items = g.items || []
      for (let j = 0; j < items.length; j++)
        out.push({ kind: "item", appName: g.appName, notification: items[j] })
    }
    return out
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
        model: root.displayRows

        Rectangle {
          id: row
          required property var modelData
          readonly property bool isSection: modelData.kind === "section"
          readonly property var notification: modelData.notification
          Layout.fillWidth: true
          implicitHeight: isSection ? 22 : (bodyCol.implicitHeight + Theme.spaceMd * 2)
          radius: isSection ? 0 : Theme.radiusLg
          color: isSection ? "transparent" : Theme.elevatedFill
          border.width: isSection ? 0 : 1
          border.color: Theme.chromeBorder

          readonly property var actions: root.actionList(notification)
          readonly property string iconSrc: root.appIconSource(notification)

          Text {
            visible: row.isSection
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: modelData.appName || "App"
            color: Theme.textMute
            font.family: Theme.fontFamily
            font.pixelSize: 11
            font.weight: Font.Medium
          }

          // Slide-out before the server-side dismiss removes the card.
          function dismissAnimated() {
            if (leaveAnim.running)
              return
            leaveAnim.start()
          }

          SequentialAnimation {
            id: leaveAnim
            ParallelAnimation {
              NumberAnimation {
                target: row
                property: "opacity"
                to: 0
                duration: 140
                easing.type: Easing.InCubic
              }
              NumberAnimation {
                target: row
                property: "x"
                to: 48
                duration: 140
                easing.type: Easing.InCubic
              }
            }
            ScriptAction {
              script: Notifications.dismiss(row.notification)
            }
          }

          ColumnLayout {
            id: bodyCol
            visible: !row.isSection
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Theme.spaceMd
            spacing: 4

            RowLayout {
              Layout.fillWidth: true
              spacing: Theme.spaceXs

              // App icon chip (desktop-entry lookup fallback; letter as last resort)
              Rectangle {
                Layout.preferredWidth: 18
                Layout.preferredHeight: 18
                radius: 5
                color: Theme.bgHover
                border.width: 1
                border.color: Theme.chromeBorder

                Image {
                  id: appIcon
                  anchors.fill: parent
                  anchors.margins: 2
                  source: row.iconSrc
                  fillMode: Image.PreserveAspectFit
                  asynchronous: true
                  visible: row.iconSrc.length > 0 && status === Image.Ready
                }

                Text {
                  anchors.centerIn: parent
                  visible: !appIcon.visible
                  text: {
                    const n = String((row.notification && row.notification.appName) || "A")
                    return n.length ? n.charAt(0).toUpperCase() : "A"
                  }
                  color: Theme.textDim
                  font.family: Theme.fontFamily
                  font.pixelSize: 10
                  font.weight: Font.DemiBold
                }
              }

              Text {
                text: {
                  const n = row.notification
                  return n && n.appName && String(n.appName).length ? n.appName : "App"
                }
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: 11
                Layout.fillWidth: true
                elide: Text.ElideRight
              }
              Text {
                text: root.timeLabel(row.notification)
                visible: text.length > 0
                color: Theme.textMute
                font.family: Theme.fontFamily
                font.pixelSize: 11
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
                  onClicked: row.dismissAnimated()
                }
              }
            }

            Text {
              visible: !!(row.notification && row.notification.summary && String(row.notification.summary).length)
              text: (row.notification && row.notification.summary) || ""
              color: Theme.text
              font.family: Theme.fontFamily
              font.pixelSize: 13
              font.weight: Font.Medium
              wrapMode: Text.Wrap
              Layout.fillWidth: true
            }

            Text {
              visible: !!(row.notification && row.notification.body && String(row.notification.body).length)
              text: (row.notification && row.notification.body) || ""
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
                    onClicked: root.invokeAction(row.notification, modelData)
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
