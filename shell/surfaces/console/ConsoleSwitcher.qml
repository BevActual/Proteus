import Quickshell
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts
import "../../shared"

// Running-apps overlay — Hyprland toplevels (DockApps patterns).
Item {
  id: root
  anchors.fill: parent
  visible: ShellState.consoleSwitcherOpen

  property int focusedIndex: 0

  readonly property var appWindows: {
    const tops = Hyprland.toplevels ? Hyprland.toplevels.values : []
    const out = []
    for (let i = 0; i < tops.length; i++) {
      const t = tops[i]
      if (!t)
        continue
      const ipc = t.lastIpcObject || {}
      const cls = String(t.class || ipc.class || "").toLowerCase()
      const title = String(t.title || ipc.title || "")
      if (cls === "quickshell" || (title.indexOf("Proteus") === 0 && cls.indexOf("quickshell") >= 0))
        continue
      // Skip layer-ish / empty
      if (!title.length && !cls.length)
        continue
      out.push(t)
    }
    return out
  }

  function windowLabel(t) {
    if (!t)
      return "App"
    const ipc = t.lastIpcObject || {}
    const title = String(t.title || ipc.title || "")
    if (title.length)
      return title
    return String(t.class || ipc.class || "App")
  }

  function windowAddress(t) {
    if (!t)
      return ""
    const ipc = t.lastIpcObject || {}
    let addr = String(t.address || ipc.address || "")
    if (addr.length && addr.indexOf("0x") !== 0)
      addr = "0x" + addr
    return addr
  }

  function focusAt(i) {
    if (i < 0 || i >= appWindows.length)
      return
    focusedIndex = i
  }

  function activateFocused() {
    if (!appWindows.length)
      return
    const t = appWindows[Math.max(0, Math.min(focusedIndex, appWindows.length - 1))]
    const addr = windowAddress(t)
    if (addr.length) {
      Hyprland.dispatch("focuswindow address:" + addr)
      ShellState.hideConsoleNav()
    }
  }

  function closeFocused() {
    if (!appWindows.length)
      return
    const t = appWindows[Math.max(0, Math.min(focusedIndex, appWindows.length - 1))]
    const addr = windowAddress(t)
    if (addr.length)
      Hyprland.dispatch("closewindow address:" + addr)
  }

  function moveFocus(delta) {
    if (!appWindows.length)
      return
    focusedIndex = (focusedIndex + delta + appWindows.length) % appWindows.length
  }

  Rectangle {
    anchors.fill: parent
    color: Theme.scrimFill
    MouseArea {
      anchors.fill: parent
      onClicked: ShellState.closeConsoleSwitcher()
    }
  }

  Rectangle {
    anchors.centerIn: parent
    width: Math.min(parent.width - 80, Math.max(420, listRow.implicitWidth + 48))
    height: 160
    radius: Theme.radiusXl
    color: Theme.elevatedFill
    border.width: 1
    border.color: Theme.chromeBorder

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Theme.spaceLg
      spacing: Theme.spaceMd

      Text {
        text: appWindows.length ? "Open apps" : "No open apps"
        color: Theme.textDim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSm
        font.letterSpacing: 1.0
        font.weight: Font.DemiBold
      }

      Flickable {
        Layout.fillWidth: true
        Layout.fillHeight: true
        contentWidth: listRow.implicitWidth
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Row {
          id: listRow
          spacing: Theme.spaceMd

          Repeater {
            model: root.appWindows

            Rectangle {
              required property var modelData
              required property int index
              width: 140
              height: 88
              radius: Theme.radiusLg
              color: root.focusedIndex === index ? Theme.accentSoft : Theme.bgHover
              border.width: root.focusedIndex === index ? 2 : 1
              border.color: root.focusedIndex === index ? Theme.accent : Theme.chromeBorder

              Text {
                anchors.fill: parent
                anchors.margins: Theme.spaceSm
                text: root.windowLabel(modelData)
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                wrapMode: Text.WordWrap
                elide: Text.ElideRight
                maximumLineCount: 3
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignHCenter
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.focusAt(index)
                  root.activateFocused()
                }
              }
            }
          }
        }
      }
    }
  }

  onVisibleChanged: {
    if (visible) {
      Hyprland.refreshToplevels()
      focusedIndex = 0
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      // Keep list fresh while open
      if (root.visible)
        Hyprland.refreshToplevels()
    }
  }
}
