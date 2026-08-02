import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../shared"
import "desktop"

// Host posture — lean ops chrome (Fact + hard flip). Same Settings spine;
// no dock / desktop widgets. Return via CC Desktop tile or Beacon action.
Scope {
  id: root

  readonly property bool skipSessionLock: {
    const v = Quickshell.env("PROTEUS_SKIP_SESSION_LOCK")
    return v === "1" || v === "true"
  }

  function runPosture(target) {
    const proot = String(Quickshell.env("PROTEUS_ROOT") || "/mnt/proteus")
    const t = String(target || "desktop")
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

  Component.onCompleted: {
    ShellState.consoleSurfaceActive = false
    ShellState.hostSurfaceActive = true
  }

  GlobalShortcut {
    appid: "proteus"
    name: "launcher"
    description: "Toggle Beacon (system search)"
    onPressed: ShellState.toggleLauncher()
  }

  GlobalShortcut {
    appid: "proteus"
    name: "settings"
    description: "Open Proteus Settings"
    onPressed: ShellState.openSettings()
  }

  GlobalShortcut {
    appid: "proteus"
    name: "lock"
    description: "Lock Proteus session"
    onPressed: ShellState.lockSession()
  }

  GlobalShortcut {
    appid: "proteus"
    name: "control-center"
    description: "Toggle Control Center"
    onPressed: ShellState.toggleControlCenter()
  }

  IpcHandler {
    target: "lock"
    function lock(): void { ShellState.lockSession() }
    function unlock(): void { ShellState.unlockSession() }
  }

  IpcHandler {
    target: "chrome"
    function controlCenter(): void { ShellState.toggleControlCenter() }
    function beacon(query: string): void {
      ShellState.openLauncher()
    }
    function beaconState(): string {
      return ShellState.launcherOpen ? '{"open":true}' : '{"open":false}'
    }
  }

  WlSessionLock {
    locked: ShellState.sessionLocked

    WlSessionLockSurface {
      LockSurface {
        lock: parent
        screen: parent.screen
      }
    }
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      required property var modelData
      screen: modelData
      exclusionMode: ExclusionMode.Ignore
      exclusiveZone: 0
      color: "transparent"
      anchors {
        top: true
        left: true
        right: true
        bottom: true
      }

      Component.onCompleted: {
        if (WlrLayershell != null) {
          WlrLayershell.namespace = "proteus-host-bg"
          WlrLayershell.layer = WlrLayer.Background
        }
      }

      Rectangle {
        anchors.fill: parent
        color: Theme.bg
      }
    }
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      required property var modelData
      screen: modelData
      visible: !ShellState.sessionLocked && !ShellState.sessionStartLockPending
      exclusionMode: ExclusionMode.Ignore
      exclusiveZone: 40
      implicitHeight: 40
      color: "transparent"
      anchors {
        top: true
        left: true
        right: true
      }

      Component.onCompleted: {
        if (WlrLayershell != null) {
          WlrLayershell.namespace = "proteus-host-bar"
          WlrLayershell.layer = WlrLayer.Top
        }
      }

      Rectangle {
        anchors.fill: parent
        color: Theme.menuBarFill
        border.width: 0

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: Theme.spaceMd
          anchors.rightMargin: Theme.spaceMd
          spacing: Theme.spaceMd

          Text {
            text: "Host"
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            font.weight: Font.DemiBold
          }

          Text {
            text: "Lean ops · same Settings spine"
            color: Theme.textMute
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
            Layout.fillWidth: true
            elide: Text.ElideRight
          }

          Text {
            text: "Desktop"
            color: Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: 13
            MouseArea {
              anchors.fill: parent
              anchors.margins: -8
              cursorShape: Qt.PointingHandCursor
              onClicked: root.runPosture("desktop")
            }
          }

          Text {
            text: "Settings"
            color: Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: 13
            MouseArea {
              anchors.fill: parent
              anchors.margins: -8
              cursorShape: Qt.PointingHandCursor
              onClicked: ShellState.openSettings()
            }
          }

          Text {
            text: "CC"
            color: Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: 13
            MouseArea {
              anchors.fill: parent
              anchors.margins: -8
              cursorShape: Qt.PointingHandCursor
              onClicked: ShellState.toggleControlCenter()
            }
          }

          Text {
            text: "Lock"
            color: Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: 13
            MouseArea {
              anchors.fill: parent
              anchors.margins: -8
              cursorShape: Qt.PointingHandCursor
              onClicked: ShellState.lockSession()
            }
          }
        }
      }
    }
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      required property var modelData
      screen: modelData
      visible: !ShellState.sessionLocked && !ShellState.sessionStartLockPending
          && (ShellState.controlCenterOpen || ShellState.launcherOpen)
      exclusionMode: ExclusionMode.Ignore
      exclusiveZone: 0
      color: "transparent"
      anchors {
        top: true
        left: true
        right: true
        bottom: true
      }

      Component.onCompleted: {
        if (WlrLayershell != null) {
          WlrLayershell.namespace = "proteus-host-chrome"
          WlrLayershell.layer = WlrLayer.Overlay
        }
      }

      ControlCenter {
        anchors.fill: parent
        visible: ShellState.controlCenterOpen
      }

      Beacon {
        anchors.fill: parent
        visible: ShellState.launcherOpen
      }
    }
  }

  Timer {
    interval: 200
    running: true
    repeat: false
    onTriggered: {
      if (!root.skipSessionLock && Config.lockOnSessionStart)
        ShellState.lockSession()
      else
        ShellState.sessionStartLockPending = false
    }
  }
}
