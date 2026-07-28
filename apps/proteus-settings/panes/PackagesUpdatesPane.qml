import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../shared"

// Packages → Updates: list upgradable; propose → confirm → pkexec proteus-pkg.
ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: 12

  property bool active: false
  property var upgrades: []
  property string status: "Checking for upgrades…"
  property bool busy: false
  property string pendingAction: "" // sync | upgrade
  property string pendingDetail: ""

  readonly property bool confirming: pendingAction.length > 0
  readonly property bool applying: Packages.packageOpBusy

  function clearPending() {
    pendingAction = ""
    pendingDetail = ""
  }

  function refresh() {
    clearPending()
    busy = true
    status = "Checking for upgrades…"
    upgrades = []
    checkProc.running = false
    checkProc.running = true
  }

  function runPending() {
    const a = pendingAction
    clearPending()
    if (a === "sync")
      Packages.openPacmanSync()
    else if (a === "upgrade")
      Packages.openPacmanUpgrade()
  }

  Text {
    Layout.fillWidth: true
    text: "Shows packages the local DB thinks can upgrade. Sync the DB first if the list looks stale."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 12
    wrapMode: Text.WordWrap
  }

  PackagesConfirm {
    open: root.confirming
    title: root.pendingAction === "sync" ? "Sync package databases?" : "Upgrade system packages?"
    detail: root.pendingDetail
    onCancelled: root.clearPending()
    onConfirmed: root.runPending()
  }

  Text {
    Layout.fillWidth: true
    text: root.applying ? Packages.packageOpStatus : root.status
    color: Theme.textDim
    font.family: Theme.fontFamily
    font.pixelSize: 12
    wrapMode: Text.WordWrap
    visible: (root.upgrades.length === 0 || root.applying) && !root.confirming
  }

  Repeater {
    model: root.upgrades

    Rectangle {
      required property var modelData
      Layout.fillWidth: true
      Layout.maximumWidth: 520
      Layout.preferredHeight: rowCol.implicitHeight + 20
      radius: Theme.radiusMd
      color: Theme.bgPanel
      border.width: 1
      border.color: Theme.border

      ColumnLayout {
        id: rowCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.spaceMd
        spacing: 2

        Text {
          text: modelData.name
          color: Theme.text
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSize
          font.bold: true
        }
        Text {
          Layout.fillWidth: true
          text: modelData.from + " → " + modelData.to
          color: Theme.textDim
          font.family: Theme.fontFamily
          font.pixelSize: 11
          wrapMode: Text.WrapAnywhere
        }
      }
    }
  }

  RowLayout {
    Layout.fillWidth: true
    Layout.maximumWidth: 520
    spacing: Theme.spaceSm
    visible: !root.confirming

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 40
      radius: Theme.radiusMd
      color: Theme.bgPanel
      border.width: 1
      border.color: Theme.border
      opacity: (root.busy || root.applying) ? 0.6 : 1
      Text {
        anchors.centerIn: parent
        text: root.busy ? "Checking…" : "Refresh"
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: 12
      }
      MouseArea {
        anchors.fill: parent
        enabled: !root.busy && !root.applying
        cursorShape: Qt.PointingHandCursor
        onClicked: root.refresh()
      }
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 40
      radius: Theme.radiusMd
      color: Theme.bgPanel
      border.width: 1
      border.color: Theme.border
      opacity: root.applying ? 0.6 : 1
      Text {
        anchors.centerIn: parent
        text: "Sync DB…"
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: 12
      }
      MouseArea {
        anchors.fill: parent
        enabled: !root.applying
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          root.pendingAction = "sync"
          root.pendingDetail = "Runs proteus-pkg sync → pacman -Sy (polkit)."
        }
      }
    }
  }

  Rectangle {
    Layout.fillWidth: true
    Layout.maximumWidth: 520
    Layout.preferredHeight: 44
    radius: Theme.radiusMd
    color: Theme.accentSoft
    border.width: 1
    border.color: Theme.accent
    visible: !root.confirming
    opacity: root.applying ? 0.6 : 1
    Text {
      anchors.centerIn: parent
      text: root.applying ? "Applying…" : (root.upgrades.length ? ("Upgrade " + root.upgrades.length + "…") : "Full upgrade…")
      color: Theme.text
      font.family: Theme.fontFamily
      font.bold: true
      font.pixelSize: 12
    }
    MouseArea {
      anchors.fill: parent
      enabled: !root.applying
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        const n = root.upgrades.length
        root.pendingAction = "upgrade"
        root.pendingDetail = n
            ? ("About to run proteus-pkg upgrade → pacman -Syu for " + n + " pending package" + (n === 1 ? "" : "s") + ".")
            : "About to run proteus-pkg upgrade → pacman -Syu (full system upgrade)."
      }
    }
  }

  Text {
    Layout.fillWidth: true
    text: "Fact: pacman -Qu · Apply: pkexec proteus-pkg (after confirm)"
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 11
    wrapMode: Text.WordWrap
  }

  Connections {
    target: Packages
    function onPackageOpFinished(ok, message) {
      if (!root.active)
        return
      root.status = message
      if (ok)
        root.refresh()
    }
  }

  Process {
    id: checkProc
    command: ["pacman", "-Qu"]
    stdout: StdioCollector {
      onStreamFinished: {
        const lines = text.trim().split("\n").filter(l => l.length)
        const out = []
        for (let i = 0; i < lines.length; i++) {
          const m = lines[i].match(/^(\S+)\s+(\S+)\s+->\s+(\S+)/)
          if (m) {
            out.push({
              name: m[1],
              from: m[2],
              to: m[3]
            })
          }
        }
        root.upgrades = out
        root.busy = false
        if (!out.length) {
          root.status = lines.length ? "Could not parse pacman -Qu output." : "System is up to date (local DB)."
          Packages.notePackageUpgrades(0)
        } else {
          root.status = ""
          Packages.notePackageUpgrades(out.length)
        }
      }
    }
    stderr: StdioCollector {
      onStreamFinished: {
        if (text.trim().length && root.upgrades.length === 0) {
          root.busy = false
          root.status = text.trim().split("\n")[0]
        }
      }
    }
  }

  onActiveChanged: {
    if (active)
      refresh()
    else
      clearPending()
  }

  Component.onCompleted: {
    if (active)
      refresh()
  }
}
