pragma Singleton

import Quickshell
import QtQuick

Singleton {
  property bool launcherOpen: false

  // Hardware probe mirrors (session start — see Hardware.qml)
  readonly property bool hwReady: Hardware.ready
  readonly property bool hwProbing: Hardware.probing
  readonly property string deviceClass: Hardware.deviceClass
  readonly property string postureHint: Hardware.postureHint
  readonly property var capabilities: Hardware.capabilityList
  readonly property string hwError: Hardware.error

  function hasCapability(cap) {
    return Hardware.has(cap)
  }

  function refreshHardware() {
    Hardware.refresh()
  }

  function closeOverlays() {
    launcherOpen = false
  }

  function toggleLauncher() {
    launcherOpen = !launcherOpen
  }

  function openLauncher() {
    launcherOpen = true
  }

  function closeLauncher() {
    launcherOpen = false
  }

  function openSettings() {
    launcherOpen = false
    // Prefer installed launcher; fall back to repo path on the 9p share
    Quickshell.execDetached({
      command: ["bash", "-lc", "command -v proteus-settings >/dev/null && exec proteus-settings || exec /mnt/proteus/apps/proteus-settings/proteus-settings"]
    })
  }
}
