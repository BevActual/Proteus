pragma Singleton

import Quickshell
import QtQuick

Singleton {
  // Proteus desktop tokens — deep slate + configurable accent/font
  readonly property color bg: "#0f1419"
  readonly property color bgPanel: "#151b23"
  readonly property color bgElevated: "#1c2430"
  readonly property color bgHover: "#243041"
  readonly property color border: "#2a3544"
  readonly property color text: "#e7ecf3"
  readonly property color textDim: "#8b9bb0"
  readonly property color textMute: "#5c6b7e"
  readonly property color accent: Config.accentColor
  readonly property color accentSoft: Qt.rgba(accent.r, accent.g, accent.b, 0.28)
  readonly property color danger: "#e35d6a"

  // Spacing scale
  readonly property int spaceXs: 4
  readonly property int spaceSm: 8
  readonly property int spaceMd: 12
  readonly property int spaceLg: 16
  readonly property int spaceXl: 24

  // Radius scale
  readonly property int radiusSm: 6
  readonly property int radius: 8
  readonly property int radiusMd: 10
  readonly property int radiusLg: 12
  readonly property int radiusXl: 16
  readonly property int radiusPill: 22

  readonly property int barHeight: 40
  readonly property int dockExclusive: 78
  readonly property string fontFamily: Config.fontFamily
  readonly property int fontSize: Config.fontSize
  readonly property int fontSizeSm: Config.fontSizeSm
}
