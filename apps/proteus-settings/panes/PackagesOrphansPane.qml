import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../shared"
import "../kit"

// Packages → Orphans: list pacman -Qdt; remove via confirm → proteus-pkg orphans.
ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: 12

  property bool active: false
  property var orphans: []
  property string status: "Checking for orphans…"
  property bool busy: false
  property bool pendingRemove: false

  readonly property bool confirming: pendingRemove
  readonly property bool applying: Packages.packageOpBusy

  function clearPending() {
    pendingRemove = false
  }

  function refresh() {
    clearPending()
    busy = true
    status = "Checking for orphans…"
    orphans = []
    listProc.running = false
    listProc.running = true
  }

  Text {
    Layout.fillWidth: true
    text: "Packages installed as dependencies that nothing needs anymore. Removing runs pacman -Rns on the orphan set."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 12
    wrapMode: Text.WordWrap
  }

  PackagesConfirm {
    open: root.confirming
    title: "Remove orphan packages?"
    detail: root.orphans.length
        ? ("About to run proteus-pkg orphans → pacman -Rns for "
           + root.orphans.length + " package" + (root.orphans.length === 1 ? "" : "s") + ".")
        : "No orphans to remove."
    onCancelled: root.clearPending()
    onConfirmed: {
      root.clearPending()
      if (root.orphans.length)
        Packages.openPacmanOrphans()
    }
  }

  PackagesOpProgress {}

  Text {
    Layout.fillWidth: true
    text: root.status
    color: Theme.textDim
    font.family: Theme.fontFamily
    font.pixelSize: 12
    wrapMode: Text.WordWrap
    visible: root.orphans.length === 0 && !root.confirming && !root.applying
  }

  Flickable {
    id: orphanFlick
    Layout.fillWidth: true
    Layout.maximumWidth: 520
    Layout.preferredHeight: Math.min(360, Math.max(0, orphanCol.implicitHeight))
    contentWidth: width
    contentHeight: orphanCol.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    visible: !root.confirming && root.orphans.length > 0
    interactive: contentHeight > height

    ColumnLayout {
      id: orphanCol
      width: orphanFlick.width
      spacing: 8

      Repeater {
        model: root.orphans

        Rectangle {
          required property var modelData
          Layout.fillWidth: true
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
              text: modelData.version
              color: Theme.textDim
              font.family: Theme.fontFamily
              font.pixelSize: 11
              wrapMode: Text.WrapAnywhere
            }
          }
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
      color: Theme.accentSoft
      border.width: 1
      border.color: Theme.accent
      opacity: (root.applying || root.orphans.length === 0) ? 0.6 : 1
      Text {
        anchors.centerIn: parent
        text: root.applying
            ? "Applying…"
            : (root.orphans.length ? ("Remove " + root.orphans.length + "…") : "No orphans")
        color: Theme.text
        font.family: Theme.fontFamily
        font.bold: true
        font.pixelSize: 12
      }
      MouseArea {
        anchors.fill: parent
        enabled: !root.applying && root.orphans.length > 0
        cursorShape: Qt.PointingHandCursor
        onClicked: root.pendingRemove = true
      }
    }
  }

  Text {
    Layout.fillWidth: true
    text: "Fact: pacman -Qdt · Apply: pkexec proteus-pkg orphans (live $ command + Cancel)"
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
    id: listProc
    command: ["pacman", "-Qdt"]
    stdout: StdioCollector {
      onStreamFinished: {
        const lines = text.trim().split("\n").filter(l => l.length)
        const out = []
        for (let i = 0; i < lines.length; i++) {
          const m = lines[i].match(/^(\S+)\s+(\S+)/)
          if (m) {
            out.push({
              name: m[1],
              version: m[2]
            })
          }
        }
        root.orphans = out
        root.busy = false
        root.status = out.length ? "" : "No orphan packages."
      }
    }
    stderr: StdioCollector {
      onStreamFinished: {
        // pacman -Qdt exits 1 with empty stdout when there are no orphans
        if (root.busy && root.orphans.length === 0) {
          root.busy = false
          if (!root.status || root.status.indexOf("Checking") === 0)
            root.status = "No orphan packages."
        }
      }
    }
    onExited: (exitCode, exitStatus) => {
      if (root.busy && root.orphans.length === 0 && exitCode !== 0) {
        root.busy = false
        if (!root.status.length || root.status.indexOf("Checking") === 0)
          root.status = "No orphan packages."
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
