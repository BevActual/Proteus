import Quickshell
import Quickshell.Services.UPower
import QtQuick
import QtQuick.Layouts
import "../../shared"

// Combined notifications + quick settings (macOS-style Control Center).
// Owns its own open/close motion: the layer window stays mapped while
// `stillVisible` so the exit animation can play (DesktopShell binds to it).
Item {
  id: root
  anchors.fill: parent

  readonly property bool openState: ShellState.controlCenterOpen
  property real openProgress: openState ? 1 : 0
  readonly property bool stillVisible: openState || openProgress > 0.001
  // Pad focus: volume | dnd | console | glance | lock | shot | settings
  property int padIndex: 0
  readonly property var padSlots: ["volume", "dnd", "console", "glance", "lock", "shot", "settings"]

  visible: stillVisible

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
    if (slot === "dnd") {
      Notifications.toggleDnd()
      return
    }
    if (slot === "console") {
      ShellState.closeControlCenter()
      const proot = String(Quickshell.env("PROTEUS_ROOT") || "/mnt/proteus")
      Quickshell.execDetached({
        command: [
          "bash", "-lc",
          "command -v proteus-posture >/dev/null && setsid proteus-posture console >/dev/null 2>&1 & "
              + "|| setsid " + proot + "/vm/guest/proteus-posture console >/dev/null 2>&1 &"
        ]
      })
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
    ShellState.closeControlCenter()
    if (slot === "lock")
      ShellState.lockSession()
    else if (slot === "shot") {
      Quickshell.execDetached({
        command: [
          "bash",
          "-lc",
          "sleep 0.4; d=\"$HOME/Pictures/Screenshots\"; mkdir -p \"$d\"; "
              + "f=\"$d/Screenshot-$(date +%Y-%m-%d-%H%M%S).png\"; "
              + "grim \"$f\" && { command -v notify-send >/dev/null 2>&1 "
              + "&& notify-send 'Screenshot saved' \"$f\" || true; }"
        ]
      })
    } else {
      ShellState.openSettings()
    }
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
    SystemLoad.watching = openState
    if (openState) {
      padIndex = 0
      forceActiveFocus()
    }
  }

  readonly property real panelW: Math.min(360, parent.width - 24)

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
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.topMargin: Theme.barHeight + 10
    anchors.rightMargin: 12
    width: root.panelW
    height: Math.min(parent.height - Theme.barHeight - 24, contentCol.implicitHeight + 28)
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
        origin.x: panel.width
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
          ShellState.openSettings("network")
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

      // Footer actions — Lock · Screenshot · Settings.
      RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spaceSm

        Repeater {
          model: [
            { act: "lock", label: "Lock" },
            { act: "shot", label: "Screenshot" },
            { act: "settings", label: "Settings ›" }
          ]

          Rectangle {
            required property var modelData
            Layout.fillWidth: true
            Layout.preferredHeight: 34
            radius: Theme.radiusMd
            color: footMa.containsMouse ? Theme.chromeHover : Theme.elevatedFill
            border.width: 1
            border.color: Theme.chromeBorder

            scale: footMa.pressed ? 0.97 : 1
            Behavior on scale {
              NumberAnimation {
                duration: 100
                easing.type: Easing.OutCubic
              }
            }

            Text {
              anchors.centerIn: parent
              text: parent.modelData.label
              color: Theme.text
              font.family: Theme.fontFamily
              font.pixelSize: 12
              font.weight: Font.Medium
            }

            MouseArea {
              id: footMa
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                ShellState.closeControlCenter()
                if (parent.modelData.act === "lock") {
                  ShellState.lockSession()
                } else if (parent.modelData.act === "shot") {
                  // Delay past the close animation so the CC isn't in the shot;
                  // the shell's own notification server confirms with a toast.
                  Quickshell.execDetached({
                    command: [
                      "bash",
                      "-lc",
                      "sleep 0.4; d=\"$HOME/Pictures/Screenshots\"; mkdir -p \"$d\"; "
                          + "f=\"$d/Screenshot-$(date +%Y-%m-%d-%H%M%S).png\"; "
                          + "grim \"$f\" && { command -v notify-send >/dev/null 2>&1 "
                          + "&& notify-send 'Screenshot saved' \"$f\" || true; }"
                    ]
                  })
                } else {
                  ShellState.openSettings()
                }
              }
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
        dnd: "Do Not Disturb",
        console: "Enter Console",
        glance: "System glance",
        lock: "Lock",
        shot: "Screenshot",
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

  Component.onCompleted: forceActiveFocus()
}
