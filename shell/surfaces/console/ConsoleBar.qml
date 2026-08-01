import QtQuick
import QtQuick.Layouts
import "../../shared"

Item {
  id: root
  height: Math.max(40, Theme.barHeight + 8)

  property string tab: "home" // home | library | search
  property int focusedSlot: -1 // 0 home, 1 library, 2 search, 3 cc

  signal tabSelected(string id)
  signal controlCenterRequested()

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
    color: Theme.menuBarFill
  }

  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: 1
    color: Theme.chromeHairline
  }

  RowLayout {
    anchors.fill: parent
    anchors.leftMargin: Theme.spaceXl
    anchors.rightMargin: Theme.spaceXl
    spacing: Theme.spaceLg

    Row {
      spacing: Theme.spaceMd
      Layout.alignment: Qt.AlignVCenter

      Rectangle {
        width: 22
        height: 22
        radius: 6
        color: Theme.accent
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        text: "Proteus"
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize + 1
        font.weight: Font.DemiBold
        anchors.verticalCenter: parent.verticalCenter
      }

      Rectangle {
        width: badge.implicitWidth + 16
        height: 22
        radius: Theme.radiusPill
        color: Theme.elevatedFill
        border.width: 1
        border.color: Theme.chromeBorder
        anchors.verticalCenter: parent.verticalCenter

        Text {
          id: badge
          anchors.centerIn: parent
          text: "CONSOLE"
          color: Theme.textDim
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSizeSm - 1
          font.letterSpacing: 0.8
          font.weight: Font.DemiBold
        }
      }
    }

    Row {
      spacing: Theme.spaceSm
      Layout.alignment: Qt.AlignVCenter

      Repeater {
        model: [
          { id: "home", label: "Home" },
          { id: "library", label: "Library" },
          { id: "search", label: "Search" }
        ]

        Rectangle {
          required property var modelData
          required property int index
          width: tabLabel.implicitWidth + 20
          height: 28
          radius: Theme.radiusPill
          color: root.tab === modelData.id ? Theme.accent : (root.focusedSlot === index ? Theme.chromeHover : "transparent")
          border.width: root.focusedSlot === index && root.tab !== modelData.id ? 1 : 0
          border.color: Theme.accent

          Text {
            id: tabLabel
            anchors.centerIn: parent
            text: modelData.label
            color: root.tab === modelData.id ? "#ffffff" : Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            font.weight: root.tab === modelData.id ? Font.DemiBold : Font.Normal
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

    Text {
      text: root.clockText + root.weatherBit
      color: Theme.textDim
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSize
      Layout.alignment: Qt.AlignVCenter
    }

    Rectangle {
      width: 28
      height: 28
      radius: 14
      color: root.focusedSlot === 3 ? Theme.chromeAccentSoft : Theme.elevatedFill
      border.width: 1
      border.color: root.focusedSlot === 3 ? Theme.accent : Theme.chromeBorder
      Layout.alignment: Qt.AlignVCenter

      Text {
        anchors.centerIn: parent
        text: "⚙"
        color: Theme.text
        font.pixelSize: 14
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.controlCenterRequested()
      }
    }
  }
}
