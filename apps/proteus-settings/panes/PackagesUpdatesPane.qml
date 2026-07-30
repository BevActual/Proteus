import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../shared"
import "../kit"

// Packages → Updates: selective list; propose → confirm → pkexec proteus-pkg.
ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: 12

  property bool active: false
  property var upgrades: []
  property string status: "Checking for upgrades…"
  property bool busy: false
  property string pendingAction: "" // sync | upgrade | upgrade-packages
  property string pendingDetail: ""

  readonly property bool confirming: pendingAction.length > 0
  readonly property bool applying: Packages.packageOpBusy
  readonly property var selectedNames: {
    const out = []
    for (let i = 0; i < upgrades.length; i++) {
      if (upgrades[i].selected)
        out.push(upgrades[i].name)
    }
    return out
  }
  readonly property int selectedCount: selectedNames.length
  readonly property bool allSelected: upgrades.length > 0 && selectedCount === upgrades.length
  readonly property bool noneSelected: selectedCount === 0

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

  function setSelected(name, on) {
    const next = []
    for (let i = 0; i < upgrades.length; i++) {
      const u = upgrades[i]
      next.push({
        name: u.name,
        from: u.from,
        to: u.to,
        selected: u.name === name ? !!on : !!u.selected
      })
    }
    upgrades = next
  }

  function setAllSelected(on) {
    const next = []
    for (let i = 0; i < upgrades.length; i++) {
      const u = upgrades[i]
      next.push({
        name: u.name,
        from: u.from,
        to: u.to,
        selected: !!on
      })
    }
    upgrades = next
  }

  function proposeUpgrade() {
    const n = selectedCount
    if (upgrades.length === 0) {
      pendingAction = "upgrade"
      pendingDetail = "About to run proteus-pkg upgrade → pacman -Syu (full system upgrade)."
      return
    }
    if (n === 0)
      return
    if (allSelected) {
      pendingAction = "upgrade"
      pendingDetail = "About to run proteus-pkg upgrade → pacman -Syu for all "
          + n + " pending package" + (n === 1 ? "" : "s") + "."
      return
    }
    const names = selectedNames
    const preview = names.length <= 8
        ? names.join(", ")
        : (names.slice(0, 8).join(", ") + "… (+" + (names.length - 8) + ")")
    pendingAction = "upgrade-packages"
    pendingDetail = "About to run proteus-pkg upgrade-packages → pacman -S --needed for "
        + n + " selected package" + (n === 1 ? "" : "s") + ": " + preview
        + ". Other pending upgrades stay until you select them (deps may still pull related packages)."
  }

  function runPending() {
    const a = pendingAction
    const names = selectedNames.slice()
    clearPending()
    if (a === "sync")
      Packages.openPacmanSync()
    else if (a === "upgrade")
      Packages.openPacmanUpgrade()
    else if (a === "upgrade-packages")
      Packages.openPacmanUpgradePackages(names)
  }

  Text {
    Layout.fillWidth: true
    text: "Shows packages the local DB thinks can upgrade. Sync the DB first if the list looks stale. Uncheck packages to leave them pending."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 12
    wrapMode: Text.WordWrap
  }

  PackagesConfirm {
    open: root.confirming
    title: {
      if (root.pendingAction === "sync")
        return "Sync package databases?"
      if (root.pendingAction === "upgrade-packages")
        return "Upgrade selected packages?"
      return "Upgrade system packages?"
    }
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

  RowLayout {
    Layout.fillWidth: true
    Layout.maximumWidth: 520
    spacing: Theme.spaceSm
    visible: root.upgrades.length > 0 && !root.confirming && !root.applying

    Text {
      text: root.selectedCount + " of " + root.upgrades.length + " selected"
      color: Theme.textDim
      font.family: Theme.fontFamily
      font.pixelSize: 12
      Layout.fillWidth: true
    }

    Text {
      text: root.allSelected ? "Select none" : "Select all"
      color: Theme.accent
      font.family: Theme.fontFamily
      font.pixelSize: 12
      font.bold: true
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.setAllSelected(!root.allSelected)
      }
    }
  }

  Repeater {
    model: root.upgrades

    Rectangle {
      required property var modelData
      required property int index
      Layout.fillWidth: true
      Layout.maximumWidth: 520
      Layout.preferredHeight: rowCol.implicitHeight + 20
      radius: Theme.radiusMd
      color: Theme.bgPanel
      border.width: 1
      border.color: modelData.selected ? Theme.accent : Theme.border
      opacity: root.confirming || root.applying ? 0.7 : 1

      RowLayout {
        id: rowCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.spaceMd
        spacing: Theme.spaceMd

        Rectangle {
          Layout.preferredWidth: 20
          Layout.preferredHeight: 20
          Layout.alignment: Qt.AlignVCenter
          radius: 4
          color: modelData.selected ? Theme.accent : "transparent"
          border.width: 1
          border.color: modelData.selected ? Theme.accent : Theme.border

          Text {
            anchors.centerIn: parent
            text: modelData.selected ? "✓" : ""
            color: "#ffffff"
            font.pixelSize: 12
            font.bold: true
            visible: modelData.selected
          }
        }

        ColumnLayout {
          Layout.fillWidth: true
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

      MouseArea {
        anchors.fill: parent
        enabled: !root.confirming && !root.applying
        cursorShape: Qt.PointingHandCursor
        onClicked: root.setSelected(modelData.name, !modelData.selected)
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
    opacity: (root.applying || (root.upgrades.length > 0 && root.noneSelected)) ? 0.5 : 1
    Text {
      anchors.centerIn: parent
      text: {
        if (root.applying)
          return "Applying…"
        if (root.upgrades.length === 0)
          return "Full upgrade…"
        if (root.noneSelected)
          return "Select packages to upgrade"
        if (root.allSelected)
          return "Upgrade all " + root.selectedCount + "…"
        return "Upgrade " + root.selectedCount + " selected…"
      }
      color: Theme.text
      font.family: Theme.fontFamily
      font.bold: true
      font.pixelSize: 12
    }
    MouseArea {
      anchors.fill: parent
      enabled: !root.applying && !(root.upgrades.length > 0 && root.noneSelected)
      cursorShape: Qt.PointingHandCursor
      onClicked: root.proposeUpgrade()
    }
  }

  Text {
    Layout.fillWidth: true
    text: "Fact: pacman -Qu · Apply: pkexec proteus-pkg sync|upgrade|upgrade-packages (live progress)"
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
              to: m[3],
              selected: true
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
