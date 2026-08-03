import Quickshell
import Quickshell.Io
import QtQuick
// Profile-local symlinks mirroring the shell/ tree shape (shared → ../shared,
// surfaces/console → ../../surfaces/console, …) so the console QML's relative
// imports ("../../shared", "../desktop") resolve both through the symlinked
// and the canonical path (same pattern as apps/proteus-settings' shared link).
import "shared"
import "surfaces/console"
import "surfaces/desktop"

// Proteus Home — the console's primary client when Gamescope owns the session
// (proteus-console-gs-session). A fullscreen xdg toplevel (FloatingWindow)
// reusing the Console list IA (ConsoleHome) — NOT Hyprland layer-shell chrome.
// Precedent: apps/proteus-settings/shell.qml (QS as a regular toplevel).
//
// Contracts:
//   - Home keeps the session alive: window close / Qt.quit ends the session
//     (gs-session's primary child) and lands at the greeter.
//   - Lock inside the Gamescope session = session exit — login is the lock
//     (WlSessionLock is Hyprland-only; see COMPOSITOR.md Phase 3).
//   - proteus-guide targets this profile in session mode; pad routing rides
//     the same ShellState grammar as the Hyprland console chrome.
ShellRoot {
  id: root

  // Fade the list IA while a title launch is in flight (mirror ConsoleShell).
  property real navFade: 1
  readonly property bool navWanted: ShellState.consoleNavVisible
      || ShellState.controlCenterOpen || ShellState.consoleSwitcherOpen

  Behavior on navFade {
    NumberAnimation {
      duration: 220
      easing.type: Easing.OutCubic
    }
  }

  function syncNavFade() {
    root.navFade = root.navWanted ? 1 : 0
  }

  Connections {
    target: ShellState
    function onConsoleNavVisibleChanged() { root.syncNavFade() }
    function onControlCenterOpenChanged() { root.syncNavFade() }
    function onConsoleSwitcherOpenChanged() { root.syncNavFade() }
  }

  // Lock = session exit (v1 honesty): any lock request inside the Gamescope
  // session terminates the session; greeter login is the lock.
  Connections {
    target: ShellState
    function onSessionLockedChanged() {
      if (!ShellState.sessionLocked)
        return
      Quickshell.execDetached({
        command: [
          "bash", "-lc",
          "sleep 0.3; if [ -n \"${XDG_SESSION_ID:-}\" ] && command -v loginctl >/dev/null 2>&1; then "
              + "loginctl terminate-session \"${XDG_SESSION_ID}\"; else pkill -x gamescope; fi"
        ]
      })
    }
  }

  Component.onCompleted: {
    ShellState.consoleSurfaceActive = true
    ShellState.hostSurfaceActive = false
    // No cold-boot lock inside the Gamescope session — the login we just
    // came from is the lock.
    ShellState.sessionStartLockPending = false
    ShellState.showConsoleNav()
    root.syncNavFade()
  }

  FloatingWindow {
    id: win
    title: "Proteus Home"
    visible: true
    implicitWidth: 1280
    implicitHeight: 720
    color: Theme.bg

    // Primary client contract: closing Home ends the session.
    onClosed: Qt.quit()

    // Console background canvas (calm; same treatment as ConsoleShell bg layer)
    Rectangle {
      anchors.fill: parent
      gradient: Gradient {
        GradientStop { position: 0.35; color: "transparent" }
        GradientStop {
          position: 1.0
          color: Qt.rgba(Theme.bgElevated.r, Theme.bgElevated.g, Theme.bgElevated.b, 0.4)
        }
      }
    }

    ConsoleHome {
      anchors.fill: parent
      navOpacity: root.navFade
    }

    // Toasts + volume/brightness HUD live inside the Home window (no
    // layer-shell overlays under Gamescope).
    NotificationToast {
      anchors.fill: parent
      visible: Notifications.showToast
    }

    StatusHud {
      anchors.fill: parent
      visible: Hud.hudVisible && !ShellState.controlCenterOpen
    }
  }

  // Same chrome IPC surface proteus-guide + focus router use against the
  // Hyprland console chrome — session mode targets this profile instead.
  IpcHandler {
    target: "chrome"

    function controlCenter(): void {
      ShellState.toggleControlCenter()
    }

    function consoleNav(): void {
      ShellState.consoleGuidePrimary()
    }

    function consoleSwitcher(): void {
      ShellState.toggleConsoleSwitcher()
    }

    function consoleCC(): void {
      ShellState.toggleControlCenter()
    }

    function consoleHide(): void {
      ShellState.hideConsoleNav()
    }

    function consoleShow(): void {
      ShellState.showConsoleNav()
    }

    function pad(button: string): void {
      ShellState.handlePad(button)
    }

    function volume(value: int): void {
      Hud.show("volume", value, "")
    }

    function brightness(value: int): void {
      Hud.show("brightness", value, "")
    }

    function volumeUp(): void {
      Audio.stepVolume(5)
    }

    function volumeDown(): void {
      Audio.stepVolume(-5)
    }

    function volumeMute(): void {
      Audio.toggleMuteHud()
    }

    function brightnessUp(): void {
      Brightness.stepBrightness(5)
    }

    function brightnessDown(): void {
      Brightness.stepBrightness(-5)
    }

    function state(): string {
      return JSON.stringify({
        surface: "console",
        session: "gamescope",
        nav: ShellState.consoleNavVisible,
        switcher: ShellState.consoleSwitcherOpen,
        controlCenter: ShellState.controlCenterOpen,
        locked: false,
        launcher: false,
        padWanted: ShellState.padWanted,
        exitConfirm: ShellState.consoleExitConfirmOpen,
        launchPending: ShellState.consoleLaunchPending
      })
    }
  }

  IpcHandler {
    target: "lock"
    // Login is the lock — both entry points end the session.
    function lock(): void {
      ShellState.lockSession()
    }
  }
}
