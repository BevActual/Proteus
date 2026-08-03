import QtQuick
import QtQuick.Layouts
import "../../shared"

// Top destinations: Games · Media · Apps · Search · Settings (+ status / clock).
// Control Center is pad/Guide only — no corner launch button.
Item {
  id: root
  height: Math.max(44, Theme.barHeight + 4)

  property string tab: "games" // games | media | apps | search | settings
  // focusedSlot: 0 games, 1 media, 2 apps, 3 search, 4 settings
  property int focusedSlot: -1
  property bool sessionToggleVisible: false
  property string sessionMode: "seat"
  property string sessionEffective: "seat"

  signal tabSelected(string id)
  signal sessionToggleRequested()

  readonly property int barTextStyle: Theme.menuBarNeedsLegibility ? Text.Outline : Text.Normal
  readonly property color barTextStyleColor: Theme.light
      ? Qt.rgba(1, 1, 1, 0.72)
      : Qt.rgba(0, 0, 0, 0.55)

  readonly property var destinations: [
    { id: "games", label: "Games", slot: 0 },
    { id: "media", label: "Media", slot: 1 },
    { id: "apps", label: "Apps", slot: 2 },
    { id: "search", label: "Search", slot: 3 },
    { id: "settings", label: "Settings", slot: 4 }
  ]

  readonly property string clockText: {
    const d = clock.date
    const days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    let h = d.getHours()
    const ap = h >= 12 ? "PM" : "AM"
    h = h % 12
    if (h === 0)
      h = 12
    const m = ("0" + d.getMinutes()).slice(-2)
    return days[d.getDay()] + " " + months[d.getMonth()] + " " + d.getDate()
        + " " + h + ":" + m + " " + ap
  }

  readonly property string weatherBit: {
    if (!Weather.ready)
      return ""
    return " · " + Weather.temperatureText
  }

  Timer {
    id: clock
    property date date: new Date()
    interval: 15000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: date = new Date()
  }

  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.55)
  }

  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: 1
    color: Theme.chromeHairline
    opacity: 0.35
  }

  RowLayout {
    anchors.fill: parent
    anchors.leftMargin: Theme.spaceXl
    anchors.rightMargin: Theme.spaceXl
    spacing: Theme.spaceLg

    Row {
      spacing: Theme.spaceSm
      Layout.alignment: Qt.AlignVCenter

      Rectangle {
        width: 10
        height: 10
        radius: 5
        color: Theme.accent
        anchors.verticalCenter: parent.verticalCenter
      }

      Repeater {
        model: root.destinations

        Text {
          required property var modelData
          text: modelData.label
          color: root.tab === modelData.id
              ? Theme.accent
              : (root.focusedSlot === modelData.slot ? Theme.text : Theme.textDim)
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSize + 1
          font.weight: root.tab === modelData.id || root.focusedSlot === modelData.slot
              ? Font.DemiBold
              : Font.Normal
          style: root.barTextStyle
          styleColor: root.barTextStyleColor
          leftPadding: 10
          rightPadding: 10
          topPadding: 6
          bottomPadding: 6

          Rectangle {
            anchors.fill: parent
            z: -1
            radius: Theme.radiusPill
            color: root.focusedSlot === modelData.slot
                ? Theme.chromeHover
                : "transparent"
            border.width: root.focusedSlot === modelData.slot && root.tab !== modelData.id ? 1 : 0
            border.color: Theme.accent
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.tabSelected(modelData.id)
          }
        }
      }
    }

    Item { Layout.fillWidth: true }

    Rectangle {
      visible: root.sessionToggleVisible
      Layout.alignment: Qt.AlignVCenter
      Layout.preferredHeight: 28
      Layout.preferredWidth: sessionLabel.implicitWidth + 16
      radius: 14
      color: sessionMa.containsMouse
          ? Theme.chromeHover
          : (root.sessionEffective === "session" ? Theme.chromeAccentSoft : "transparent")
      border.width: 1
      border.color: root.sessionEffective === "session" ? Theme.accent : Theme.chromeBorder

      Text {
        id: sessionLabel
        anchors.centerIn: parent
        text: root.sessionEffective === "session" ? "Gamescope" : "Seat"
        color: root.sessionEffective === "session" ? Theme.accent : Theme.textDim
        font.family: Theme.fontFamily
        font.pixelSize: 10
        font.weight: Font.DemiBold
        style: root.barTextStyle
        styleColor: root.barTextStyleColor
      }

      MouseArea {
        id: sessionMa
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.sessionToggleRequested()
      }
    }

    Rectangle {
      Layout.alignment: Qt.AlignVCenter
      Layout.preferredHeight: 28
      Layout.preferredWidth: statusRow.implicitWidth + 14
      radius: 14
      visible: statusRow.implicitWidth > 0
      color: ShellState.controlCenterOpen ? Theme.chromeHover : "transparent"

      Row {
        id: statusRow
        anchors.centerIn: parent
        spacing: 10

        Rectangle {
          visible: Notifications.unreadCount > 0 && !ShellState.controlCenterOpen
          anchors.verticalCenter: parent.verticalCenter
          width: Math.max(16, badgeLabel.implicitWidth + 8)
          height: 16
          radius: 8
          color: Theme.accent
          Text {
            id: badgeLabel
            anchors.centerIn: parent
            text: Notifications.unreadCount > 9 ? "9+" : String(Notifications.unreadCount)
            color: "#fff"
            font.pixelSize: 10
            font.weight: Font.DemiBold
          }
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          visible: FocusMode.active || Config.notificationsDnd
          text: FocusMode.active ? "Focus" : "DND"
          color: Theme.accent
          font.family: Theme.fontFamily
          font.pixelSize: 10
          font.weight: Font.DemiBold
          style: root.barTextStyle
          styleColor: root.barTextStyleColor
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          visible: KeepAwake.active
          text: KeepAwake.mode === "indefinite" ? "Awake" : ("Awake " + KeepAwake.remainingLabel)
          color: Theme.accent
          font.family: Theme.fontFamily
          font.pixelSize: 10
          font.weight: Font.DemiBold
          style: root.barTextStyle
          styleColor: root.barTextStyleColor
        }
      }
    }

    Text {
      text: root.clockText + root.weatherBit
      color: Theme.textDim
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSize
      style: root.barTextStyle
      styleColor: root.barTextStyleColor
      Layout.alignment: Qt.AlignVCenter
    }
  }
}
