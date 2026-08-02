import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import "../shared"
import "console"
import "desktop"

// Console posture — sparse navigation layer over fullscreen apps.
Scope {
  id: root

  // Same as DesktopShell: smoke/dogfood can skip cold-boot lock only.
  readonly property bool skipSessionLock: {
    const v = Quickshell.env("PROTEUS_SKIP_SESSION_LOCK")
    return v === "1" || v === "true"
  }

  // Hide nav when a real app window is focused (Guide / IPC brings it back).
  function syncNavToFocus() {
    if (ShellState.sessionLocked)
      return
    const t = Hyprland.activeToplevel
    if (!t) {
      // During launch, stay hidden so the new client can take focus/fullscreen.
      if (ShellState.consoleLaunchPending)
        return
      if (!ShellState.consoleNavVisible)
        ShellState.showConsoleNav()
      return
    }
    const ipc = t.lastIpcObject || {}
    const cls = String(t.class || ipc.class || "").toLowerCase()
    const title = String(t.title || ipc.title || "")
    if (cls === "quickshell" || title.indexOf("Proteus Settings") === 0)
      return
    // App focused — hide navigation layer; launch settled
    ShellState.consoleLaunchPending = false
    if (ShellState.consoleNavVisible && !ShellState.controlCenterOpen && !ShellState.consoleSwitcherOpen)
      ShellState.hideConsoleNav()
  }

  GlobalShortcut {
    appid: "proteus"
    name: "lock"
    description: "Lock Proteus session"
    onPressed: ShellState.lockSession()
  }

  GlobalShortcut {
    appid: "proteus"
    name: "console-nav"
    description: "Toggle console navigation / switcher"
    onPressed: {
      if (ShellState.sessionLocked)
        return
      ShellState.consoleGuidePrimary()
    }
  }

  GlobalShortcut {
    appid: "proteus"
    name: "console-cc"
    description: "Toggle Control Center (console)"
    onPressed: ShellState.toggleControlCenter()
  }

  GlobalShortcut {
    appid: "proteus"
    name: "volume-up"
    description: "Raise volume"
    onPressed: Audio.stepVolume(5)
  }

  GlobalShortcut {
    appid: "proteus"
    name: "volume-down"
    description: "Lower volume"
    onPressed: Audio.stepVolume(-5)
  }

  GlobalShortcut {
    appid: "proteus"
    name: "volume-mute"
    description: "Toggle mute"
    onPressed: Audio.toggleMuteHud()
  }

  GlobalShortcut {
    appid: "proteus"
    name: "brightness-up"
    description: "Raise brightness"
    onPressed: Brightness.stepBrightness(5)
  }

  GlobalShortcut {
    appid: "proteus"
    name: "brightness-down"
    description: "Lower brightness"
    onPressed: Brightness.stepBrightness(-5)
  }

  IpcHandler {
    target: "lock"
    function lock(): void {
      ShellState.lockSession()
    }
    function unlock(): void {
      ShellState.unlockSession()
    }
  }

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
        nav: ShellState.consoleNavVisible,
        switcher: ShellState.consoleSwitcherOpen,
        controlCenter: ShellState.controlCenterOpen,
        locked: ShellState.sessionLocked,
        launcher: false,
        padWanted: ShellState.padWanted,
        exitConfirm: ShellState.consoleExitConfirmOpen
      })
    }
  }

  WlSessionLock {
    id: sessionLock
    locked: ShellState.sessionLocked

    WlSessionLockSurface {
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
      sessionLock.locked = ShellState.sessionLocked
      if (!ShellState.sessionLocked)
        ShellState.showConsoleNav()
    }
  }

  // Cold boot: same Fact as desktop (Config.lockOnSessionStart)
  Timer {
    id: sessionStartLockTimer
    interval: 250
    running: true
    repeat: false
    onTriggered: {
      if (!ShellState.sessionStartLockPending)
        return
      if (!Config.lockOnSessionStart) {
        ShellState.sessionStartLockPending = false
        ShellState.consoleNavVisible = true
        return
      }
      if (root.skipSessionLock) {
        console.warn("session lock skipped — PROTEUS_SKIP_SESSION_LOCK is set")
        ShellState.sessionStartLockPending = false
        ShellState.consoleNavVisible = true
        root.syncNavFade()
        return
      }
      // Keep pending TRUE while locked (same as DesktopShell) so nav stays
      // unmapped under the lock. Engage WlSessionLock explicitly — binding
      // alone can race on first lock after a chrome restart.
      ShellState.lockSession()
      sessionLock.locked = true
    }
  }

  // If Wayland session lock never maps, unlock + show nav so console is not
  // permanently blank (bg layer only, overlay hidden).
  Timer {
    id: lockWatchdog
    interval: 2500
    running: true
    repeat: false
    onTriggered: {
      if (!ShellState.sessionLocked || !ShellState.sessionStartLockPending)
        return
      if (sessionLock.locked) {
        // Still locked with compositor — leave LockSurface as SoT.
        return
      }
      console.warn("console session lock failed to engage — showing nav")
      ShellState.unlockSession()
      ShellState.showConsoleNav()
      root.syncNavFade()
    }
  }

  Connections {
    target: Hyprland
    function onActiveToplevelChanged() {
      root.syncNavToFocus()
    }
  }

  // Nav fade — keep layer mapped briefly so hide/show can animate (CC stillVisible).
  property real navFade: 0
  readonly property bool navLayerWanted: !ShellState.sessionLocked && !ShellState.sessionStartLockPending
      && (ShellState.consoleNavVisible || ShellState.controlCenterOpen || ShellState.consoleSwitcherOpen)

  Behavior on navFade {
    NumberAnimation {
      duration: 220
      easing.type: Easing.OutCubic
    }
  }

  function syncNavFade() {
    root.navFade = root.navLayerWanted ? 1 : 0
  }

  Connections {
    target: ShellState
    function onConsoleNavVisibleChanged() { root.syncNavFade() }
    function onControlCenterOpenChanged() { root.syncNavFade() }
    function onConsoleSwitcherOpenChanged() { root.syncNavFade() }
    function onSessionLockedChanged() { root.syncNavFade() }
    function onSessionStartLockPendingChanged() { root.syncNavFade() }
  }

  Component.onCompleted: {
    ShellState.consoleSurfaceActive = true
    ShellState.hostSurfaceActive = false
    root.syncNavFade()
  }

  // Background canvas layer (calm; not desktop wallpaper config)
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
          WlrLayershell.namespace = "proteus-console-bg"
          WlrLayershell.layer = WlrLayer.Background
        }
      }

      Rectangle {
        anchors.fill: parent
        color: Theme.bg
      }

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
    }
  }

  // Navigation overlay
  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: navWin
      required property var modelData
      screen: modelData

      visible: !ShellState.sessionLocked && !ShellState.sessionStartLockPending
          && (root.navLayerWanted || root.navFade > 0.01)
      exclusionMode: ExclusionMode.Ignore
      exclusiveZone: 0
      color: "transparent"

      anchors {
        top: true
        left: true
        right: true
        bottom: true
      }

      function applyLayer() {
        if (navWin.WlrLayershell == null)
          return
        navWin.WlrLayershell.namespace = "proteus-console-nav"
        navWin.WlrLayershell.layer = WlrLayer.Overlay
        // Exclusive only while nav/CC/switcher claim input. When nav hides for
        // an app launch, release immediately so Hyprland can focus the client
        // (otherwise apps stay tiled with no activewindow).
        const grab = !ShellState.sessionLocked
            && (ShellState.consoleNavVisible || ShellState.controlCenterOpen || ShellState.consoleSwitcherOpen)
        navWin.WlrLayershell.keyboardFocus = grab
            ? WlrKeyboardFocus.Exclusive
            : WlrKeyboardFocus.None
      }

      Component.onCompleted: applyLayer()

      Connections {
        target: ShellState
        function onConsoleNavVisibleChanged() { navWin.applyLayer() }
        function onControlCenterOpenChanged() { navWin.applyLayer() }
        function onConsoleSwitcherOpenChanged() { navWin.applyLayer() }
        function onSessionLockedChanged() { navWin.applyLayer() }
        function onSessionStartLockPendingChanged() { navWin.applyLayer() }
      }

      ConsoleHome {
        anchors.fill: parent
        navOpacity: root.navFade
      }
    }
  }

  // Toasts — same suppress rules as desktop (DND / CC-open)
  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: toastWin
      required property var modelData
      screen: modelData

      readonly property bool isFocused: {
        const mon = Hyprland.monitorFor(modelData)
        return mon ? mon.focused : (modelData === Quickshell.screens[0])
      }
      readonly property bool showToast: isFocused && Notifications.showToast && !ShellState.sessionLocked

      visible: showToast
      exclusionMode: ExclusionMode.Ignore
      color: "transparent"

      anchors {
        top: true
        left: true
        right: true
        bottom: true
      }

      Component.onCompleted: {
        if (toastWin.WlrLayershell != null) {
          toastWin.WlrLayershell.namespace = "proteus-console-toast"
          toastWin.WlrLayershell.layer = WlrLayer.Overlay
        }
      }

      NotificationToast {
        id: toastLayer
        anchors.fill: parent
        visible: toastWin.showToast
      }

      mask: toastWin.showToast ? toastMask : emptyMask
      Region {
        id: toastMask
        item: toastLayer.cardItem
      }
      Region {
        id: emptyMask
      }
    }
  }

  // Status HUD (volume / brightness)
  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: hudWin
      required property var modelData
      screen: modelData

      readonly property bool isFocused: {
        const mon = Hyprland.monitorFor(modelData)
        return mon ? mon.focused : (modelData === Quickshell.screens[0])
      }

      visible: !ShellState.sessionLocked && isFocused && Hud.hudVisible
          && !ShellState.controlCenterOpen
      exclusionMode: ExclusionMode.Ignore
      color: "transparent"

      anchors {
        top: true
        left: true
        right: true
        bottom: true
      }

      Component.onCompleted: {
        if (hudWin.WlrLayershell != null) {
          hudWin.WlrLayershell.namespace = "proteus-console-hud"
          hudWin.WlrLayershell.layer = WlrLayer.Overlay
        }
      }

      StatusHud {
        id: hudLayer
        anchors.fill: parent
      }

      mask: hudMask
      Region {
        id: hudMask
        item: hudLayer.cardItem
      }
    }
  }
}
