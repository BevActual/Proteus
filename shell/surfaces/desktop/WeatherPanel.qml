import Quickshell
import QtQuick
import QtQuick.Layouts
import "../../shared"

// Menu-bar weather glance — Proteus location/forecast (Open-Meteo).
// “Open Weather” hands off to gnome-weather (or Settings if missing).
Item {
  id: root
  anchors.fill: parent

  readonly property bool openState: ShellState.weatherOpen
  property real openProgress: 0
  readonly property bool stillVisible: openState || openProgress > 0.001

  visible: stillVisible

  Behavior on openProgress {
    NumberAnimation {
      duration: 200
      easing.type: Easing.OutCubic
    }
  }

  onOpenStateChanged: {
    openProgress = openState ? 1 : 0
    if (openState) {
      if (Weather.hasLocation && Config.weatherEnabled)
        Weather.refresh()
      forceActiveFocus()
    }
  }
  Component.onCompleted: {
    if (openState)
      openProgress = 1
  }

  Rectangle {
    anchors.fill: parent
    color: Theme.scrimFill
    opacity: root.openProgress
    MouseArea {
      anchors.fill: parent
      onClicked: ShellState.closeWeather()
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

      Text {
        Layout.fillWidth: true
        text: String(Config.locationName || "Weather")
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: 15
        font.weight: Font.DemiBold
        elide: Text.ElideRight
      }

      // Current conditions hero
      RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spaceMd

        Text {
          text: Weather.ready ? Weather.glyph : "◌"
          color: Theme.text
          font.family: Theme.fontFamily
          font.pixelSize: 36
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: 2

          Text {
            Layout.fillWidth: true
            text: {
              if (Weather.ready)
                return Weather.temperatureText
              if (Weather.loading)
                return "…"
              if (!Config.weatherEnabled)
                return "Weather off"
              return "—"
            }
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: 28
            font.weight: Font.DemiBold
          }

          Text {
            Layout.fillWidth: true
            text: {
              if (Weather.ready)
                return Weather.description
              if (Weather.error.length)
                return Weather.error
              if (Weather.loading)
                return "Updating…"
              return "No conditions yet"
            }
            color: Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: 13
            elide: Text.ElideRight
          }
        }
      }

      Text {
        Layout.fillWidth: true
        visible: Weather.ready
        text: {
          const hi = Math.round(Weather.high)
          const lo = Math.round(Weather.low)
          const feel = Math.round(Weather.apparent)
          return "H " + hi + Weather.tempUnit
              + "  ·  L " + lo + Weather.tempUnit
              + "  ·  Feels " + feel + Weather.tempUnit
        }
        color: Theme.textDim
        font.family: Theme.fontFamily
        font.pixelSize: 12
      }

      Text {
        Layout.fillWidth: true
        visible: Weather.ready && (Weather.sunrise.length || Weather.humidity > 0)
        text: {
          const parts = []
          const rise = Weather.clockFromIso(Weather.sunrise)
          const set = Weather.clockFromIso(Weather.sunset)
          if (rise.length && set.length)
            parts.push("↑ " + rise + "  ↓ " + set)
          if (Weather.humidity > 0)
            parts.push(Weather.humidity + "% humidity")
          if (Weather.windSpeed > 0)
            parts.push(Math.round(Weather.windSpeed) + " " + Weather.windUnit)
          return parts.join("  ·  ")
        }
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: 11
        wrapMode: Text.WordWrap
      }

      Rectangle {
        Layout.fillWidth: true
        height: 1
        color: Theme.separator
        visible: Weather.hasForecast
      }

      Text {
        visible: Weather.hasForecast
        text: "Next days"
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: 11
        font.weight: Font.Medium
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: 4
        visible: Weather.hasForecast

        Repeater {
          model: Math.min(5, Weather.forecast.length)

          Rectangle {
            required property int index
            Layout.fillWidth: true
            Layout.preferredHeight: dayCol.implicitHeight + 10
            radius: Theme.radiusMd
            color: Theme.elevatedFill
            border.width: 1
            border.color: Theme.chromeBorder

            ColumnLayout {
              id: dayCol
              anchors.centerIn: parent
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
                font.pixelSize: 13
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
                font.pixelSize: 11
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

      // Handoff to full Weather app
      Rectangle {
        Layout.fillWidth: true
        implicitHeight: handoffCol.implicitHeight + 12
        radius: Theme.radiusMd
        color: Theme.elevatedFill
        border.width: 1
        border.color: Theme.chromeBorder

        ColumnLayout {
          id: handoffCol
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.margins: 10
          spacing: 4

          Text {
            Layout.fillWidth: true
            text: "Maps, multi-city, and richer forecasts"
            color: Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: 11
            wrapMode: Text.WordWrap
          }

          Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 30
            radius: Theme.radiusMd
            color: openWxMa.containsMouse ? Theme.chromeAccentSoft : Theme.chromeHover

            Text {
              anchors.centerIn: parent
              text: ShellState.weatherAppAvailable ? "Open Weather" : "Open Date & weather"
              color: Theme.accent
              font.family: Theme.fontFamily
              font.pixelSize: 12
              font.weight: Font.DemiBold
            }

            MouseArea {
              id: openWxMa
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (ShellState.weatherAppAvailable)
                  ShellState.openWeatherApp()
                else
                  ShellState.openDateTimeSettings()
              }
            }
          }
        }
      }

      Text {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        text: "Location & units in Date, time & weather"
        color: locMa.containsMouse ? Theme.accent : Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: 11

        MouseArea {
          id: locMa
          anchors.fill: parent
          anchors.margins: -4
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: ShellState.openDateTimeSettings()
        }
      }

      Text {
        Layout.fillWidth: true
        visible: !ShellState.weatherAppAvailable
        text: "Install gnome-weather for the full Weather app"
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: 10
        wrapMode: Text.WordWrap
      }
    }
  }

  Keys.onEscapePressed: ShellState.closeWeather()
}
