import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "../../../shared"

// World clock — time in another city. Multi-instance: add one per place.
// Remote time comes from `TZ=<zone> date` (glibc owns the tz database — no
// hand-rolled DST rules); refreshed on a short timer while visible.
Item {
  id: root
  property string size: "sm"
  property bool showWhenIdle: true
  property bool interactive: false
  property var widgetData: null

  readonly property string tzId: widgetData ? String(widgetData.tzId || "UTC") : "UTC"
  readonly property string tzLabel: widgetData ? String(widgetData.tzLabel || "UTC") : "UTC"
  readonly property string widgetId: widgetData ? String(widgetData.id) : ""

  property string timeText: "—"
  property string dayText: ""
  property string deltaText: ""
  property bool pickerOpen: false

  readonly property var cities: [
    { label: "UTC", tz: "UTC" },
    { label: "New York", tz: "America/New_York" },
    { label: "Chicago", tz: "America/Chicago" },
    { label: "Denver", tz: "America/Denver" },
    { label: "Los Angeles", tz: "America/Los_Angeles" },
    { label: "Honolulu", tz: "Pacific/Honolulu" },
    { label: "São Paulo", tz: "America/Sao_Paulo" },
    { label: "London", tz: "Europe/London" },
    { label: "Paris", tz: "Europe/Paris" },
    { label: "Berlin", tz: "Europe/Berlin" },
    { label: "Moscow", tz: "Europe/Moscow" },
    { label: "Dubai", tz: "Asia/Dubai" },
    { label: "Delhi", tz: "Asia/Kolkata" },
    { label: "Singapore", tz: "Asia/Singapore" },
    { label: "Shanghai", tz: "Asia/Shanghai" },
    { label: "Tokyo", tz: "Asia/Tokyo" },
    { label: "Seoul", tz: "Asia/Seoul" },
    { label: "Sydney", tz: "Australia/Sydney" },
    { label: "Auckland", tz: "Pacific/Auckland" }
  ]

  function refresh() {
    tzProc.running = false
    tzProc.running = true
  }

  onTzIdChanged: refresh()
  Component.onCompleted: refresh()

  Timer {
    interval: 30 * 1000
    repeat: true
    running: root.visible
    onTriggered: root.refresh()
  }

  function offsetMinutes(z) {
    // "+0930" → 570
    const sign = z.charAt(0) === "-" ? -1 : 1
    const hh = parseInt(z.slice(1, 3), 10) || 0
    const mm = parseInt(z.slice(3, 5), 10) || 0
    return sign * (hh * 60 + mm)
  }

  Process {
    id: tzProc
    command: [
      "bash",
      "-c",
      "TZ='" + root.tzId.replace(/'/g, "") + "' date '+%I:%M %p|%a|%z'; date '+%z'"
    ]
    stdout: StdioCollector {
      onStreamFinished: {
        const lines = text.trim().split("\n")
        if (lines.length < 2)
          return
        const parts = lines[0].split("|")
        if (parts.length < 3)
          return
        root.timeText = parts[0].replace(/^0/, "")
        root.dayText = parts[1]
        const dm = root.offsetMinutes(parts[2]) - root.offsetMinutes(lines[1].trim())
        if (dm === 0) {
          root.deltaText = "Local time"
        } else {
          const h = dm / 60
          const s = (h > 0 ? "+" : "−") + (Number.isInteger(h) ? Math.abs(h) : Math.abs(h).toFixed(1))
          root.deltaText = s + "h"
        }
      }
    }
    stderr: StdioCollector {}
  }

  implicitWidth: card.implicitWidth
  implicitHeight: card.implicitHeight
  width: parent ? Math.min(parent.width, size === "lg" ? 280 : (size === "md" ? 200 : 150)) : 150
  height: implicitHeight

  Rectangle {
    id: card
    anchors.left: parent.left
    anchors.right: parent.right
    implicitHeight: body.implicitHeight + 20
    radius: 16
    color: Qt.rgba(28 / 255, 28 / 255, 30 / 255, 0.72)
    border.width: 1
    border.color: hoverMa.containsMouse && root.interactive
        ? Qt.rgba(1, 1, 1, 0.25) : Qt.rgba(1, 1, 1, 0.1)

    ColumnLayout {
      id: body
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: 12
      spacing: 2

      RowLayout {
        Layout.fillWidth: true
        Text {
          Layout.fillWidth: true
          text: root.tzLabel
          color: Qt.rgba(1, 1, 1, 0.55)
          font.family: Theme.fontFamily
          font.pixelSize: 11
          font.weight: Font.DemiBold
          elide: Text.ElideRight
        }
        Text {
          visible: root.interactive
          text: "▾"
          color: Qt.rgba(1, 1, 1, 0.42)
          font.pixelSize: 10
        }
      }

      Text {
        text: root.timeText
        color: "#f5f5f7"
        font.family: Theme.fontFamily
        font.pixelSize: root.size === "sm" ? 22 : 26
        font.weight: Font.Light
      }

      Text {
        Layout.fillWidth: true
        text: root.dayText.length ? (root.dayText + "  ·  " + root.deltaText) : ""
        color: Qt.rgba(1, 1, 1, 0.5)
        font.family: Theme.fontFamily
        font.pixelSize: 11
        elide: Text.ElideRight
      }
    }

    MouseArea {
      id: hoverMa
      anchors.fill: parent
      visible: root.interactive
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.pickerOpen = !root.pickerOpen
      onPressAndHold: {
        root.pickerOpen = false
        ShellState.enterDesktopCustomize()
      }
    }
  }

  // City picker — drops below the card (desktop only, click to choose)
  Rectangle {
    visible: root.pickerOpen && root.interactive
    anchors.top: card.bottom
    anchors.topMargin: 6
    anchors.left: parent.left
    anchors.right: parent.right
    height: 230
    radius: 14
    color: Qt.rgba(28 / 255, 28 / 255, 30 / 255, 0.96)
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.12)
    clip: true
    z: 30

    Flickable {
      anchors.fill: parent
      anchors.margins: 6
      contentHeight: cityCol.implicitHeight
      clip: true

      Column {
        id: cityCol
        width: parent.width

        Repeater {
          model: root.cities

          Rectangle {
            required property var modelData
            width: cityCol.width
            height: 30
            radius: 8
            color: cityMa.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : "transparent"

            Text {
              anchors.left: parent.left
              anchors.leftMargin: 8
              anchors.verticalCenter: parent.verticalCenter
              text: parent.modelData.label
              color: parent.modelData.tz === root.tzId ? Theme.accent : "#f5f5f7"
              font.family: Theme.fontFamily
              font.pixelSize: 12
              font.weight: parent.modelData.tz === root.tzId ? Font.DemiBold : Font.Normal
            }

            MouseArea {
              id: cityMa
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                root.pickerOpen = false
                if (root.widgetId.length)
                  Widgets.patchDesktopWidget(root.widgetId, {
                    tzId: parent.modelData.tz,
                    tzLabel: parent.modelData.label
                  })
              }
            }
          }
        }
      }
    }
  }
}
