import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import QtQuick
import QtQuick.Window
import "../../shared"

// Menu bar — thin glass strip (macOS Tahoe-adjacent).
Item {
  id: root
  anchors.fill: parent

  // Owning PanelWindow screen (Spaces strip is monitor-aware).
  property var screen: null

  readonly property real dpr: Math.max(1, Screen.devicePixelRatio || 1)
  readonly property int controlH: Math.max(20, Theme.barHeight - 10)
  readonly property int sidePad: 14

  // Only a real battery earns a percent in the bar — a VM / desktop UPower
  // display device reports 0% and would read as a dying laptop.
  readonly property string batteryHint: Power.hasBattery ? (Power.percent + "%") : ""
  readonly property color statusGlyphColor: Theme.light
      ? Qt.rgba(0.11, 0.11, 0.12, 0.88)
      : Qt.rgba(0.96, 0.96, 0.97, 0.92)

  // Glass plate
  Rectangle {
    anchors.fill: parent
    color: Theme.menuBarFill
    border.width: 0

    Behavior on color {
      ColorAnimation {
        duration: 180
        easing.type: Easing.OutCubic
      }
    }
  }

  // Bottom hairline (hidden when fully clear)
  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: 1
    color: Theme.chromeHairline
    opacity: Theme.chromeClear || Theme.menuBarAlpha < 0.08 ? 0 : Math.min(1, Theme.menuBarAlpha + 0.15)

    Behavior on opacity {
      NumberAnimation {
        duration: 160
        easing.type: Easing.OutCubic
      }
    }
  }

  // Soft text outline when the plate is thin (wallpaper-first legibility floor)
  readonly property int barTextStyle: Theme.menuBarNeedsLegibility ? Text.Outline : Text.Normal
  readonly property color barTextStyleColor: Theme.light
      ? Qt.rgba(1, 1, 1, 0.72)
      : Qt.rgba(0, 0, 0, 0.55)

  Item {
    anchors.fill: parent
    anchors.leftMargin: root.sidePad
    anchors.rightMargin: root.sidePad

    // Left: window controls · app name · workspaces (Beacon lives in the dock)
    Row {
      id: leftRow
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      spacing: 10
      z: 2

      // Traffic lights for the focused window (Hyprland draws no decorations —
      // the bar owns close / minimize / maximize, macOS-style).
      Item {
        id: lights
        anchors.verticalCenter: parent.verticalCenter
        width: lightsRow.implicitWidth
        height: 14
        visible: Hyprland.activeToplevel !== null

        readonly property bool hot: lightsHover.hovered

        HoverHandler {
          id: lightsHover
        }

        Row {
          id: lightsRow
          anchors.verticalCenter: parent.verticalCenter
          spacing: 7

          Repeater {
            model: [
              { fill: "#ff5f57", edge: "#e0443e", glyph: "×", act: "close" },
              { fill: "#febc2e", edge: "#d89e24", glyph: "−", act: "min" },
              { fill: "#28c840", edge: "#1faf33", glyph: "+", act: "max" }
            ]

            Rectangle {
              required property var modelData
              anchors.verticalCenter: parent.verticalCenter
              width: 12
              height: 12
              radius: 6
              color: modelData.fill
              border.width: 1
              border.color: modelData.edge

              Text {
                anchors.centerIn: parent
                visible: lights.hot
                text: parent.modelData.glyph
                color: Qt.rgba(0, 0, 0, 0.55)
                font.pixelSize: 9
                font.bold: true
              }

              MouseArea {
                anchors.fill: parent
                anchors.margins: -2
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (parent.modelData.act === "close")
                    DockApps.closeActiveWindow()
                  else if (parent.modelData.act === "min")
                    DockApps.minimizeActiveWindow()
                  else
                    DockApps.maximizeActiveWindow()
                }
              }
            }
          }
        }
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, Math.max(80, root.width * 0.28))
        text: ActiveWindow.barText
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        font.weight: Font.DemiBold
        elide: Text.ElideRight
        opacity: text.length ? 0.92 : 0
        visible: text.length > 0
        style: root.barTextStyle
        styleColor: root.barTextStyleColor
      }

      Workspaces {
        anchors.verticalCenter: parent.verticalCenter
        screen: root.screen
      }
    }

    // Center: date · time · weather — click opens the calendar / today popover.
    // True viewport center; fades when left/right chrome crowds the mid band.
    Rectangle {
      id: centerCluster
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.verticalCenter: parent.verticalCenter
      height: root.controlH
      // Natural content width; cap so a long weather string can't eat the bar.
      width: Math.min(centerRow.implicitWidth + 22, Math.max(72, root.width * 0.42))
      radius: height / 2
      z: 3
      clip: true

      readonly property bool weatherVisible: Config.weatherEnabled && Weather.hasLocation
          && (Weather.ready || Weather.loading || Weather.error.length > 0)
      // Side chrome budget (no dependency on this cluster's width — avoids flicker).
      readonly property real sideBudget: leftRow.implicitWidth + rightChrome.width
          + (tileToggle.visible ? tileToggle.width + 6 : 0) + root.sidePad * 2 + 40
      readonly property real midClear: root.width - sideBudget
      // Hide weekday/date first when the mid band is tight; keep time (+ weather).
      readonly property bool showDate: midClear >= 200
      // Soft-hide the whole cluster if even a compact time chip would collide.
      readonly property bool crowdedOut: midClear < 88

      opacity: crowdedOut ? 0 : 1
      enabled: !crowdedOut

      Behavior on opacity {
        NumberAnimation {
          duration: 140
          easing.type: Easing.OutCubic
        }
      }

      readonly property bool centerHot: ShellState.calendarOpen || ShellState.weatherOpen
          || clockMa.containsMouse || wxChipMa.containsMouse

      color: centerHot
          ? (ShellState.calendarOpen || ShellState.weatherOpen
              ? Theme.chromeAccentSoft
              : (Theme.light ? Qt.rgba(0, 0, 0, 0.07) : Qt.rgba(1, 1, 1, 0.12)))
          : "transparent"

      Behavior on color {
        ColorAnimation {
          duration: 140
          easing.type: Easing.OutCubic
        }
      }

      Row {
        id: centerRow
        anchors.centerIn: parent
        spacing: 0

        // Date · time → calendar glance
        Item {
          id: clockChip
          width: clockRow.implicitWidth
          height: root.controlH

          Row {
            id: clockRow
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0

            Text {
              anchors.verticalCenter: parent.verticalCenter
              visible: centerCluster.showDate
              text: Time.dateText
              color: Theme.textDim
              font.family: Theme.fontFamily
              font.pixelSize: Theme.fontSizeSm
              font.weight: Font.Normal
              style: root.barTextStyle
              styleColor: root.barTextStyleColor
              opacity: 0.92
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              visible: centerCluster.showDate
              text: "  ·  "
              color: Theme.textMute
              font.family: Theme.fontFamily
              font.pixelSize: Theme.fontSizeSm
              style: root.barTextStyle
              styleColor: root.barTextStyleColor
              opacity: 0.55
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: Time.timeText
              color: Theme.text
              font.family: Theme.fontFamily
              font.pixelSize: Theme.fontSizeSm
              font.weight: Font.DemiBold
              style: root.barTextStyle
              styleColor: root.barTextStyleColor
            }
          }

          MouseArea {
            id: clockMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: ShellState.toggleCalendar()
          }
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          visible: centerCluster.weatherVisible
          text: "  ·  "
          color: Theme.textMute
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSizeSm
          style: root.barTextStyle
          styleColor: root.barTextStyleColor
          opacity: 0.55
        }

        // Weather chip → weather glance (Open Weather app from the panel)
        Item {
          id: wxChip
          visible: centerCluster.weatherVisible
          width: wxRow.implicitWidth
          height: root.controlH

          Row {
            id: wxRow
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0

            Text {
              anchors.verticalCenter: parent.verticalCenter
              visible: Weather.ready
              text: Weather.glyph
              color: Theme.textDim
              font.family: Theme.fontFamily
              font.pixelSize: Theme.fontSizeSm + 1
              style: root.barTextStyle
              styleColor: root.barTextStyleColor
              opacity: 0.9
            }

            Item {
              visible: Weather.ready
              width: 5
              height: 1
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: {
                if (Weather.ready)
                  return Weather.temperatureText
                if (Weather.loading)
                  return "…"
                return "—"
              }
              color: Theme.textDim
              font.family: Theme.fontFamily
              font.pixelSize: Theme.fontSizeSm
              font.weight: Font.Medium
              style: root.barTextStyle
              styleColor: root.barTextStyleColor
            }
          }

          MouseArea {
            id: wxChipMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: ShellState.toggleWeather()
          }
        }
      }
    }

    // Tiling toggle (COSMIC-adjacent) — float ⇄ tile the focused window.
    // Accent = floating (state, not decor); grid glyph = tiled.
    Rectangle {
      id: tileToggle
      anchors.right: rightChrome.left
      anchors.rightMargin: 6
      anchors.verticalCenter: parent.verticalCenter
      height: root.controlH
      width: root.controlH + 8
      radius: height / 2
      z: 2
      visible: Hyprland.activeToplevel !== null
      color: tileMa.containsMouse
          ? (Theme.light ? Qt.rgba(0, 0, 0, 0.06) : Qt.rgba(1, 1, 1, 0.1))
          : "transparent"

      readonly property bool floating: DockApps.activeFloating
      readonly property color glyphColor: floating
          ? Theme.accent
          : (Theme.light ? Qt.rgba(0.11, 0.11, 0.12, 0.88) : Qt.rgba(0.96, 0.96, 0.97, 0.92))

      Item {
        anchors.centerIn: parent
        width: 14
        height: 12

        // Tiled — 2×2 grid
        Grid {
          anchors.fill: parent
          visible: !tileToggle.floating
          columns: 2
          rowSpacing: 2
          columnSpacing: 2

          Repeater {
            model: 4
            Rectangle {
              width: 6
              height: 5
              radius: 1
              color: tileToggle.glyphColor
            }
          }
        }

        // Floating — two offset panes
        Item {
          anchors.fill: parent
          visible: tileToggle.floating

          Rectangle {
            x: 0
            y: 0
            width: 9
            height: 8
            radius: 1.5
            color: "transparent"
            border.width: 1.4
            border.color: tileToggle.glyphColor
            opacity: 0.7
          }
          Rectangle {
            x: 5
            y: 4
            width: 9
            height: 8
            radius: 1.5
            color: tileToggle.glyphColor
          }
        }
      }

      MouseArea {
        id: tileMa
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: DockApps.toggleFloatActiveWindow()
      }
    }

    // Right chrome: app tray · privacy dots · system services · CC
    Item {
      id: rightChrome
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      height: root.controlH
      width: rightRow.implicitWidth
      z: 2

      Row {
        id: rightRow
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8

        // Background apps (1Password, Discord, …) via StatusNotifier
        Row {
          id: trayRow
          anchors.verticalCenter: parent.verticalCenter
          spacing: 6
          visible: SystemTray.items.values.length > 0

          Repeater {
            model: SystemTray.items

            Item {
              id: trayCell
              required property var modelData
              width: 18
              height: root.controlH

              IconImage {
                anchors.centerIn: parent
                source: trayCell.modelData.icon
                implicitSize: 16
                asynchronous: true
              }

              MouseArea {
                anchors.fill: parent
                anchors.margins: -2
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                cursorShape: Qt.PointingHandCursor
                onClicked: mouse => {
                  if (mouse.button === Qt.LeftButton) {
                    if (trayCell.modelData.onlyMenu && trayCell.modelData.hasMenu)
                      trayMenu.open()
                    else
                      trayCell.modelData.activate()
                  } else if (mouse.button === Qt.RightButton && trayCell.modelData.hasMenu) {
                    trayMenu.open()
                  } else if (mouse.button === Qt.MiddleButton) {
                    trayCell.modelData.secondaryActivate()
                  }
                }
              }

              WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => trayCell.modelData.scroll(event.angleDelta.y, false)
              }

              QsMenuAnchor {
                id: trayMenu
                menu: trayCell.modelData.menu
                anchor.item: trayCell
                anchor.edges: Edges.Bottom | Edges.Left
                anchor.gravity: Edges.Bottom | Edges.Left
              }
            }
          }
        }

        // Privacy indicators — mic / camera / screen icons (tinted, not bare dots)
        Row {
          id: privacyRow
          anchors.verticalCenter: parent.verticalCenter
          spacing: 4
          visible: PrivacyIndicators.anyActive

          // Microphone
          Item {
            visible: PrivacyIndicators.mic
            width: 18
            height: root.controlH

            // Capsule + stand
            Item {
              anchors.centerIn: parent
              width: 12
              height: 14

              Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 0
                width: 7
                height: 9
                radius: 3.5
                color: PrivacyIndicators.micColor
              }
              Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 7
                width: 10
                height: 5
                radius: 5
                color: "transparent"
                border.width: 1.4
                border.color: PrivacyIndicators.micColor
              }
              Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 11.5
                width: 1.6
                height: 2.5
                color: PrivacyIndicators.micColor
              }
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: PrivacyIndicators.openPrivacySettings()
            }
          }

          // Camera
          Item {
            visible: PrivacyIndicators.camera
            width: 20
            height: root.controlH

            Item {
              anchors.centerIn: parent
              width: 16
              height: 11

              Rectangle {
                x: 0
                y: 1
                width: 11
                height: 9
                radius: 2
                color: PrivacyIndicators.cameraColor
              }
              // Lens
              Rectangle {
                x: 3
                y: 3.2
                width: 5
                height: 5
                radius: 2.5
                color: Theme.light ? Qt.rgba(1, 1, 1, 0.35) : Qt.rgba(0, 0, 0, 0.35)
              }
              // Viewfinder wedge
              Canvas {
                x: 10
                y: 2
                width: 6
                height: 7
                onPaint: {
                  const ctx = getContext("2d")
                  ctx.reset()
                  ctx.fillStyle = PrivacyIndicators.cameraColor
                  ctx.beginPath()
                  ctx.moveTo(0, 0)
                  ctx.lineTo(6, 3.5)
                  ctx.lineTo(0, 7)
                  ctx.closePath()
                  ctx.fill()
                }
                Component.onCompleted: requestPaint()
              }
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: PrivacyIndicators.openPrivacySettings()
            }
          }

          // Screen capture
          Item {
            visible: PrivacyIndicators.screen
            width: 18
            height: root.controlH

            Item {
              anchors.centerIn: parent
              width: 14
              height: 12

              Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 0
                width: 14
                height: 9
                radius: 1.5
                color: "transparent"
                border.width: 1.5
                border.color: PrivacyIndicators.screenColor

                // Record pip
                Rectangle {
                  anchors.right: parent.right
                  anchors.top: parent.top
                  anchors.margins: 1.5
                  width: 3.5
                  height: 3.5
                  radius: 1.75
                  color: PrivacyIndicators.screenColor
                }
              }
              Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 9
                width: 6
                height: 1.5
                color: PrivacyIndicators.screenColor
              }
              Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 10.5
                width: 9
                height: 1.5
                radius: 0.5
                color: PrivacyIndicators.screenColor
              }
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: PrivacyIndicators.openPrivacySettings()
            }
          }
        }

        // System services + status — click opens Control Center
        Rectangle {
          id: statusCluster
          height: root.controlH
          width: statusRow.implicitWidth + 14
          radius: height / 2
          color: statusMa.containsMouse || ShellState.controlCenterOpen
              ? (Theme.light ? Qt.rgba(0, 0, 0, 0.06) : Qt.rgba(1, 1, 1, 0.1))
              : "transparent"

          Behavior on color {
            ColorAnimation {
              duration: 140
              easing.type: Easing.OutCubic
            }
          }

          Row {
            id: statusRow
            anchors.centerIn: parent
            spacing: 9

        // —— System services (network · bluetooth · sound · battery) ——
        Item {
          id: netChip
          anchors.verticalCenter: parent.verticalCenter
          visible: SystemServices.networkVisible
          width: 16
          height: root.controlH

          readonly property bool hot: SystemServices.wifiSupported
              ? (SystemServices.wifiEnabled && SystemServices.connected && SystemServices.netKind === "wifi")
              : SystemServices.connected
          readonly property color ink: hot ? root.statusGlyphColor : Theme.textMute
          opacity: (SystemServices.wifiSupported && !SystemServices.wifiEnabled) ? 0.4 : 0.92

          // Wi‑Fi arcs (or ethernet link when no radio)
          Canvas {
            id: netCanvas
            anchors.centerIn: parent
            width: 14
            height: 12
            onPaint: {
              const ctx = getContext("2d")
              ctx.reset()
              ctx.strokeStyle = netChip.ink
              ctx.fillStyle = netChip.ink
              ctx.lineWidth = 1.4
              ctx.lineCap = "round"
              if (SystemServices.wifiSupported) {
                const cx = 7, cy = 11
                for (let i = 0; i < 3; i++) {
                  const r = 3 + i * 3
                  ctx.beginPath()
                  ctx.arc(cx, cy, r, Math.PI * 1.2, Math.PI * 1.8)
                  ctx.stroke()
                }
                ctx.beginPath()
                ctx.arc(cx, cy - 1, 1.2, 0, Math.PI * 2)
                ctx.fill()
                if (!SystemServices.wifiEnabled) {
                  ctx.strokeStyle = netChip.ink
                  ctx.beginPath()
                  ctx.moveTo(2, 2)
                  ctx.lineTo(12, 10)
                  ctx.stroke()
                }
              } else {
                // Ethernet: two ports + link
                ctx.strokeRect(1, 2, 5, 4)
                ctx.strokeRect(8, 6, 5, 4)
                ctx.beginPath()
                ctx.moveTo(6, 4)
                ctx.lineTo(8, 8)
                ctx.stroke()
              }
            }
            Connections {
              target: SystemServices
              function onWifiEnabledChanged() { netCanvas.requestPaint() }
              function onWifiSupportedChanged() { netCanvas.requestPaint() }
              function onConnectedChanged() { netCanvas.requestPaint() }
              function onNetKindChanged() { netCanvas.requestPaint() }
            }
            Connections {
              target: Theme
              function onLightChanged() { netCanvas.requestPaint() }
            }
            Component.onCompleted: requestPaint()
          }
        }

        Item {
          id: btChip
          anchors.verticalCenter: parent.verticalCenter
          visible: SystemServices.bluetoothVisible
          width: 12
          height: root.controlH
          opacity: SystemServices.btPowered ? 0.92 : 0.4

          readonly property color ink: SystemServices.btPowered
              ? root.statusGlyphColor
              : Theme.textMute

          Canvas {
            id: btCanvas
            anchors.centerIn: parent
            width: 10
            height: 14
            onPaint: {
              const ctx = getContext("2d")
              ctx.reset()
              ctx.strokeStyle = btChip.ink
              ctx.lineWidth = 1.5
              ctx.lineCap = "round"
              ctx.lineJoin = "round"
              // Bluetooth rune
              ctx.beginPath()
              ctx.moveTo(5, 1)
              ctx.lineTo(5, 13)
              ctx.moveTo(5, 1)
              ctx.lineTo(9, 4)
              ctx.lineTo(5, 7)
              ctx.lineTo(9, 10)
              ctx.lineTo(5, 13)
              ctx.moveTo(5, 7)
              ctx.lineTo(1, 4)
              ctx.moveTo(5, 7)
              ctx.lineTo(1, 10)
              ctx.stroke()
            }
            Connections {
              target: SystemServices
              function onBtPoweredChanged() { btCanvas.requestPaint() }
            }
            Connections {
              target: Theme
              function onLightChanged() { btCanvas.requestPaint() }
            }
            Component.onCompleted: requestPaint()
          }
        }

        Item {
          id: volChip
          anchors.verticalCenter: parent.verticalCenter
          width: 16
          height: root.controlH

          readonly property bool quiet: SystemServices.muted || SystemServices.volume <= 0
          readonly property color ink: quiet ? Theme.textMute : root.statusGlyphColor
          opacity: quiet ? 0.5 : 0.92

          Canvas {
            id: volCanvas
            anchors.centerIn: parent
            width: 15
            height: 12
            onPaint: {
              const ctx = getContext("2d")
              ctx.reset()
              ctx.fillStyle = volChip.ink
              ctx.strokeStyle = volChip.ink
              ctx.lineWidth = 1.3
              ctx.lineCap = "round"
              // Speaker body
              ctx.beginPath()
              ctx.moveTo(1, 4)
              ctx.lineTo(4, 4)
              ctx.lineTo(8, 1)
              ctx.lineTo(8, 11)
              ctx.lineTo(4, 8)
              ctx.lineTo(1, 8)
              ctx.closePath()
              ctx.fill()
              if (volChip.quiet) {
                ctx.beginPath()
                ctx.moveTo(10, 3)
                ctx.lineTo(14, 9)
                ctx.moveTo(14, 3)
                ctx.lineTo(10, 9)
                ctx.stroke()
              } else {
                const rings = SystemServices.volume < 34 ? 1 : (SystemServices.volume < 67 ? 2 : 3)
                for (let i = 0; i < rings; i++) {
                  const r = 3 + i * 2.2
                  ctx.beginPath()
                  ctx.arc(8, 6, r, -Math.PI * 0.35, Math.PI * 0.35)
                  ctx.stroke()
                }
              }
            }
            Connections {
              target: SystemServices
              function onVolumeChanged() { volCanvas.requestPaint() }
              function onMutedChanged() { volCanvas.requestPaint() }
            }
            Connections {
              target: Theme
              function onLightChanged() { volCanvas.requestPaint() }
            }
            Component.onCompleted: requestPaint()
          }

          WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => {
              const d = event.angleDelta.y
              if (d > 0)
                Audio.stepVolume(5)
              else if (d < 0)
                Audio.stepVolume(-5)
              SystemServices.refresh()
            }
          }
        }

        Item {
          id: battChip
          anchors.verticalCenter: parent.verticalCenter
          visible: Power.hasBattery && Power.percent >= 0
          width: battRow.implicitWidth
          height: root.controlH

          Row {
            id: battRow
            anchors.centerIn: parent
            spacing: 4

            // Tiny battery outline + fill level
            Item {
              anchors.verticalCenter: parent.verticalCenter
              width: 16
              height: 9

              Rectangle {
                anchors.fill: parent
                anchors.rightMargin: 2
                radius: 1.5
                color: "transparent"
                border.width: 1.2
                border.color: Power.percent <= 15 && Power.onBattery
                    ? Theme.accent
                    : root.statusGlyphColor
                opacity: 0.85

                Rectangle {
                  anchors.left: parent.left
                  anchors.leftMargin: 1.5
                  anchors.verticalCenter: parent.verticalCenter
                  height: parent.height - 3
                  width: Math.max(1, (parent.width - 3) * Math.max(0.08, Power.percent / 100))
                  radius: 0.8
                  color: Power.percent <= 15 && Power.onBattery
                      ? Theme.accent
                      : root.statusGlyphColor
                  opacity: 0.9
                }
              }

              Rectangle {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 1.5
                height: 4
                radius: 0.5
                color: root.statusGlyphColor
                opacity: 0.7
              }
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: root.batteryHint
              color: Theme.textDim
              font.family: Theme.fontFamily
              font.pixelSize: Theme.fontSizeSm
              style: root.barTextStyle
              styleColor: root.barTextStyleColor
            }
          }
        }

        Rectangle {
          // Unread clears when Control Center opens (Notifications.markAllRead).
          visible: Notifications.unreadCount > 0 && !ShellState.controlCenterOpen
          anchors.verticalCenter: parent.verticalCenter
          width: Math.max(16, badgeLabel.implicitWidth + 8)
          height: 16
          radius: 8
          color: Theme.accent
          Text {
            id: badgeLabel
            anchors.centerIn: parent
            text: Notifications.unreadCount > 9 ? "9+" : String(Notifications.unreadCount)
            color: "#fff"
            font.pixelSize: 10
            font.weight: Font.DemiBold
          }
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          visible: FocusMode.active || Config.notificationsDnd
          text: FocusMode.active ? ("Focus" + (FocusMode.shortLabel !== "On" && FocusMode.shortLabel !== "Off" ? (" " + FocusMode.shortLabel) : "")) : "DND"
          color: Theme.accent
          font.family: Theme.fontFamily
          font.pixelSize: 10
          font.weight: Font.DemiBold
          style: root.barTextStyle
          styleColor: root.barTextStyleColor
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          visible: KeepAwake.active
          text: KeepAwake.mode === "indefinite" ? "Awake" : ("Awake " + KeepAwake.remainingLabel)
          color: Theme.accent
          font.family: Theme.fontFamily
          font.pixelSize: 10
          font.weight: Font.DemiBold
          style: root.barTextStyle
          styleColor: root.barTextStyleColor
        }

        // Control Center glyph — three mini sliders with staggered knobs.
        // Same language as ThemeSlider (dim track · bright round knob) and the
        // CC panel itself; accent only while open (accent = state, not decor).
        Item {
          id: ccGlyph
          anchors.verticalCenter: parent.verticalCenter
          width: 16
          height: 13

          readonly property color glyphColor: ShellState.controlCenterOpen
              ? Theme.accent
              : (Theme.light ? Qt.rgba(0.11, 0.11, 0.12, 0.88) : Qt.rgba(0.96, 0.96, 0.97, 0.92))

          Behavior on opacity {
            NumberAnimation {
              duration: 120
            }
          }

          Repeater {
            // knobX as a fraction of the track — staggered like live sliders;
            // `ko` is where each knob settles while the CC is open
            model: [
              { cy: 2, k: 0.68, ko: 0.3 },
              { cy: 6.5, k: 0.25, ko: 0.75 },
              { cy: 11, k: 0.52, ko: 0.4 }
            ]

            Item {
              required property var modelData
              anchors.left: ccGlyph.left
              anchors.right: ccGlyph.right
              y: modelData.cy - 3
              height: 6

              // Track
              Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 1.6
                radius: 0.8
                color: ccGlyph.glyphColor
                opacity: 0.45
              }

              // Knob — slides to a new position while the CC is open
              Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                x: (ccGlyph.width - width)
                    * (ShellState.controlCenterOpen ? modelData.ko : modelData.k)
                width: 5.5
                height: 5.5
                radius: width / 2
                color: ccGlyph.glyphColor

                Behavior on x {
                  NumberAnimation {
                    duration: 160
                    easing.type: Easing.OutCubic
                  }
                }
              }
            }
          }
        }
      }

          MouseArea {
            id: statusMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              const mon = Hyprland.monitorFor(root.screen)
              ShellState.toggleControlCenter(mon ? mon.name : "")
            }
          }
        }
      }
    }
  }
}
