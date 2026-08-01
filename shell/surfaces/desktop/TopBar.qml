import Quickshell
import Quickshell.Hyprland
import QtQuick
import QtQuick.Window
import "../../shared"

// Menu bar — thin glass strip (macOS Tahoe-adjacent).
Item {
  id: root
  anchors.fill: parent

  readonly property real dpr: Math.max(1, Screen.devicePixelRatio || 1)
  readonly property int controlH: Math.max(20, Theme.barHeight - 10)
  readonly property int sidePad: 14

  // Only a real battery earns a percent in the bar — a VM / desktop UPower
  // display device reports 0% and would read as a dying laptop.
  readonly property string batteryHint: Power.hasBattery ? (Power.percent + "%") : ""

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
      }
    }

    // Center: date · time · weather — click opens the calendar / today popover
    Rectangle {
      id: centerCluster
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.verticalCenter: parent.verticalCenter
      height: root.controlH
      width: centerRow.implicitWidth + 18
      radius: height / 2
      z: 3
      color: centerMa.containsMouse || ShellState.calendarOpen
          ? (Theme.light ? Qt.rgba(0, 0, 0, 0.06) : Qt.rgba(1, 1, 1, 0.1))
          : "transparent"

      Row {
        id: centerRow
        anchors.centerIn: parent
        spacing: 8

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: Time.text
          color: Theme.text
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSizeSm
          font.weight: Font.Medium
          style: root.barTextStyle
          styleColor: root.barTextStyleColor
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          visible: Weather.ready
          text: "·  " + Weather.temperatureText
          color: Theme.textDim
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSizeSm
          style: root.barTextStyle
          styleColor: root.barTextStyleColor
        }
      }

      MouseArea {
        id: centerMa
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: ShellState.toggleCalendar()
      }
    }

    // Tiling toggle (COSMIC-adjacent) — float ⇄ tile the focused window.
    // Accent = floating (state, not decor); grid glyph = tiled.
    Rectangle {
      id: tileToggle
      anchors.right: statusCluster.left
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

    // Right: status items — calm, not a heavy chip
    Rectangle {
      id: statusCluster
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      height: root.controlH
      width: statusRow.implicitWidth + 14
      radius: height / 2
      z: 2
      color: statusMa.containsMouse || ShellState.controlCenterOpen
          ? (Theme.light ? Qt.rgba(0, 0, 0, 0.06) : Qt.rgba(1, 1, 1, 0.1))
          : "transparent"

      Row {
        id: statusRow
        anchors.centerIn: parent
        spacing: 10

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
          visible: Config.notificationsDnd
          text: "DND"
          color: Theme.accent
          font.family: Theme.fontFamily
          font.pixelSize: 10
          font.weight: Font.DemiBold
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          visible: KeepAwake.active
          text: KeepAwake.mode === "indefinite" ? "Awake" : ("Awake " + KeepAwake.remainingLabel)
          color: Theme.accent
          font.family: Theme.fontFamily
          font.pixelSize: 10
          font.weight: Font.DemiBold
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          visible: root.batteryHint.length > 0
          text: root.batteryHint
          color: Theme.textDim
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSizeSm
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
        onClicked: ShellState.toggleControlCenter()
      }
    }
  }
}
