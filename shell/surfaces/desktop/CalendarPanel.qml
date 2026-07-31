import Quickshell
import QtQuick
import QtQuick.Layouts
import "../../shared"

// Menu-bar center popover — today header, month calendar, weather summary.
// Same motion/window contract as ControlCenter (stillVisible keeps the layer
// window mapped while the exit animation plays).
Item {
  id: root
  anchors.fill: parent

  readonly property bool openState: ShellState.calendarOpen
  property real openProgress: openState ? 1 : 0
  readonly property bool stillVisible: openState || openProgress > 0.001

  visible: stillVisible

  Behavior on openProgress {
    NumberAnimation {
      duration: 200
      easing.type: Easing.OutCubic
    }
  }

  // —— Month state ——
  property int viewYear: 2000
  property int viewMonth: 0
  property var todayDate: new Date()

  function goToday() {
    const d = new Date()
    root.todayDate = d
    root.viewYear = d.getFullYear()
    root.viewMonth = d.getMonth()
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

  readonly property bool onCurrentMonth: viewYear === todayDate.getFullYear()
      && viewMonth === todayDate.getMonth()

  // Locale-aware first day of week (Qt: Monday=1 … Sunday=7 → JS 0–6).
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
      cells.push({
        day: d.getDate(),
        inMonth: d.getMonth() === viewMonth,
        isToday: d.getFullYear() === todayDate.getFullYear()
            && d.getMonth() === todayDate.getMonth()
            && d.getDate() === todayDate.getDate()
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
    if (openState) {
      goToday()
      forceActiveFocus()
    }
  }
  Component.onCompleted: goToday()

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
    width: 296
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

      // Today header
      Text {
        text: Qt.formatDateTime(root.todayDate, "dddd, MMMM d")
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: 15
        font.weight: Font.DemiBold
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
            Layout.preferredWidth: 22
            Layout.preferredHeight: 22
            radius: 11
            color: navMa.containsMouse ? Theme.chromeHover : "transparent"
            opacity: modelData.act === "today" && root.onCurrentMonth ? 0.35 : 1

            Text {
              anchors.centerIn: parent
              text: parent.modelData.glyph
              color: Theme.text
              font.family: Theme.fontFamily
              font.pixelSize: parent.modelData.act === "today" ? 11 : 14
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

      // Day grid (6 × 7)
      GridLayout {
        Layout.fillWidth: true
        columns: 7
        rowSpacing: 0
        columnSpacing: 0

        Repeater {
          model: root.dayCells

          Item {
            required property var modelData
            Layout.fillWidth: true
            Layout.preferredHeight: 28

            Rectangle {
              anchors.centerIn: parent
              width: 24
              height: 24
              radius: 12
              color: parent.modelData.isToday ? Theme.accent : "transparent"
            }

            Text {
              anchors.centerIn: parent
              text: parent.modelData.day
              color: parent.modelData.isToday
                  ? "#ffffff"
                  : (parent.modelData.inMonth ? Theme.text : Theme.textMute)
              opacity: parent.modelData.inMonth || parent.modelData.isToday ? 1 : 0.4
              font.family: Theme.fontFamily
              font.pixelSize: 11
              font.weight: parent.modelData.isToday ? Font.DemiBold : Font.Normal
            }
          }
        }
      }

      Rectangle {
        Layout.fillWidth: true
        height: 1
        color: Theme.separator
      }

      // Weather summary — honest states (ready / loading / no location)
      RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spaceSm

        ColumnLayout {
          Layout.fillWidth: true
          spacing: 1

          Text {
            Layout.fillWidth: true
            text: {
              if (Weather.ready)
                return Weather.temperatureText + "  ·  " + Weather.description
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
            visible: Weather.ready
            text: {
              const hi = Math.round(Weather.high) + "°"
              const lo = Math.round(Weather.low) + "°"
              const loc = String(Config.locationName || "")
              return "H " + hi + "  L " + lo + (loc.length ? "  ·  " + loc : "")
            }
            color: Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: 11
            elide: Text.ElideRight
          }
        }
      }
    }
  }

  Keys.onEscapePressed: ShellState.closeCalendar()
}
