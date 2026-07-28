pragma Singleton

import Quickshell
import QtQuick

Singleton {
  // Proteus tokens — Apple-inspired System Settings surfaces + chrome opacity
  readonly property bool light: Config.chromeMode === "light"
  readonly property real chromeAlpha: {
    const a = Number(Config.chromeOpacity)
    return isFinite(a) ? Math.max(0, Math.min(1, a)) : 1
  }
  readonly property bool blur: Config.chromeBlur
  readonly property bool chromeClear: chromeAlpha < 0.01

  // Grouped-background canvas; elevated = inset list cards
  readonly property color bg: light ? "#f2f2f7" : "#000000"
  readonly property color bgPanel: light ? "#e8e8ed" : "#1c1c1e"
  readonly property color bgElevated: light ? "#ffffff" : "#1c1c1e"
  readonly property color bgHover: light ? "#e5e5ea" : "#2c2c2e"
  readonly property color border: light ? "#d1d1d6" : "#2c2c2e"
  readonly property color separator: light ? Qt.rgba(0.24, 0.24, 0.26, 0.29) : Qt.rgba(1, 1, 1, 0.1)
  readonly property color text: light ? "#1c1c1e" : "#f5f5f7"
  readonly property color textDim: light ? "#636366" : "#98989d"
  readonly property color textMute: light ? "#8e8e93" : "#636366"
  readonly property color accent: Config.accentColor
  readonly property color accentSoft: Qt.rgba(accent.r, accent.g, accent.b, light ? 0.14 : 0.22)
  readonly property color danger: "#ff453a"

  // Chrome surfaces — alpha tracks Transparency (0 = fully clear plate)
  readonly property color panelFill: Qt.rgba(bgPanel.r, bgPanel.g, bgPanel.b, chromeAlpha)
  readonly property color elevatedFill: Qt.rgba(bgElevated.r, bgElevated.g, bgElevated.b, chromeAlpha)
  readonly property color chromeHover: Qt.rgba(bgHover.r, bgHover.g, bgHover.b, chromeAlpha)
  readonly property color chromeBorder: Qt.rgba(border.r, border.g, border.b, chromeAlpha)
  readonly property color chromeAccentFill: Qt.rgba(accent.r, accent.g, accent.b, chromeAlpha)
  readonly property color chromeAccentSoft: Qt.rgba(accent.r, accent.g, accent.b, chromeAlpha * (light ? 0.22 : 0.28))
  readonly property color scrimFill: Qt.rgba(bg.r, bg.g, bg.b, (light ? 0.28 : 0.45) * Math.max(chromeAlpha, 0.4))

  readonly property int spaceXs: 4
  readonly property int spaceSm: 8
  readonly property int spaceMd: 12
  readonly property int spaceLg: 16
  readonly property int spaceXl: 24

  readonly property int radiusSm: 6
  readonly property int radius: 8
  readonly property int radiusMd: 10
  readonly property int radiusLg: 12
  readonly property int radiusXl: 16
  readonly property int radiusPill: 22

  readonly property int barHeight: {
    const h = Number(Config.barHeight)
    return isFinite(h) ? Math.max(28, Math.min(52, Math.round(h))) : 34
  }
  readonly property int dockIconSize: {
    const s = Number(Config.dockIconSize)
    return isFinite(s) ? Math.max(36, Math.min(72, Math.round(s))) : 48
  }
  readonly property int dockIconMax: Math.round(dockIconSize * 1.45)
  // Reserved space above the shelf for exclusive zone
  readonly property int dockExclusive: dockIconSize + 32
  readonly property string fontFamily: Config.fontFamily
  readonly property int fontSize: Config.fontSize
  readonly property int fontSizeSm: Config.fontSizeSm
}
