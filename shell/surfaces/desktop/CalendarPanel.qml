import Quickshell
import QtQuick
import QtQuick.Controls
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

  onSelectedDayChanged: {
    if (openState)
      CalendarEvents.refreshForDate(root.selectedDate)
  }
  onSelectedMonthChanged: {
    if (openState)
      CalendarEvents.refreshForDate(root.selectedDate)
  }
  onSelectedYearChanged: {
    if (openState)
      CalendarEvents.refreshForDate(root.selectedDate)
  }

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

  function openFullMail() {
    ShellState.openMailApp()
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
      CalendarEvents.refreshForDate(root.selectedDate)
      MailGlance.refresh()
      ContactsGlance.refresh()
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

      // Selected-day glance — Online accounts + CalDAV create/update/delete thin
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

          property string newEventTitle: ""
          // Thin recurrence (create + whole-series edit): none|daily|weekly|monthly
          property string newEventRepeat: "none"
          property string confirmDeleteHref: ""
          property string editingHref: ""
          property string editTitle: ""
          property string editEventRepeat: "none"

          readonly property var repeatCycle: ["none", "daily", "weekly", "monthly"]
          function repeatLabel(v) {
            const x = String(v || "none")
            if (x === "daily")
              return "Daily"
            if (x === "weekly")
              return "Weekly"
            if (x === "monthly")
              return "Monthly"
            return "Once"
          }
          function cycleRepeat() {
            const i = selCol.repeatCycle.indexOf(selCol.newEventRepeat)
            selCol.newEventRepeat = selCol.repeatCycle[(i < 0 ? 0 : i + 1) % selCol.repeatCycle.length]
          }
          function cycleEditRepeat() {
            const i = selCol.repeatCycle.indexOf(selCol.editEventRepeat)
            selCol.editEventRepeat = selCol.repeatCycle[(i < 0 ? 0 : i + 1) % selCol.repeatCycle.length]
          }

          Text {
            Layout.fillWidth: true
            text: {
              const _r = CalendarEvents.rev
              if (CalendarEvents.busy || CalendarEvents.mutating)
                return CalendarEvents.mutating ? "Updating…" : "Loading events…"
              if (CalendarEvents.hasEvents)
                return (root.selectedIsToday ? "Today" : Qt.formatDate(root.selectedDate, "MMM d"))
                    + " · " + CalendarEvents.events.length
                    + (CalendarEvents.events.length === 1 ? " event" : " events")
              if (CalendarEvents.hasSeats)
                return root.selectedIsToday
                    ? "No events today"
                    : ("No events · " + Qt.formatDate(root.selectedDate, "MMM d"))
              return root.selectedIsToday
                  ? "No events in this glance"
                  : ("Selected · " + Qt.formatDate(root.selectedDate, "MMM d"))
            }
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: 12
            font.weight: Font.Medium
          }

          Repeater {
            model: {
              const _r = CalendarEvents.rev
              const list = CalendarEvents.events || []
              return list.slice(0, 5)
            }
            ColumnLayout {
              id: evRow
              required property var modelData
              Layout.fillWidth: true
              spacing: 4

              readonly property string evHref: String(modelData.href || "")
              readonly property bool isEditing: selCol.editingHref === evHref && evHref.length
              readonly property bool isConfirmDelete: selCol.confirmDeleteHref === evHref
                  && evHref.length

              RowLayout {
                Layout.fillWidth: true
                spacing: 6
                visible: !evRow.isEditing

                Text {
                  Layout.fillWidth: true
                  text: {
                    const t = CalendarEvents.timeLabel(modelData)
                    return (t.length ? (t + " · ") : "") + String(modelData.title || "")
                  }
                  color: Theme.textDim
                  font.family: Theme.fontFamily
                  font.pixelSize: 11
                  elide: Text.ElideRight
                }

                Text {
                  visible: CalendarEvents.isMutable(modelData) && !evRow.isConfirmDelete
                  text: "Edit"
                  color: Theme.accent
                  font.family: Theme.fontFamily
                  font.pixelSize: 11
                  MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      selCol.confirmDeleteHref = ""
                      selCol.editingHref = String(modelData.href || "")
                      selCol.editTitle = String(modelData.title || "")
                      const r = String(modelData.recurrence || "").toLowerCase()
                      selCol.editEventRepeat = (r === "daily" || r === "weekly" || r === "monthly")
                          ? r : "none"
                    }
                  }
                }

                Text {
                  visible: CalendarEvents.isMutable(modelData) && !evRow.isConfirmDelete
                  text: "✕"
                  color: Theme.textMute
                  font.family: Theme.fontFamily
                  font.pixelSize: 11
                  MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      selCol.editingHref = ""
                      selCol.confirmDeleteHref = String(modelData.href || "")
                    }
                  }
                }

                RowLayout {
                  visible: CalendarEvents.isMutable(modelData) && evRow.isConfirmDelete
                  spacing: 6
                  Text {
                    text: "Cancel"
                    color: Theme.textMute
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    MouseArea {
                      anchors.fill: parent
                      anchors.margins: -4
                      cursorShape: Qt.PointingHandCursor
                      onClicked: selCol.confirmDeleteHref = ""
                    }
                  }
                  Text {
                    text: "Delete"
                    color: Theme.danger
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    MouseArea {
                      anchors.fill: parent
                      anchors.margins: -4
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        CalendarEvents.deleteEvent(modelData)
                        selCol.confirmDeleteHref = ""
                      }
                    }
                  }
                }
              }

              RowLayout {
                Layout.fillWidth: true
                spacing: 6
                visible: evRow.isEditing

                TextField {
                  Layout.fillWidth: true
                  text: selCol.editTitle
                  color: Theme.text
                  placeholderText: "Title"
                  placeholderTextColor: Theme.textMute
                  font.family: Theme.fontFamily
                  font.pixelSize: 11
                  background: Item {}
                  onTextChanged: selCol.editTitle = text
                  onAccepted: {
                    const y = root.selectedDate.getFullYear()
                    const m = ("0" + (root.selectedDate.getMonth() + 1)).slice(-2)
                    const d = ("0" + root.selectedDate.getDate()).slice(-2)
                    if (CalendarEvents.updateEvent(
                          modelData, selCol.editTitle, y + "-" + m + "-" + d,
                          selCol.editEventRepeat))
                      selCol.editingHref = ""
                  }
                }

                Text {
                  text: selCol.repeatLabel(selCol.editEventRepeat)
                  color: Theme.textDim
                  font.family: Theme.fontFamily
                  font.pixelSize: 11
                  font.weight: Font.Medium
                  MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
                    cursorShape: Qt.PointingHandCursor
                    onClicked: selCol.cycleEditRepeat()
                  }
                }

                Text {
                  text: "Save"
                  color: Theme.accent
                  font.family: Theme.fontFamily
                  font.pixelSize: 11
                  font.weight: Font.DemiBold
                  MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      const y = root.selectedDate.getFullYear()
                      const m = ("0" + (root.selectedDate.getMonth() + 1)).slice(-2)
                      const d = ("0" + root.selectedDate.getDate()).slice(-2)
                      if (CalendarEvents.updateEvent(
                            modelData, selCol.editTitle, y + "-" + m + "-" + d,
                            selCol.editEventRepeat))
                        selCol.editingHref = ""
                    }
                  }
                }

                Text {
                  text: "Cancel"
                  color: Theme.textMute
                  font.family: Theme.fontFamily
                  font.pixelSize: 11
                  MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
                    cursorShape: Qt.PointingHandCursor
                    onClicked: selCol.editingHref = ""
                  }
                }
              }
            }
          }

          Text {
            Layout.fillWidth: true
            visible: {
              const _r = CalendarEvents.rev
              return !!CalendarEvents.error.length
            }
            text: CalendarEvents.error
            color: Theme.danger
            font.family: Theme.fontFamily
            font.pixelSize: 11
            wrapMode: Text.WordWrap
          }

          RowLayout {
            Layout.fillWidth: true
            visible: {
              const _r = CalendarEvents.rev
              return CalendarEvents.canCreate
            }
            spacing: 6

            TextField {
              Layout.fillWidth: true
              placeholderText: "New event"
              text: selCol.newEventTitle
              color: Theme.text
              placeholderTextColor: Theme.textMute
              font.family: Theme.fontFamily
              font.pixelSize: 11
              background: Item {}
              onTextChanged: selCol.newEventTitle = text
              onAccepted: {
                const y = root.selectedDate.getFullYear()
                const m = ("0" + (root.selectedDate.getMonth() + 1)).slice(-2)
                const d = ("0" + root.selectedDate.getDate()).slice(-2)
                if (CalendarEvents.createEvent(
                      selCol.newEventTitle, y + "-" + m + "-" + d, selCol.newEventRepeat))
                  selCol.newEventTitle = ""
              }
            }

            Text {
              text: selCol.repeatLabel(selCol.newEventRepeat)
              color: Theme.textDim
              font.family: Theme.fontFamily
              font.pixelSize: 11
              font.weight: Font.Medium
              MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                cursorShape: Qt.PointingHandCursor
                onClicked: selCol.cycleRepeat()
              }
            }

            Text {
              text: "Add"
              color: Theme.accent
              font.family: Theme.fontFamily
              font.pixelSize: 11
              font.weight: Font.DemiBold
              MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  const y = root.selectedDate.getFullYear()
                  const m = ("0" + (root.selectedDate.getMonth() + 1)).slice(-2)
                  const d = ("0" + root.selectedDate.getDate()).slice(-2)
                  if (CalendarEvents.createEvent(
                        selCol.newEventTitle, y + "-" + m + "-" + d, selCol.newEventRepeat))
                    selCol.newEventTitle = ""
                }
              }
            }
          }

          Text {
            Layout.fillWidth: true
            text: {
              const _r = CalendarEvents.rev
              if (CalendarEvents.canCreate)
                return "CalDAV + Google/MS create/edit/delete In · recurrence thin create+edit In · mail compose thin In · Open Calendar for full editing"
              if (CalendarEvents.hasSeats)
                return ShellState.calendarAppAvailable
                    ? "Open in Calendar for editing · CalDAV seats enable glance create/edit/delete"
                    : "Connect CalDAV/Nextcloud/Apple in Settings → Online accounts"
              return ShellState.calendarAppAvailable
                  ? "Open in Calendar for events, reminders, and editing"
                  : "Install gnome-calendar · or connect Online accounts"
            }
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

      // Mail glance — unread subjects from Online accounts (G/MS)
      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: mailCol.implicitHeight + 20
        radius: Theme.radiusMd
        color: Theme.elevatedFill
        border.width: 1
        border.color: Theme.chromeBorder

        ColumnLayout {
          id: mailCol
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.margins: 10
          spacing: 4

          Text {
            Layout.fillWidth: true
            text: {
              const _r = MailGlance.rev
              if (MailGlance.busy)
                return "Loading mail…"
              if (MailGlance.hasMessages || MailGlance.unread > 0) {
                const n = MailGlance.unread
                return n > 0
                    ? (n + (n === 1 ? " unread" : " unread"))
                    : "Recent mail"
              }
              if (MailGlance.hasSeats)
                return "Inbox clear"
              return "Mail glance"
            }
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: 12
            font.weight: Font.Medium
          }

          Repeater {
            model: {
              const _r = MailGlance.rev
              const list = MailGlance.messages || []
              return list.slice(0, 3)
            }
            Text {
              required property var modelData
              Layout.fillWidth: true
              text: {
                const from = MailGlance.fromLabel(modelData)
                const sub = String(modelData.subject || "")
                return (from.length ? (from + " · ") : "") + sub
              }
              color: Theme.textDim
              font.family: Theme.fontFamily
              font.pixelSize: 11
              elide: Text.ElideRight
            }
          }

          Text {
            Layout.fillWidth: true
            visible: {
              const _r = MailGlance.rev
              return !!MailGlance.error.length && !MailGlance.hasMessages
            }
            text: MailGlance.error
            color: Theme.danger
            font.family: Theme.fontFamily
            font.pixelSize: 11
            wrapMode: Text.WordWrap
          }

          Text {
            Layout.fillWidth: true
            visible: {
              const _r = MailGlance.rev
              return !!MailGlance.hint.length
            }
            text: MailGlance.hint
            color: Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: 11
            wrapMode: Text.WordWrap
          }

          ColumnLayout {
            Layout.fillWidth: true
            visible: {
              const _r = MailGlance.rev
              return MailGlance.canSend
            }
            spacing: 4

            TextField {
              Layout.fillWidth: true
              placeholderText: "To"
              text: MailGlance.composeTo
              color: Theme.text
              placeholderTextColor: Theme.textMute
              font.family: Theme.fontFamily
              font.pixelSize: 11
              background: Item {}
              onTextChanged: MailGlance.composeTo = text
            }

            TextField {
              Layout.fillWidth: true
              placeholderText: "Subject"
              text: MailGlance.composeSubject
              color: Theme.text
              placeholderTextColor: Theme.textMute
              font.family: Theme.fontFamily
              font.pixelSize: 11
              background: Item {}
              onTextChanged: MailGlance.composeSubject = text
              onAccepted: MailGlance.sendMessage()
            }

            TextField {
              Layout.fillWidth: true
              placeholderText: "Message"
              text: MailGlance.composeBody
              color: Theme.text
              placeholderTextColor: Theme.textMute
              font.family: Theme.fontFamily
              font.pixelSize: 11
              background: Item {}
              onTextChanged: MailGlance.composeBody = text
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: 6

              Text {
                Layout.fillWidth: true
                text: {
                  const _r = MailGlance.rev
                  if (MailGlance.sending)
                    return "Sending…"
                  if (MailGlance.sendError.length)
                    return MailGlance.sendError
                  return "Plain text · To / Subject / Body"
                }
                color: {
                  const _r = MailGlance.rev
                  return MailGlance.sendError.length ? Theme.danger : Theme.textDim
                }
                font.family: Theme.fontFamily
                font.pixelSize: 11
                elide: Text.ElideRight
              }

              Text {
                text: "Send"
                color: Theme.accent
                font.family: Theme.fontFamily
                font.pixelSize: 11
                font.weight: Font.DemiBold
                opacity: {
                  const _r = MailGlance.rev
                  return MailGlance.sending ? 0.5 : 1
                }
                MouseArea {
                  anchors.fill: parent
                  anchors.margins: -6
                  cursorShape: Qt.PointingHandCursor
                  enabled: {
                    const _r = MailGlance.rev
                    return !MailGlance.sending
                  }
                  onClicked: MailGlance.sendMessage()
                }
              }
            }
          }

          Text {
            Layout.fillWidth: true
            text: {
              const _r = MailGlance.rev
              if (MailGlance.canSend)
                return "Compose thin In · Google/MS/Exchange + IMAP/Apple SMTP · Open Mail for full reading"
              if (MailGlance.hasSeats)
                return ShellState.mailAppAvailable
                    ? "Open in Mail for reading · reconnect seats for send scopes"
                    : "Connect seats in Settings → Online accounts"
              return ShellState.mailAppAvailable
                  ? "Open in Mail · or connect Online accounts for glance/compose"
                  : "Install a mail app · or connect Online accounts"
            }
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
            color: openMailMa.containsMouse ? Theme.chromeAccentSoft : Theme.chromeHover

            Text {
              anchors.centerIn: parent
              text: ShellState.mailAppAvailable ? "Open in Mail" : "Open Online accounts"
              color: Theme.accent
              font.family: Theme.fontFamily
              font.pixelSize: 12
              font.weight: Font.DemiBold
            }

            MouseArea {
              id: openMailMa
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (ShellState.mailAppAvailable)
                  root.openFullMail()
                else
                  ShellState.openSettings("accounts")
              }
            }
          }
        }
      }

      // Contacts glance — CardDAV address book (Online accounts)
      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: contactsCol.implicitHeight + 20
        radius: Theme.radiusMd
        color: Theme.elevatedFill
        border.width: 1
        border.color: Theme.chromeBorder

        ColumnLayout {
          id: contactsCol
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.margins: 10
          spacing: 4

          Text {
            Layout.fillWidth: true
            text: {
              const _r = ContactsGlance.rev
              if (ContactsGlance.busy)
                return "Loading contacts…"
              if (ContactsGlance.hasContacts)
                return "Contacts · " + ContactsGlance.contacts.length
              if (ContactsGlance.hasSeats)
                return "Address book empty"
              return "Contacts glance"
            }
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: 12
            font.weight: Font.Medium
          }

          Repeater {
            model: {
              const _r = ContactsGlance.rev
              const list = ContactsGlance.contacts || []
              return list.slice(0, 3)
            }
            Text {
              required property var modelData
              Layout.fillWidth: true
              text: ContactsGlance.contactLabel(modelData)
              color: Theme.textDim
              font.family: Theme.fontFamily
              font.pixelSize: 11
              elide: Text.ElideRight
            }
          }

          Text {
            Layout.fillWidth: true
            visible: {
              const _r = ContactsGlance.rev
              return !!ContactsGlance.error.length && !ContactsGlance.hasContacts
            }
            text: ContactsGlance.error
            color: Theme.danger
            font.family: Theme.fontFamily
            font.pixelSize: 11
            wrapMode: Text.WordWrap
          }

          Text {
            Layout.fillWidth: true
            text: {
              const _r = ContactsGlance.rev
              if (ContactsGlance.hasSeats)
                return "CardDAV seat · Settings → Online accounts"
              return "Connect CardDAV in Settings → Online accounts"
            }
            color: Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: 11
            wrapMode: Text.WordWrap
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
