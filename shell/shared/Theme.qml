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

  // Glass plate alpha for dock — tracks Opacity smoothly.
  // With blur: soft floor so frosted glass still reads; without: linear to clear.
  readonly property real glassAlpha: {
    if (chromeClear)
      return 0
    if (blur)
      return Math.max(0.20, Math.min(0.90, chromeAlpha * 0.82 + 0.06))
    return chromeAlpha
  }

  // Menu bar: wallpaper-first (Tahoe-adjacent) — clearer than dock at same Opacity.
  // Soft floor only with blur so text can keep a legibility plate; 0% still clears.
  readonly property real menuBarAlpha: {
    if (chromeClear)
      return 0
    if (blur)
      return Math.max(0.05, Math.min(0.48, chromeAlpha * 0.38 + 0.03))
    return Math.max(0, Math.min(0.72, chromeAlpha * 0.42))
  }
  readonly property bool menuBarNeedsLegibility: menuBarAlpha > 0.001 && menuBarAlpha < 0.32

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

  // Chrome surfaces — alpha tracks Opacity (0 = fully clear plate)
  readonly property color panelFill: Qt.rgba(bgPanel.r, bgPanel.g, bgPanel.b, chromeAlpha)
  readonly property color elevatedFill: Qt.rgba(bgElevated.r, bgElevated.g, bgElevated.b, chromeAlpha)
  readonly property color chromeHover: Qt.rgba(bgHover.r, bgHover.g, bgHover.b, chromeAlpha)
  readonly property color chromeBorder: Qt.rgba(border.r, border.g, border.b, Math.min(1, chromeAlpha + (blur ? 0.08 : 0)))
  readonly property color chromeAccentFill: Qt.rgba(accent.r, accent.g, accent.b, chromeAlpha)
  readonly property color chromeAccentSoft: Qt.rgba(accent.r, accent.g, accent.b, chromeAlpha * (light ? 0.22 : 0.28))
  readonly property color scrimFill: Qt.rgba(bg.r, bg.g, bg.b, (light ? 0.28 : 0.45) * Math.max(chromeAlpha, 0.4))

  // Menu bar — wallpaper-first plate (clearer than dock at same Opacity)
  readonly property color menuBarFill: light
      ? Qt.rgba(0.96, 0.96, 0.97, menuBarAlpha)
      : Qt.rgba(0.11, 0.11, 0.12, menuBarAlpha)
  // Dock keeps stronger frost (glassAlpha); same RGB family as bar.
  readonly property color dockPlateFill: light
      ? Qt.rgba(0.96, 0.96, 0.97, glassAlpha)
      : Qt.rgba(0.11, 0.11, 0.12, glassAlpha)
  // Floating menus / context plates — dock glass family (CHROME · #1149)
  readonly property color menuPlateFill: dockPlateFill
  readonly property color chromeHairline: light
      ? Qt.rgba(0, 0, 0, chromeClear ? 0 : (blur ? 0.10 : 0.12))
      : Qt.rgba(1, 1, 1, chromeClear ? 0 : (blur ? 0.08 : 0.10))
  // Soft top specular reserved for masked glass (dock shelf no longer paints a
  // child strip — Qt radius clip left a hard straight highlight on top).
  readonly property color dockPlateSpecular: light
      ? Qt.rgba(1, 1, 1, chromeClear ? 0 : (blur ? 0.22 : 0.10))
      : Qt.rgba(1, 1, 1, chromeClear ? 0 : (blur ? 0.14 : 0.06))

  // Squircle icon plate — macOS Tahoe Icon & widget style: Default / Dark / Clear / Tinted
  readonly property color iconPlateDefault: light
      ? Qt.rgba(0.86, 0.87, 0.90, 0.92)
      : Qt.rgba(0.18, 0.19, 0.22, 0.88)
  readonly property color iconPlateDark: Qt.rgba(0.08, 0.08, 0.09, 0.94)
  readonly property color iconPlateFill: {
    const mode = Config.iconPlateStyle
    if (mode === "clear")
      return Qt.rgba(0, 0, 0, 0)
    if (mode === "dark")
      return iconPlateDark
    if (mode === "tinted") {
      const h = Config.normalizeAccentHex(Config.iconPlateCustom)
      if (h.length)
        return h
      return Qt.rgba(accent.r, accent.g, accent.b, 0.88)
    }
    // default — chrome-aware neutral plate
    return iconPlateDefault
  }
  // Keep alias used during dogfood
  readonly property color iconPlateAuto: iconPlateDefault
  readonly property real iconGlyphScaleApp: 0.72
  readonly property real iconGlyphScaleBrand: 0.78
  readonly property real iconFrameScale: 0.98
  // Continuous-corner ratio (macOS icon squircle); dock shelf uses the same language.
  readonly property real squircleCornerRatio: 0.2237

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
  // Match Dock.qml panel footprint (shelf + magnify headroom) + gap
  readonly property int dockGap: 12
  readonly property int dockPanelHeight: {
    const icon = dockIconSize
    const padTop = Math.max(6, Math.round(icon * 0.14))
    const padBottom = Math.max(8, Math.round(icon * 0.18))
    const tipH = 22
    const tipGap = 10
    const shelf = icon + padTop + padBottom
    const magHeadroom = (dockIconMax - icon) + tipH + tipGap + 12
    return Math.max(shelf + magHeadroom, dockExclusive + 24)
  }
  readonly property int dockReserved: dockPanelHeight + dockGap
  readonly property string fontFamily: Config.fontFamily
  readonly property int fontSize: Config.fontSize
  readonly property int fontSizeSm: Config.fontSizeSm
}
