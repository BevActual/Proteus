pragma Singleton

import Quickshell
import QtQuick

// Status / HUD glass family SoT — show/hide/auto-dismiss only (#1157).
// Volume/brightness wiring lands in #1158–#1159.
Singleton {
  id: root

  property bool hudVisible: false
  property string kind: "demo"
  property int value: 0
  property string title: "HUD"
  property int seq: 0

  readonly property string glyph: {
    if (kind === "volume")
      return value <= 0 ? "MUTE" : "VOL"
    if (kind === "brightness")
      return "BRT"
    return "HUD"
  }

  function show(k, v, t) {
    const kindIn = String(k || "demo")
    // Volume/brightness HUD stays out of the way of Control Center quick menu
    if (ShellState.controlCenterOpen && (kindIn === "volume" || kindIn === "brightness"))
      return
    kind = kindIn.length ? kindIn : "demo"
    value = Math.max(0, Math.min(100, Math.round(Number(v) || 0)))
    const titleIn = String(t || "")
    if (titleIn.length)
      title = titleIn
    else if (kind === "volume")
      title = "Sound"
    else if (kind === "brightness")
      title = "Brightness"
    else
      title = "HUD"
    hudVisible = true
    seq++
    hideTimer.restart()
  }

  function hide() {
    hudVisible = false
    hideTimer.stop()
  }

  Timer {
    id: hideTimer
    interval: 1500
    repeat: false
    onTriggered: root.hide()
  }
}
