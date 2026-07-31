import QtQuick
import QtQuick.Layouts
import "../../../shared"

// Calendar — today at a glance (S), month grid with today disc (M/L).
// View-only: month navigation lives in the menu-bar calendar popover.
Item {
  id: root
  property string size: "sm"
  property bool showWhenIdle: true
  // Desktop only: click opens the full calendar popover (month navigation)
  property bool interactive: false

  property var today: new Date()

  // Roll the grid over at midnight without polling every frame.
  Timer {
    interval: 60 * 1000
    repeat: true
    running: root.visible
    onTriggered: {
      const d = new Date()
      if (d.getDate() !== root.today.getDate()
          || d.getMonth() !== root.today.getMonth())
        root.today = d
    }
  }

  readonly property bool grid: size !== "sm"

  readonly property int firstDowJs: Qt.locale().firstDayOfWeek % 7

  readonly property var dayCells: {
    const y = today.getFullYear()
    const m = today.getMonth()
    const first = new Date(y, m, 1)
    const offset = (first.getDay() - firstDowJs + 7) % 7
    const daysInMonth = new Date(y, m + 1, 0).getDate()
    const rows = Math.ceil((offset + daysInMonth) / 7)
    const cells = []
    for (let i = 0; i < rows * 7; i++) {
      const d = new Date(y, m, 1 - offset + i)
      cells.push({
        day: d.getDate(),
        inMonth: d.getMonth() === m,
        isToday: d.getMonth() === m && d.getDate() === today.getDate()
      })
    }
    return cells
  }

  function weekdayLetter(i) {
    const js = (firstDowJs + i) % 7
    const qtDay = js === 0 ? 7 : js
    // NarrowFormat is numeric in some locales (e.g. C) — first letter of the
    // short name is reliably alphabetic.
    return Qt.locale().dayName(qtDay, Locale.ShortFormat).charAt(0)
  }

  implicitWidth: card.implicitWidth
  implicitHeight: card.implicitHeight
  width: parent ? Math.min(parent.width, size === "lg" ? 260 : (size === "md" ? 210 : 150)) : 150
  height: implicitHeight

  Rectangle {
    id: card
    anchors.left: parent.left
    anchors.right: parent.right
    implicitHeight: body.implicitHeight + 20
    radius: 16
    color: Qt.rgba(28 / 255, 28 / 255, 30 / 255, 0.72)
    border.width: 1
    border.color: calMa.containsMouse && root.interactive
        ? Qt.rgba(1, 1, 1, 0.25) : Qt.rgba(1, 1, 1, 0.1)

    MouseArea {
      id: calMa
      anchors.fill: parent
      visible: root.interactive
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: ShellState.toggleCalendar()
      onPressAndHold: ShellState.enterDesktopCustomize()
    }

    ColumnLayout {
      id: body
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: 12
      spacing: root.grid ? 6 : 2

      Text {
        text: root.grid
            ? Qt.locale().monthName(root.today.getMonth(), Locale.LongFormat)
                + " " + root.today.getFullYear()
            : Qt.formatDateTime(root.today, "dddd")
        color: root.grid ? Qt.rgba(1, 1, 1, 0.55) : "#ff453a"
        font.family: Theme.fontFamily
        font.pixelSize: 11
        font.weight: Font.DemiBold
      }

      // Small: macOS calendar-tile look — weekday over a big day number
      Text {
        visible: !root.grid
        text: root.today.getDate()
        color: "#f5f5f7"
        font.family: Theme.fontFamily
        font.pixelSize: 34
        font.weight: Font.Light
      }

      GridLayout {
        visible: root.grid
        Layout.fillWidth: true
        columns: 7
        rowSpacing: 0
        columnSpacing: 0

        Repeater {
          model: 7
          Text {
            required property int index
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: root.weekdayLetter(index)
            color: Qt.rgba(1, 1, 1, 0.42)
            font.family: Theme.fontFamily
            font.pixelSize: root.size === "lg" ? 10 : 9
            font.weight: Font.Medium
          }
        }
      }

      GridLayout {
        visible: root.grid
        Layout.fillWidth: true
        columns: 7
        rowSpacing: 0
        columnSpacing: 0

        Repeater {
          model: root.dayCells

          Item {
            required property var modelData
            Layout.fillWidth: true
            Layout.preferredHeight: root.size === "lg" ? 22 : 18

            Rectangle {
              anchors.centerIn: parent
              width: root.size === "lg" ? 19 : 16
              height: width
              radius: width / 2
              color: parent.modelData.isToday ? Theme.accent : "transparent"
            }

            Text {
              anchors.centerIn: parent
              text: parent.modelData.inMonth ? parent.modelData.day : ""
              color: parent.modelData.isToday ? "#ffffff" : Qt.rgba(1, 1, 1, 0.8)
              font.family: Theme.fontFamily
              font.pixelSize: root.size === "lg" ? 10 : 9
              font.weight: parent.modelData.isToday ? Font.DemiBold : Font.Normal
            }
          }
        }
      }
    }
  }
}
