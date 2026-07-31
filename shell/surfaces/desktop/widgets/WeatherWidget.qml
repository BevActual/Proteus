import QtQuick
import QtQuick.Layouts
import "../../../shared"

// Current conditions for the system location (Settings → Date & time → Location).
// Shared by the lock and desktop surfaces — see Widgets.widgetCatalog.
Item {
  id: root
  property string size: "sm"
  property bool showWhenIdle: true
  // Desktop only: click opens the calendar popover (weather summary) or,
  // without a location, Settings → Date & time to set one.
  property bool interactive: false

  implicitWidth: card.implicitWidth
  implicitHeight: card.implicitHeight
  width: parent ? Math.min(parent.width, size === "lg" ? 280 : (size === "md" ? 200 : 140)) : 140
  height: implicitHeight

  readonly property bool detailed: size === "lg" || size === "md"

  Rectangle {
    id: card
    anchors.left: parent.left
    anchors.right: parent.right
    implicitHeight: body.implicitHeight + 20
    radius: 16
    color: Qt.rgba(28 / 255, 28 / 255, 30 / 255, 0.72)
    border.width: 1
    border.color: wxMa.containsMouse && root.interactive
        ? Qt.rgba(1, 1, 1, 0.25) : Qt.rgba(1, 1, 1, 0.1)

    MouseArea {
      id: wxMa
      anchors.fill: parent
      visible: root.interactive
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        if (Weather.hasLocation)
          ShellState.toggleCalendar()
        else
          ShellState.openSettings("datetime")
      }
      onPressAndHold: ShellState.enterDesktopCustomize()
    }

    ColumnLayout {
      id: body
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: 12
      spacing: 6

      RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Text {
          text: Weather.hasLocation ? Weather.glyph : "◌"
          color: Qt.rgba(1, 1, 1, 0.92)
          font.pixelSize: root.detailed ? 26 : 20
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: 1

          Text {
            Layout.fillWidth: true
            text: Weather.ready ? Weather.temperatureText : "—"
            color: Qt.rgba(1, 1, 1, 0.92)
            font.family: Theme.fontFamily
            font.pixelSize: root.detailed ? 22 : 18
            font.weight: Font.Medium
            elide: Text.ElideRight
          }

          Text {
            Layout.fillWidth: true
            visible: root.detailed
            text: Weather.hasLocation ? Config.locationName : "Set a location in Settings"
            color: Qt.rgba(1, 1, 1, 0.5)
            font.family: Theme.fontFamily
            font.pixelSize: 11
            elide: Text.ElideRight
          }
        }
      }

      Text {
        Layout.fillWidth: true
        visible: Weather.hasLocation
        text: Weather.ready ? Weather.description : Weather.summary
        color: Qt.rgba(1, 1, 1, 0.62)
        font.family: Theme.fontFamily
        font.pixelSize: 12
        elide: Text.ElideRight
      }

      // High/low and feels-like only earn their space at larger sizes.
      RowLayout {
        Layout.fillWidth: true
        visible: root.detailed && Weather.ready
        spacing: 10

        Text {
          text: "H " + Math.round(Weather.high) + "°"
          color: Qt.rgba(1, 1, 1, 0.5)
          font.family: Theme.fontFamily
          font.pixelSize: 11
        }
        Text {
          text: "L " + Math.round(Weather.low) + "°"
          color: Qt.rgba(1, 1, 1, 0.5)
          font.family: Theme.fontFamily
          font.pixelSize: 11
        }
        Text {
          Layout.fillWidth: true
          visible: root.size === "lg"
          text: "Feels " + Math.round(Weather.apparent) + "°"
          color: Qt.rgba(1, 1, 1, 0.5)
          font.family: Theme.fontFamily
          font.pixelSize: 11
          elide: Text.ElideRight
        }
      }

      Text {
        Layout.fillWidth: true
        visible: root.size === "lg" && Weather.ready
        text: "Wind " + Math.round(Weather.windSpeed) + " " + Weather.windUnit
            + " · Humidity " + Weather.humidity + "%"
        color: Qt.rgba(1, 1, 1, 0.42)
        font.family: Theme.fontFamily
        font.pixelSize: 11
        elide: Text.ElideRight
      }
    }
  }
}
