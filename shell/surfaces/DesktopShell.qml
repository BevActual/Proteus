import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../shared"
import "desktop"

Scope {
  id: root

  // Suppresses ONLY the automatic cold-boot lock, so the smoke suite can
  // cold-start the shell without stranding the guest at a password prompt it
  // cannot answer. Super+L, the lock surface and its cooldown are unaffected.
  // Deliberately named for what it does rather than hidden behind a generic
  // "smoke mode" flag — it is a lock behaviour change and should read as one.
  readonly property bool skipSessionLock: {
    const v = Quickshell.env("PROTEUS_SKIP_SESSION_LOCK")
    return v === "1" || v === "true"
  }

  GlobalShortcut {
    appid: "proteus"
    name: "launcher"
    description: "Toggle Proteus app launcher"
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
    name: "customize-desktop"
    description: "Customize desktop widgets"
    onPressed: ShellState.enterDesktopCustomize()
  }

  IpcHandler {
    target: "lock"
    function lock(): void {
      ShellState.lockSession()
    }
  }

  WlSessionLock {
    id: sessionLock
    locked: ShellState.sessionLocked

    WlSessionLockSurface {
      // Opaque base — transparent lock surfaces are unreliable on Hyprland
      color: "#000000"
      LockSurface {
        anchors.fill: parent
        onUnlocked: ShellState.unlockSession()
      }
    }
  }

  Connections {
    target: ShellState
    function onSessionLockedChanged() {
      // Keep lock object in sync explicitly (binding can race on first lock)
      sessionLock.locked = ShellState.sessionLocked
    }
  }

  // Cold boot / every session: show Proteus lock until password
  Timer {
    id: sessionStartLockTimer
    interval: 250
    running: true
    repeat: false
    onTriggered: {
      if (!Config.lockOnSessionStart)
        return
      if (!ShellState.sessionStartLockPending)
        return
      ShellState.sessionStartLockPending = false
      if (root.skipSessionLock) {
        console.warn("session lock skipped — PROTEUS_SKIP_SESSION_LOCK is set")
        return
      }
      ShellState.lockSession()
    }
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: deskWidgetsWin
      required property var modelData
      screen: modelData

      // Below windows (Bottom); Overlay while customizing so applets stay on top
      visible: !ShellState.sessionLocked
      exclusionMode: ExclusionMode.Ignore
      exclusiveZone: 0
      color: "transparent"

      // Usable desktop only — keep applets out from under menu bar + dock
      // (including Customize; snap grid covers this surface, not chrome).
      readonly property int topClearance: Theme.barHeight
      readonly property int bottomClearance: Config.dockEnabled ? Theme.dockReserved : Theme.spaceMd

      anchors {
        top: true
        left: true
        right: true
        bottom: true
      }
      margins.top: topClearance
      margins.bottom: bottomClearance

      Component.onCompleted: {
        if (deskWidgetsWin.WlrLayershell != null) {
          deskWidgetsWin.WlrLayershell.namespace = "proteus-desktop-widgets"
          deskWidgetsWin.WlrLayershell.layer = ShellState.desktopCustomizeMode ? WlrLayer.Overlay : WlrLayer.Bottom
        }
      }

      Connections {
        target: ShellState
        function onDesktopCustomizeModeChanged() {
          if (deskWidgetsWin.WlrLayershell != null)
            deskWidgetsWin.WlrLayershell.layer = ShellState.desktopCustomizeMode ? WlrLayer.Overlay : WlrLayer.Bottom
        }
      }

      DesktopWidgetSurface {
        anchors.fill: parent
      }
    }
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: bar
      required property var modelData
      screen: modelData
      readonly property bool onThisScreen: Config.chromeOnScreen(modelData, Config.barMonitor)
      visible: onThisScreen && !ShellState.desktopCustomizeMode

      readonly property int peek: 3
      readonly property int barH: Theme.barHeight
      property bool barHovered: false
      property bool barRevealed: !Config.barAutoHide || barHovered || ShellState.launcherOpen || ShellState.controlCenterOpen

      anchors {
        top: true
        left: true
        right: true
      }

      implicitHeight: barH
      color: "transparent"
      // Slide off top when auto-hidden; leave a thin peek for edge hover
      margins.top: barRevealed ? 0 : -(barH - peek)
      exclusiveZone: onThisScreen && (!Config.barAutoHide || barRevealed) ? barH : 0
      exclusionMode: Config.barAutoHide && !barRevealed ? ExclusionMode.Ignore : ExclusionMode.Auto
      WlrLayershell.namespace: "proteus-bar"

      Behavior on margins.top {
        NumberAnimation {
          duration: 220
          easing.type: Easing.OutCubic
        }
      }

      Timer {
        id: barHideTimer
        interval: 700
        onTriggered: bar.barHovered = false
      }

      // HoverHandler sees children too (unlike a sibling MouseArea under TopBar)
      HoverHandler {
        onHoveredChanged: {
          if (hovered) {
            barHideTimer.stop()
            bar.barHovered = true
          } else if (Config.barAutoHide) {
            barHideTimer.restart()
          }
        }
      }

      TopBar {
        anchors.fill: parent
      }
    }
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: dockWin
      required property var modelData
      screen: modelData
      readonly property bool onThisScreen: Config.dockEnabled && Config.chromeOnScreen(modelData, Config.dockMonitor)
      visible: onThisScreen && !ShellState.desktopCustomizeMode

      readonly property int peek: 4
      readonly property int dockGap: Theme.dockGap
      // Full panel height (shelf + magnify headroom) — must match exclusive zone
      // or windows draw into the transparent area and text ghosts through the dock.
      readonly property int dockH: Math.max(dock.implicitHeight, Theme.dockPanelHeight)
      property bool dockHovered: false
      property bool dockRevealed: !Config.dockAutoHide || dockHovered || ShellState.launcherOpen

      anchors {
        left: true
        right: true
        bottom: true
      }

      margins.bottom: dockRevealed ? dockGap : -(dockH - peek)
      implicitHeight: onThisScreen ? dockH : 0
      exclusiveZone: onThisScreen && (!Config.dockAutoHide || dockRevealed) ? (dockH + dockGap) : 0
      exclusionMode: Config.dockAutoHide && !dockRevealed ? ExclusionMode.Ignore : ExclusionMode.Auto
      color: "transparent"
      WlrLayershell.namespace: "proteus-dock"

      Behavior on margins.bottom {
        NumberAnimation {
          duration: 220
          easing.type: Easing.OutCubic
        }
      }

      Timer {
        id: dockHideTimer
        interval: 700
        onTriggered: dockWin.dockHovered = false
      }

      HoverHandler {
        onHoveredChanged: {
          if (hovered) {
            dockHideTimer.stop()
            dockWin.dockHovered = true
          } else if (Config.dockAutoHide) {
            dockHideTimer.restart()
          }
        }
      }

      Dock {
        id: dock
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        visible: Config.dockEnabled
      }
    }
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: launcherWin
      required property var modelData
      screen: modelData

      readonly property bool isFocused: {
        const mon = Hyprland.monitorFor(modelData)
        return mon ? mon.focused : (modelData === Quickshell.screens[0])
      }

      readonly property bool active: ShellState.launcherOpen && isFocused

      visible: active
      exclusionMode: ExclusionMode.Ignore
      color: "transparent"

      // focusable:true is only OnDemand — Exclusive is required so keystrokes
      // leave the focused client (editor/terminal) while Spotlight is open.
      WlrLayershell.namespace: "proteus-launcher"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

      anchors {
        top: true
        left: true
        right: true
        bottom: true
      }

      Rectangle {
        anchors.fill: parent
        // Lighter than Control Center scrim — Spotlight floats on the desktop
        color: Theme.light ? Qt.rgba(0, 0, 0, 0.14) : Qt.rgba(0, 0, 0, 0.32)
        MouseArea {
          anchors.fill: parent
          onClicked: ShellState.closeLauncher()
        }
      }

      Launcher {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Math.max(56, parent.height * 0.11)
        width: Math.min(680, parent.width - 48)
        height: Math.min(480, parent.height - 100)
      }
    }
  }

  // Control Center (notifications + quick settings) + notification toasts
  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: ccWin
      required property var modelData
      screen: modelData

      readonly property bool isFocused: {
        const mon = Hyprland.monitorFor(modelData)
        return mon ? mon.focused : (modelData === Quickshell.screens[0])
      }

      readonly property bool showToast: Notifications.showToast

      visible: !ShellState.sessionLocked && isFocused
          && (ShellState.controlCenterOpen || showToast)
      exclusionMode: ExclusionMode.Ignore
      color: "transparent"

      anchors {
        top: true
        left: true
        right: true
        bottom: true
      }

      Component.onCompleted: {
        if (ccWin.WlrLayershell != null) {
          ccWin.WlrLayershell.namespace = "proteus-control-center"
          ccWin.WlrLayershell.layer = WlrLayer.Overlay
        }
      }

      ControlCenter {
        anchors.fill: parent
        visible: ShellState.controlCenterOpen
      }

      NotificationToast {
        id: toastLayer
        anchors.fill: parent
        visible: ccWin.showToast
      }

      // Toast-only: click-through except the card. Full input while Control Center is open.
      mask: ShellState.controlCenterOpen ? null : (showToast ? toastMask : null)

      Region {
        id: toastMask
        item: toastLayer.cardItem
      }
    }
  }
}
