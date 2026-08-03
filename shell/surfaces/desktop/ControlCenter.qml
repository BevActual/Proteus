import Quickshell
import Quickshell.Services.UPower
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../shared"

// Combined notifications + quick settings (macOS-style Control Center).
// Owns its own open/close motion: the layer window stays mapped while
// `stillVisible` so the exit animation can play (DesktopShell binds to it).
Item {
  id: root
  anchors.fill: parent

  readonly property bool openState: ShellState.controlCenterOpen
  // Drive openProgress from onOpenStateChanged (not a ternary binding) so
  // Behavior can animate the close before stillVisible unmaps the layer.
  property real openProgress: 0
  readonly property bool stillVisible: openState || openProgress > 0.001
  // Pad focus: volume | focus | posture | glance | lock | shot | settings
  property int padIndex: 0
  readonly property string postureSlot: (ShellState.consoleSurfaceActive
      || ShellState.hostSurfaceActive) ? "desktop" : "console"
  readonly property var padSlots: ["volume", "focus", postureSlot, "glance", "lock", "shot", "settings"]
  property bool shotMenuOpen: false

  visible: stillVisible

  function runScreenshot(mode) {
    ShellState.closeControlCenter()
    const m = mode === "region" ? "region" : "screen"
    const delay = m === "region" ? "0.35" : "0.2"
    Quickshell.execDetached({
      command: [
        "bash",
        "-lc",
        "sleep " + delay + "; "
            + "if command -v proteus-screenshot >/dev/null 2>&1; then "
            + "proteus-screenshot " + m + "; "
            + "elif [[ -x " + JSON.stringify(Config.scriptsDir + "/proteus-screenshot") + " ]]; then "
            + JSON.stringify(Config.scriptsDir + "/proteus-screenshot") + " " + m + "; "
            + "fi"
      ]
    })
  }

  function runPosture(target) {
    const proot = String(Quickshell.env("PROTEUS_ROOT") || "/mnt/proteus")
    const t = String(target || "desktop")
    // Prefer live tree (dogfood) over stale /usr/local. Do not use
    // `A && B & || C` — bash rejects that as a syntax error (tile no-op).
    Quickshell.execDetached({
      command: [
        "bash", "-lc",
        "P=" + proot + "/vm/guest/proteus-posture; "
            + "if [[ -x \"$P\" ]]; then setsid \"$P\" " + t + " >/dev/null 2>&1 & "
            + "elif command -v proteus-posture >/dev/null 2>&1; then "
            + "setsid proteus-posture " + t + " >/dev/null 2>&1 & "
            + "fi"
      ]
    })
  }

  function padMove(delta) {
    const n = padSlots.length
    if (!n)
      return
    padIndex = (padIndex + delta + n) % n
  }

  function padActivate() {
    const slot = padSlots[Math.max(0, Math.min(padIndex, padSlots.length - 1))]
    if (slot === "volume")
      return
    if (slot === "focus") {
      FocusMode.cycle()
      return
    }
    if (slot === "console" || slot === "desktop") {
      ShellState.closeControlCenter()
      root.runPosture(slot)
      return
    }
    if (slot === "glance") {
      ShellState.closeControlCenter()
      if (MissionCenter.available)
        MissionCenter.open()
      else
        MissionCenter.openSoftware()
      return
    }
    if (slot === "shot") {
      root.runScreenshot("screen")
      return
    }
    ShellState.closeControlCenter()
    if (slot === "lock")
      ShellState.lockSession()
    else
      ShellState.openSettingsSmart()
  }

  function handlePad(button) {
    const b = String(button || "")
    if (b === "b" || b === "select") {
      ShellState.closeControlCenter()
      return
    }
    if (b === "a" || b === "start") {
      padActivate()
      return
    }
    if (b === "up") {
      padMove(-1)
      return
    }
    if (b === "down") {
      padMove(1)
      return
    }
    if (b === "left") {
      if (padSlots[padIndex] === "volume")
        Audio.stepVolume(-5)
      else
        padMove(-1)
      return
    }
    if (b === "right") {
      if (padSlots[padIndex] === "volume")
        Audio.stepVolume(5)
      else
        padMove(1)
    }
  }

  Behavior on openProgress {
    NumberAnimation {
      duration: 200
      easing.type: Easing.OutCubic
    }
  }

  onOpenStateChanged: {
    openProgress = openState ? 1 : 0
    SystemLoad.watching = openState
    if (openState) {
      padIndex = 0
      forceActiveFocus()
    }
  }

  readonly property real panelW: Math.min(360, parent.width - 24)
  readonly property bool consoleChrome: ShellState.consoleSurfaceActive
  readonly property bool hostChrome: ShellState.hostSurfaceActive
  // Console bar is Theme.barHeight + 8; host bar is 40; desktop menu bar is Theme.barHeight.
  readonly property int panelTopMargin: root.consoleChrome
      ? (Theme.barHeight + 18)
      : (root.hostChrome ? 50 : (Theme.barHeight + 10))

  Rectangle {
    anchors.fill: parent
    color: Theme.scrimFill
    opacity: root.openProgress
    MouseArea {
      anchors.fill: parent
      onClicked: ShellState.closeControlCenter()
    }
  }

  Rectangle {
    id: panel
    // Desktop: drop from status cluster (top-right). Console: centered sheet for TV.
    y: root.panelTopMargin
    x: root.consoleChrome
        ? Math.round((parent.width - width) / 2)
        : Math.max(12, parent.width - width - 12)
    width: root.panelW
    height: Math.min(parent.height - root.panelTopMargin - 24, contentCol.implicitHeight + 28)
    radius: Theme.radiusXl
    // Chrome glass family (menu/dock frost) — one language across bar · dock · CC.
    color: Theme.menuPlateFill
    border.width: 1
    border.color: Theme.chromeBorder
    clip: true

    // Slide down + fade + gentle scale from the status cluster (top-right).
    opacity: root.openProgress
    transform: [
      Translate {
        y: -14 * (1 - root.openProgress)
      },
      Scale {
        origin.x: root.consoleChrome ? panel.width / 2 : panel.width
        origin.y: 0
        xScale: 0.98 + 0.02 * root.openProgress
        yScale: 0.98 + 0.02 * root.openProgress
      }
    ]

    Behavior on height {
      enabled: root.openState
      NumberAnimation {
        duration: 150
        easing.type: Easing.OutCubic
      }
    }

    // Absorb clicks so scrim doesn't close when interacting
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
      spacing: Theme.spaceMd
      width: parent.width - Theme.spaceMd * 2

      NotificationList {
        Layout.fillWidth: true
        Layout.maximumHeight: 300
      }

      Rectangle {
        Layout.fillWidth: true
        height: 1
        color: Theme.separator
      }

      // MPRIS Now Playing — collapses when no media player is registered.
      NowPlaying {
        Layout.fillWidth: true
      }

      // Privacy In-use strip — visible while mic / camera / screen capture active.
      Rectangle {
        visible: PrivacyIndicators.anyActive
        Layout.fillWidth: true
        implicitHeight: 40
        radius: Theme.radiusMd
        color: privacyMa.containsMouse ? Theme.chromeHover : Theme.elevatedFill
        border.width: 1
        border.color: Theme.chromeBorder

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: Theme.spaceSm
          anchors.rightMargin: Theme.spaceSm
          spacing: Theme.spaceSm

          Text {
            visible: PrivacyIndicators.mic
            text: "🎙"
            font.pixelSize: 14
            color: PrivacyIndicators.micColor
          }
          Text {
            visible: PrivacyIndicators.camera
            text: "📷"
            font.pixelSize: 14
            color: PrivacyIndicators.cameraColor
          }
          Text {
            visible: PrivacyIndicators.screen
            text: "▣"
            font.pixelSize: 14
            color: PrivacyIndicators.screenColor
          }

          Text {
            Layout.fillWidth: true
            text: {
              const apps = PrivacyIndicators.apps || []
              const names = []
              for (let i = 0; i < apps.length && names.length < 3; i++) {
                const n = String(apps[i].label || apps[i].name || apps[i].app || "").trim()
                if (n.length && names.indexOf(n) < 0)
                  names.push(n)
              }
              if (names.length)
                return names.join(", ") + " · In use"
              return "In use now"
            }
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: 12
            elide: Text.ElideRight
          }

          Text {
            text: "Privacy ›"
            color: Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: 11
            font.weight: Font.Medium
          }
        }

        MouseArea {
          id: privacyMa
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            ShellState.closeControlCenter()
            PrivacyIndicators.openPrivacySettings()
          }
        }
      }

      Text {
        text: "Quick Settings"
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: 14
        font.weight: Font.Medium
      }

      QuickSettingsGrid {
        id: qsGrid
        Layout.fillWidth: true
        // No battery (VM / desktop) → empty; the Power tile shows the profile alone.
        batteryText: {
          if (!Power.hasBattery)
            return ""
          const s = Power.stateLabel
          const charging = s === "Charging" || s === "Full"
          if (charging)
            return Power.percent + "% · Charging"
          if (UPower.onBattery)
            return Power.percent + "%"
          return Power.percent + "% · AC"
        }
        onNetworkClicked: {
          // Chrome path — Settings owns Network UX; nm-connection-editor stays
          // an escape inside Settings, not the Control Center default.
          ShellState.openSettingsSmart("network")
        }
        onDndToggled: Notifications.toggleDnd()
      }

      // System glance — SystemLoad polls only while the CC is open (`watching`).
      Rectangle {
        Layout.fillWidth: true
        implicitHeight: 30
        radius: Theme.radiusMd
        color: glanceMa.containsMouse ? Theme.chromeHover : "transparent"

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: Theme.spaceSm
          anchors.rightMargin: Theme.spaceSm
          spacing: Theme.spaceSm

          Text {
            Layout.fillWidth: true
            text: SystemLoad.ready ? SystemLoad.summaryLabel : "Reading system load…"
            color: Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: 11
            elide: Text.ElideRight
          }

          Text {
            text: MissionCenter.available ? "Mission Center ›" : "Install ›"
            color: Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: 11
            font.weight: Font.Medium
          }
        }

        MouseArea {
          id: glanceMa
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            ShellState.closeControlCenter()
            if (MissionCenter.available)
              MissionCenter.open()
            else
              MissionCenter.openSoftware()
          }
        }
      }

      // Customize escape — tile order/size live in Settings → Desktop → Control Center.
      Text {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        text: "Edit tiles ›"
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: 11
        font.weight: Font.Medium
        MouseArea {
          anchors.fill: parent
          anchors.margins: -6
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            ShellState.closeControlCenter()
            ShellState.openSettings("desktop-control-center")
          }
        }
      }

      // Footer actions — Lock · Screenshot (menu) · Settings.
      RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spaceSm

        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 34
          radius: Theme.radiusMd
          color: lockMa.containsMouse ? Theme.chromeHover : Theme.elevatedFill
          border.width: 1
          border.color: Theme.chromeBorder
          scale: lockMa.pressed ? 0.97 : 1
          Behavior on scale {
            NumberAnimation {
              duration: 100
              easing.type: Easing.OutCubic
            }
          }
          Text {
            anchors.centerIn: parent
            text: "Lock"
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: 12
            font.weight: Font.Medium
          }
          MouseArea {
            id: lockMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              ShellState.closeControlCenter()
              ShellState.lockSession()
            }
          }
        }

        Rectangle {
          id: shotBtn
          Layout.fillWidth: true
          Layout.preferredHeight: 34
          radius: Theme.radiusMd
          color: (shotMenu.visible || shotMa.containsMouse) ? Theme.chromeHover : Theme.elevatedFill
          border.width: 1
          border.color: shotMenu.visible ? Theme.accent : Theme.chromeBorder
          scale: shotMa.pressed ? 0.97 : 1
          Behavior on scale {
            NumberAnimation {
              duration: 100
              easing.type: Easing.OutCubic
            }
          }
          Text {
            anchors.centerIn: parent
            text: "Screenshot ▾"
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: 12
            font.weight: Font.Medium
          }
          MouseArea {
            id: shotMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              if (shotMenu.visible)
                shotMenu.close()
              else
                shotMenu.open()
            }
          }
          Popup {
            id: shotMenu
            y: shotBtn.height + 4
            x: 0
            width: Math.max(160, shotBtn.width)
            padding: 4
            closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
            modal: false
            background: Rectangle {
              radius: Theme.radiusMd
              color: Theme.bgElevated
              border.width: 1
              border.color: Theme.border
            }
            contentItem: Column {
              spacing: 1
              Repeater {
                model: [
                  { id: "region", title: "Region" },
                  { id: "screen", title: "Screen" }
                ]
                Rectangle {
                  required property var modelData
                  width: shotMenu.width - 8
                  height: 32
                  radius: Theme.radiusSm
                  color: shotRowMa.containsMouse ? Theme.bgHover : "transparent"
                  Text {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spaceSm
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.title
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                  }
                  MouseArea {
                    id: shotRowMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      shotMenu.close()
                      root.runScreenshot(modelData.id)
                    }
                  }
                }
              }
            }
          }
        }

        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 34
          radius: Theme.radiusMd
          color: setMa.containsMouse ? Theme.chromeHover : Theme.elevatedFill
          border.width: 1
          border.color: Theme.chromeBorder
          scale: setMa.pressed ? 0.97 : 1
          Behavior on scale {
            NumberAnimation {
              duration: 100
              easing.type: Easing.OutCubic
            }
          }
          Text {
            anchors.centerIn: parent
            text: "Settings ›"
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: 12
            font.weight: Font.Medium
          }
          MouseArea {
            id: setMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              ShellState.closeControlCenter()
              ShellState.openSettingsSmart()
            }
          }
        }
      }
    }
  }

  Keys.onEscapePressed: ShellState.closeControlCenter()
  Keys.onPressed: event => {
    if (event.key === Qt.Key_Up) {
      root.padMove(-1)
      event.accepted = true
    } else if (event.key === Qt.Key_Down) {
      root.padMove(1)
      event.accepted = true
    } else if (event.key === Qt.Key_Left) {
      root.handlePad("left")
      event.accepted = true
    } else if (event.key === Qt.Key_Right) {
      root.handlePad("right")
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
      root.padActivate()
      event.accepted = true
    }
  }
  focus: true

  // Pad focus hint
  Text {
    anchors.left: parent.left
    anchors.bottom: parent.bottom
    anchors.margins: Theme.spaceSm
    z: 50
    visible: root.openState
    text: {
      const slot = root.padSlots[root.padIndex] || ""
      const labels = {
        volume: "Volume (←/→)",
        focus: "Focus",
        console: "Enter Console",
        desktop: "Return to Desktop",
        glance: "System glance",
        lock: "Lock",
        shot: "Screenshot (screen)",
        settings: "Settings"
      }
      return "◎ " + (labels[slot] || slot)
    }
    color: Theme.accent
    font.family: Theme.fontFamily
    font.pixelSize: 11
    font.weight: Font.Medium
  }

  Connections {
    target: ShellState
    function onPadAction(button) {
      if (!ShellState.controlCenterOpen || ShellState.sessionLocked)
        return
      root.handlePad(button)
    }
  }

  Component.onCompleted: {
    if (openState)
      openProgress = 1
    forceActiveFocus()
  }
}
