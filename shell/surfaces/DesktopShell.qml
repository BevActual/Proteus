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
    name: "customize-desktop"
    description: "Customize desktop widgets"
    onPressed: ShellState.enterDesktopCustomize()
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

    // Dogfood/recovery escape (same-user IPC only — no privilege boundary):
    // re-acquire + release the ext-session-lock cleanly, e.g. after a shell
    // restart tripped Hyprland's crashed-lockscreen guard.
    function unlock(): void {
      ShellState.unlockSession()
    }
  }

  // Smoke/dogfood probe: drive chrome surfaces from the CLI.
  //   qs -p <config> ipc call chrome controlCenter
  //   qs -p <config> ipc call chrome state
  IpcHandler {
    target: "chrome"

    function controlCenter(): void {
      ShellState.toggleControlCenter()
    }

    function calendar(): void {
      ShellState.toggleCalendar()
    }

    function customizeDesktop(): void {
      if (ShellState.desktopCustomizeMode)
        ShellState.exitDesktopCustomize()
      else
        ShellState.enterDesktopCustomize()
    }

    function launcher(): void {
      ShellState.toggleLauncher()
    }

    // Beacon probes — seed a query, then read the result summary:
    //   qs -p <config> ipc call chrome beacon reboot
    //   qs -p <config> ipc call chrome beaconState
    function beacon(query: string): void {
      ShellState.seedBeaconQuery(query)
    }

    function beaconState(): string {
      return ShellState.beaconProbe
    }

    function state(): string {
      return JSON.stringify({
        controlCenter: ShellState.controlCenterOpen,
        calendar: ShellState.calendarOpen,
        launcher: ShellState.launcherOpen,
        customize: ShellState.desktopCustomizeMode,
        locked: ShellState.sessionLocked
      })
    }
  }

  IpcHandler {
    target: "hud"
    function ping(): void {
      Hud.show("demo", 64, "HUD")
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
    function brightnessDemo(): void {
      Hud.show("brightness", 60, "Brightness")
    }
    function hide(): void {
      Hud.hide()
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
    function onControlCenterOpenChanged() {
      // Volume HUD must not stack over the quick menu
      if (ShellState.controlCenterOpen)
        Hud.hide()
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

      // Raised + keyboard grab while customizing or editing a Note in place;
      // plain click-through Bottom surface otherwise.
      function applyLayerState() {
        if (deskWidgetsWin.WlrLayershell == null)
          return
        const raised = ShellState.desktopCustomizeMode || ShellState.desktopNoteEditing
        deskWidgetsWin.WlrLayershell.layer = raised ? WlrLayer.Overlay : WlrLayer.Bottom
        deskWidgetsWin.WlrLayershell.keyboardFocus = raised
            ? WlrKeyboardFocus.Exclusive
            : WlrKeyboardFocus.None
      }

      Component.onCompleted: {
        if (deskWidgetsWin.WlrLayershell != null)
          deskWidgetsWin.WlrLayershell.namespace = "proteus-desktop-widgets"
        applyLayerState()
      }

      Connections {
        target: ShellState
        function onDesktopCustomizeModeChanged() {
          deskWidgetsWin.applyLayerState()
        }
        function onDesktopNoteEditingChanged() {
          deskWidgetsWin.applyLayerState()
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
      // leave the focused client (editor/terminal) while Beacon is open.
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
        // Lighter than Control Center scrim — Beacon floats on the desktop
        color: Theme.light ? Qt.rgba(0, 0, 0, 0.14) : Qt.rgba(0, 0, 0, 0.32)
        MouseArea {
          anchors.fill: parent
          onClicked: ShellState.closeLauncher()
        }
      }

      Beacon {
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

      // stillVisible keeps the window mapped while close animations play
      // (ControlCenter / CalendarPanel own their open/close motion).
      visible: !ShellState.sessionLocked && isFocused
          && (ccView.stillVisible || calView.stillVisible || showToast)
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
        id: ccView
        anchors.fill: parent
      }

      CalendarPanel {
        id: calView
        anchors.fill: parent
      }

      NotificationToast {
        id: toastLayer
        anchors.fill: parent
        visible: ccWin.showToast
      }

      // Full input while CC / calendar is open; toast-only shows click-through
      // except the card; during exit animations the surface is click-through.
      mask: ShellState.controlCenterOpen || ShellState.calendarOpen
          ? null
          : (showToast ? toastMask : emptyMask)

      Region {
        id: toastMask
        item: toastLayer.cardItem
      }

      Region {
        id: emptyMask
      }
    }
  }

  // Status / HUD glass chip (own overlay — independent of toast/CC)
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
          hudWin.WlrLayershell.namespace = "proteus-hud"
          hudWin.WlrLayershell.layer = WlrLayer.Overlay
        }
      }

      StatusHud {
        id: hudLayer
        anchors.fill: parent
      }

      // Click-through: only the chip geometry is in the input region, and the
      // chip itself has no MouseArea — Wayland still needs a non-empty mask
      // for some compositors to map the layer.
      mask: hudMask
      Region {
        id: hudMask
        item: hudLayer.cardItem
      }
    }
  }
}
