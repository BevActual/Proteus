import Quickshell
import QtQuick
import QtQuick.Layouts
import "../../shared"

// Menu-bar center popover — glance calendar with real interaction.
// Stays useful for date/weather; “Open in Calendar” hands off to the app
// for events / editing (gnome-calendar when installed).
Item {
  id: root
  anchors.fill: parent

  readonly property bool openState: ShellState.calendarOpen
  property real openProgress: 0
  readonly property bool stillVisible: openState || openProgress > 0.001

  visible: stillVisible

  Behavior on openProgress {
    NumberAnimation {
      duration: 200
      easing.type: Easing.OutCubic
    }
  }

  // —— Month / selection state ——
  property int viewYear: 2000
  property int viewMonth: 0
  property var todayDate: new Date()
  property int selectedYear: 2000
  property int selectedMonth: 0
  property int selectedDay: 1

  readonly property var selectedDate: new Date(selectedYear, selectedMonth, selectedDay)

  readonly property string selectedLabel: {
    const t = root.todayDate
    const s = root.selectedDate
    const start = new Date(t.getFullYear(), t.getMonth(), t.getDate())
    const sel = new Date(s.getFullYear(), s.getMonth(), s.getDate())
    const diff = Math.round((sel - start) / 86400000)
    if (diff === 0)
      return "Today"
    if (diff === 1)
      return "Tomorrow"
    if (diff === -1)
      return "Yesterday"
    if (diff > 1 && diff < 7)
      return "In " + diff + " days"
    if (diff < -1 && diff > -7)
      return Math.abs(diff) + " days ago"
    return Qt.formatDate(s, "dddd")
  }

  readonly property bool selectedIsToday: selectedYear === todayDate.getFullYear()
      && selectedMonth === todayDate.getMonth()
      && selectedDay === todayDate.getDate()

  function goToday() {
    const d = new Date()
    root.todayDate = d
    root.viewYear = d.getFullYear()
    root.viewMonth = d.getMonth()
    root.selectDate(d.getFullYear(), d.getMonth(), d.getDate())
  }

  function selectDate(y, m, day) {
    root.selectedYear = y
    root.selectedMonth = m
    root.selectedDay = day
    // Jump the grid when picking a day outside the viewed month
    if (m !== root.viewMonth || y !== root.viewYear) {
      root.viewYear = y
      root.viewMonth = m
    }
  }

  function shiftMonth(delta) {
    let m = root.viewMonth + delta
    let y = root.viewYear
    while (m < 0) {
      m += 12
      y--
    }
    while (m > 11) {
      m -= 12
      y++
    }
    root.viewMonth = m
    root.viewYear = y
  }

  function openFullCalendar() {
    ShellState.openCalendarApp()
  }

  readonly property bool onCurrentMonth: viewYear === todayDate.getFullYear()
      && viewMonth === todayDate.getMonth()

  readonly property int firstDowJs: {
    const f = Qt.locale().firstDayOfWeek
    return f % 7
  }

  readonly property var dayCells: {
    const first = new Date(viewYear, viewMonth, 1)
    const offset = (first.getDay() - firstDowJs + 7) % 7
    const cells = []
    for (let i = 0; i < 42; i++) {
      const d = new Date(viewYear, viewMonth, 1 - offset + i)
      const y = d.getFullYear()
      const m = d.getMonth()
      const day = d.getDate()
      cells.push({
        day: day,
        month: m,
        year: y,
        inMonth: m === viewMonth,
        isToday: y === todayDate.getFullYear()
            && m === todayDate.getMonth()
            && day === todayDate.getDate(),
        isSelected: y === selectedYear && m === selectedMonth && day === selectedDay
      })
    }
    return cells
  }

  function weekdayLabel(i) {
    const js = (firstDowJs + i) % 7
    const qtDay = js === 0 ? 7 : js
    return Qt.locale().dayName(qtDay, Locale.ShortFormat)
  }

  onOpenStateChanged: {
    openProgress = openState ? 1 : 0
    if (openState) {
      goToday()
      forceActiveFocus()
    }
  }
  Component.onCompleted: {
    goToday()
    if (openState)
      openProgress = 1
  }

  Rectangle {
    anchors.fill: parent
    color: Theme.scrimFill
    opacity: root.openProgress
    MouseArea {
      anchors.fill: parent
      onClicked: ShellState.closeCalendar()
    }
  }

  Rectangle {
    id: panel
    anchors.top: parent.top
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.topMargin: Theme.barHeight + 10
    width: 308
    height: contentCol.implicitHeight + Theme.spaceMd * 2
    radius: Theme.radiusXl
    color: Theme.menuPlateFill
    border.width: 1
    border.color: Theme.chromeBorder
    clip: true

    opacity: root.openProgress
    transform: [
      Translate {
        y: -14 * (1 - root.openProgress)
      },
      Scale {
        origin.x: panel.width * 0.5
        origin.y: 0
        xScale: 0.98 + 0.02 * root.openProgress
        yScale: 0.98 + 0.02 * root.openProgress
      }
    ]

    MouseArea {
      anchors.fill: parent
      onClicked: {}
    }

    ColumnLayout {
      id: contentCol
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Theme.spaceMd
      spacing: Theme.spaceSm

      // Selected day hero (not just a static “today” label)
      ColumnLayout {
        Layout.fillWidth: true
        spacing: 2

        Text {
          Layout.fillWidth: true
          text: root.selectedLabel
          color: Theme.accent
          font.family: Theme.fontFamily
          font.pixelSize: 12
          font.weight: Font.DemiBold
        }

        Text {
          Layout.fillWidth: true
          text: Qt.formatDate(root.selectedDate, "dddd, MMMM d")
          color: Theme.text
          font.family: Theme.fontFamily
          font.pixelSize: 16
          font.weight: Font.DemiBold
        }

        Text {
          Layout.fillWidth: true
          visible: root.selectedIsToday
          text: Time.timeText
          color: Theme.textDim
          font.family: Theme.fontFamily
          font.pixelSize: 13
          font.weight: Font.Medium
        }
      }

      // Month switcher
      RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spaceXs

        Text {
          Layout.fillWidth: true
          text: Qt.locale().monthName(root.viewMonth, Locale.LongFormat) + " " + root.viewYear
          color: Theme.textDim
          font.family: Theme.fontFamily
          font.pixelSize: 12
          font.weight: Font.Medium
        }

        Repeater {
          model: [
            { act: "prev", glyph: "‹" },
            { act: "today", glyph: "•" },
            { act: "next", glyph: "›" }
          ]

          Rectangle {
            required property var modelData
            Layout.preferredWidth: 24
            Layout.preferredHeight: 24
            radius: 12
            color: navMa.containsMouse ? Theme.chromeHover : "transparent"
            opacity: modelData.act === "today" && root.onCurrentMonth && root.selectedIsToday ? 0.35 : 1

            Text {
              anchors.centerIn: parent
              text: parent.modelData.glyph
              color: Theme.text
              font.family: Theme.fontFamily
              font.pixelSize: parent.modelData.act === "today" ? 11 : 15
            }

            MouseArea {
              id: navMa
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (parent.modelData.act === "prev")
                  root.shiftMonth(-1)
                else if (parent.modelData.act === "next")
                  root.shiftMonth(1)
                else
                  root.goToday()
              }
            }
          }
        }
      }

      // Weekday header
      RowLayout {
        Layout.fillWidth: true
        spacing: 0

        Repeater {
          model: 7
          Text {
            required property int index
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: root.weekdayLabel(index)
            color: Theme.textMute
            font.family: Theme.fontFamily
            font.pixelSize: 10
            font.weight: Font.Medium
          }
        }
      }

      // Day grid — click selects, double-click opens full Calendar
      GridLayout {
        Layout.fillWidth: true
        columns: 7
        rowSpacing: 1
        columnSpacing: 0

        Repeater {
          model: root.dayCells

          Item {
            id: dayCell
            required property var modelData
            Layout.fillWidth: true
            Layout.preferredHeight: 30

            Rectangle {
              anchors.centerIn: parent
              width: 26
              height: 26
              radius: 13
              color: {
                if (dayCell.modelData.isSelected && dayCell.modelData.isToday)
                  return Theme.accent
                if (dayCell.modelData.isSelected)
                  return Theme.accentSoft
                if (dayMa.containsMouse)
                  return Theme.chromeHover
                return "transparent"
              }
              border.width: dayCell.modelData.isToday && !dayCell.modelData.isSelected ? 1.2 : 0
              border.color: Theme.accent

              Behavior on color {
                ColorAnimation {
                  duration: 100
                }
              }
            }

            Text {
              anchors.centerIn: parent
              text: dayCell.modelData.day
              color: {
                if (dayCell.modelData.isSelected && dayCell.modelData.isToday)
                  return "#ffffff"
                if (dayCell.modelData.isSelected)
                  return Theme.accent
                if (dayCell.modelData.isToday)
                  return Theme.accent
                return dayCell.modelData.inMonth ? Theme.text : Theme.textMute
              }
              opacity: dayCell.modelData.inMonth || dayCell.modelData.isToday || dayCell.modelData.isSelected ? 1 : 0.4
              font.family: Theme.fontFamily
              font.pixelSize: 11
              font.weight: (dayCell.modelData.isToday || dayCell.modelData.isSelected)
                  ? Font.DemiBold
                  : Font.Normal
            }

            MouseArea {
              id: dayMa
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.selectDate(
                            dayCell.modelData.year,
                            dayCell.modelData.month,
                            dayCell.modelData.day)
              onDoubleClicked: root.openFullCalendar()
            }
          }
        }
      }

      // Selected-day glance — stays in the dropdown; full app for events
      Rectangle {
        Layout.fillWidth: true
        implicitHeight: selCol.implicitHeight + 12
        radius: Theme.radiusMd
        color: Theme.elevatedFill
        border.width: 1
        border.color: Theme.chromeBorder

        ColumnLayout {
          id: selCol
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.margins: 10
          spacing: 4

          Text {
            Layout.fillWidth: true
            text: root.selectedIsToday
                ? "No events in this glance"
                : ("Selected · " + Qt.formatDate(root.selectedDate, "MMM d"))
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: 12
            font.weight: Font.Medium
          }

          Text {
            Layout.fillWidth: true
            text: ShellState.calendarAppAvailable
                ? "Open in Calendar for events, reminders, and editing"
                : "Install gnome-calendar for events and reminders"
            color: Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: 11
            wrapMode: Text.WordWrap
          }

          Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 28
            Layout.topMargin: 2
            radius: Theme.radiusMd
            color: openCalMa.containsMouse ? Theme.chromeAccentSoft : Theme.chromeHover

            Text {
              anchors.centerIn: parent
              text: ShellState.calendarAppAvailable ? "Open in Calendar" : "Open Date & weather"
              color: Theme.accent
              font.family: Theme.fontFamily
              font.pixelSize: 12
              font.weight: Font.DemiBold
            }

            MouseArea {
              id: openCalMa
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (ShellState.calendarAppAvailable)
                  root.openFullCalendar()
                else
                  ShellState.openDateTimeSettings()
              }
            }
          }
        }
      }

      Rectangle {
        Layout.fillWidth: true
        height: 1
        color: Theme.separator
      }

      // Weather summary — click opens the weather glance (not Settings)
      Rectangle {
        Layout.fillWidth: true
        implicitHeight: wxCol.implicitHeight + 10
        radius: Theme.radiusMd
        color: wxMa.containsMouse ? Theme.chromeHover : "transparent"

        ColumnLayout {
          id: wxCol
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: 6
          anchors.rightMargin: 6
          spacing: 1

          Text {
            Layout.fillWidth: true
            text: {
              if (Weather.ready)
                return Weather.glyph + "  " + Weather.temperatureText + "  ·  " + Weather.description
              if (Weather.hasLocation)
                return Weather.loading ? "Loading weather…" : "Weather unavailable"
              return "No weather location set"
            }
            color: Weather.ready ? Theme.text : Theme.textMute
            font.family: Theme.fontFamily
            font.pixelSize: 12
            font.weight: Weather.ready ? Font.Medium : Font.Normal
            elide: Text.ElideRight
          }

          Text {
            Layout.fillWidth: true
            visible: Weather.ready || !Weather.hasLocation
            text: {
              if (!Weather.hasLocation)
                return "Set location in Date, time & weather ›"
              const hi = Math.round(Weather.high) + "°"
              const lo = Math.round(Weather.low) + "°"
              const loc = String(Config.locationName || "")
              return "H " + hi + "  L " + lo + (loc.length ? "  ·  " + loc : "") + "  ·  Weather ›"
            }
            color: Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: 11
            elide: Text.ElideRight
          }
        }

        MouseArea {
          id: wxMa
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: ShellState.toggleWeather()
        }
      }

      // 5-day forecast
      RowLayout {
        Layout.fillWidth: true
        spacing: 2
        visible: Weather.hasForecast

        Repeater {
          model: Math.min(5, Weather.forecast.length)

          ColumnLayout {
            required property int index
            Layout.fillWidth: true
            spacing: 2

            Text {
              Layout.alignment: Qt.AlignHCenter
              text: Weather.forecastDayLabel(
                      (Weather.forecast[index] || {}).date, index)
              color: Theme.textMute
              font.family: Theme.fontFamily
              font.pixelSize: 10
              font.weight: Font.Medium
            }

            Text {
              Layout.alignment: Qt.AlignHCenter
              text: {
                const d = Weather.forecast[index] || {}
                return Math.round(Number(d.high) || 0) + "°"
              }
              color: Theme.text
              font.family: Theme.fontFamily
              font.pixelSize: 11
              font.weight: Font.DemiBold
            }

            Text {
              Layout.alignment: Qt.AlignHCenter
              text: {
                const d = Weather.forecast[index] || {}
                return Math.round(Number(d.low) || 0) + "°"
              }
              color: Theme.textDim
              font.family: Theme.fontFamily
              font.pixelSize: 10
            }
          }
        }
      }

      // Secondary escape — settings only (Calendar is above)
      Text {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        text: "Date, time & weather settings"
        color: dtLinkMa.containsMouse ? Theme.accent : Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: 11

        MouseArea {
          id: dtLinkMa
          anchors.fill: parent
          anchors.margins: -4
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: ShellState.openDateTimeSettings()
        }
      }
    }
  }

  Keys.onEscapePressed: ShellState.closeCalendar()
  Keys.onLeftPressed: root.shiftMonth(-1)
  Keys.onRightPressed: root.shiftMonth(1)
}
