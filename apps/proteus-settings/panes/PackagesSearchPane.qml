import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../shared"
import "../kit"

// Packages → Repos: Omarchy-style Install / Remove picker (searchable + multi-select).
ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: 12

  property bool active: false
  property string mode: "remove" // install | remove — open on inventory (what you have)
  property var results: []
  property string status: ""
  property bool busy: false
  property string query: ""
  property string pendingDetail: ""
  property string pendingAction: "" // install | remove
  property var pendingNames: []
  property var installedSet: ({})
  property int resultCap: 60

  readonly property bool confirming: pendingAction.length > 0
  readonly property bool applying: Packages.packageOpBusy
  readonly property var selectedNames: {
    const out = []
    for (let i = 0; i < results.length; i++) {
      if (results[i].selected)
        out.push(results[i].name)
    }
    return out
  }
  readonly property int selectedCount: selectedNames.length

  function clearPending() {
    pendingDetail = ""
    pendingAction = ""
    pendingNames = []
  }

  function isInstalled(name) {
    return !!(installedSet && installedSet[name])
  }

  function refreshInstalled() {
    installedProc.running = false
    installedProc.running = true
  }

  function setSelected(name, on) {
    const next = []
    for (let i = 0; i < results.length; i++) {
      const u = results[i]
      next.push(Object.assign({}, u, {
        selected: u.name === name ? !!on : !!u.selected
      }))
    }
    results = next
  }

  function setAllSelected(on) {
    const next = []
    for (let i = 0; i < results.length; i++) {
      next.push(Object.assign({}, results[i], {
        selected: !!on
      }))
    }
    results = next
  }

  function search() {
    clearPending()
    const q = query.trim()
    if (mode === "remove") {
      busy = true
      status = "Loading installed packages…"
      removeListProc.running = false
      removeListProc.running = true
      return
    }
    if (q.length < 2) {
      busy = true
      status = "Loading available packages…"
      browseProc.running = false
      browseProc.running = true
      return
    }
    busy = true
    status = "Searching…"
    searchProc.command = ["pacman", "-Ss", "--", q]
    searchProc.running = false
    searchProc.running = true
  }

  function scheduleSearch() {
    debounce.restart()
  }

  function proposeBatch() {
    const names = selectedNames
    if (!names.length)
      return
    pendingNames = names.slice()
    pendingAction = mode
    const preview = names.length <= 8 ? names.join(", ") : (names.slice(0, 8).join(", ") + "…")
    pendingDetail = mode === "remove"
        ? ("Remove " + names.length + " package" + (names.length === 1 ? "" : "s") + " via proteus-pkg remove → pacman -Rns: " + preview)
        : ("Install " + names.length + " package" + (names.length === 1 ? "" : "s") + " via proteus-pkg install: " + preview)
  }

  function runPending() {
    const act = pendingAction
    const names = pendingNames.slice()
    clearPending()
    if (act === "remove")
      Packages.openPacmanRemoveMany(names)
    else
      Packages.openPacmanInstallMany(names)
  }

  Text {
    Layout.fillWidth: true
    text: "Official repos — fuzzy search, multi-select (like Omarchy Package install/remove), then confirm."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 12
    wrapMode: Text.WordWrap
  }

  SettingsSegmented {
    Layout.maximumWidth: 520
    visible: !root.confirming
    options: [
      {
        id: "install",
        label: "Install"
      },
      {
        id: "remove",
        label: "Remove"
      }
    ]
    selected: root.mode
    onActivated: id => {
      root.mode = id
      root.results = []
      root.search()
    }
  }

  PackagesConfirm {
    open: root.confirming
    title: root.pendingAction === "remove" ? "Remove packages?" : "Install packages?"
    detail: root.pendingDetail
    onCancelled: root.clearPending()
    onConfirmed: root.runPending()
  }

  Text {
    Layout.fillWidth: true
    visible: root.applying
    text: Packages.packageOpStatus
    color: Theme.textDim
    font.family: Theme.fontFamily
    font.pixelSize: 12
    wrapMode: Text.WordWrap
  }

  RowLayout {
    Layout.fillWidth: true
    Layout.maximumWidth: 520
    spacing: Theme.spaceSm
    visible: !root.confirming

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 36
      radius: Theme.radius
      color: Theme.bgPanel
      border.width: 1
      border.color: searchInput.activeFocus ? Theme.accent : Theme.border
      TextInput {
        id: searchInput
        anchors.fill: parent
        anchors.leftMargin: Theme.spaceMd
        anchors.rightMargin: Theme.spaceMd
        verticalAlignment: TextInput.AlignVCenter
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        selectByMouse: true
        clip: true
        text: root.query
        onTextChanged: {
          root.query = text
          root.scheduleSearch()
        }
        Keys.onReturnPressed: {
          debounce.stop()
          root.search()
        }
        Keys.onEnterPressed: {
          debounce.stop()
          root.search()
        }
        Text {
          anchors.fill: parent
          verticalAlignment: Text.AlignVCenter
          text: root.mode === "remove" ? "Filter installed…" : "Search or browse packages…"
          color: Theme.textMute
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSize
          visible: !searchInput.text.length && !searchInput.activeFocus
        }
      }
    }
  }

  RowLayout {
    Layout.fillWidth: true
    Layout.maximumWidth: 520
    visible: root.results.length > 0 && !root.confirming && !root.applying
    Text {
      Layout.fillWidth: true
      text: root.selectedCount + " of " + root.results.length + " selected"
      color: Theme.textDim
      font.family: Theme.fontFamily
      font.pixelSize: 12
    }
    Text {
      text: root.selectedCount === root.results.length ? "Select none" : "Select all"
      color: Theme.accent
      font.family: Theme.fontFamily
      font.pixelSize: 12
      font.bold: true
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.setAllSelected(root.selectedCount !== root.results.length)
      }
    }
  }

  Text {
    Layout.fillWidth: true
    text: root.busy ? (root.mode === "remove" ? "Loading…" : "Searching…") : root.status
    color: Theme.textDim
    font.family: Theme.fontFamily
    font.pixelSize: 12
    wrapMode: Text.WordWrap
    visible: root.results.length === 0 && !root.confirming && !root.applying
  }

  Repeater {
    model: root.results

    Rectangle {
      required property var modelData
      Layout.fillWidth: true
      Layout.maximumWidth: 520
      Layout.preferredHeight: pkgCol.implicitHeight + 20
      radius: Theme.radiusMd
      color: Theme.bgPanel
      border.width: 1
      border.color: modelData.selected ? Theme.accent : Theme.border
      visible: !root.confirming
      opacity: root.applying ? 0.7 : 1

      RowLayout {
        id: pkgCol
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
          RowLayout {
            Layout.fillWidth: true
            Text {
              Layout.fillWidth: true
              text: modelData.repo ? (modelData.repo + "/" + modelData.name) : modelData.name
              color: Theme.text
              font.family: Theme.fontFamily
              font.pixelSize: Theme.fontSize
              font.bold: true
              elide: Text.ElideRight
            }
            Text {
              visible: !!modelData.installed && root.mode === "install"
              text: "Installed"
              color: Theme.accent
              font.family: Theme.fontFamily
              font.pixelSize: 10
              font.bold: true
            }
            Text {
              text: modelData.version || ""
              color: Theme.textDim
              font.family: Theme.fontFamily
              font.pixelSize: 11
              visible: !!(modelData.version && modelData.version.length)
            }
          }
          Text {
            Layout.fillWidth: true
            text: modelData.desc || ""
            color: Theme.textMute
            font.family: Theme.fontFamily
            font.pixelSize: 11
            wrapMode: Text.WordWrap
            visible: !!(modelData.desc && modelData.desc.length)
          }
        }
      }

      MouseArea {
        anchors.fill: parent
        enabled: !root.applying
        cursorShape: Qt.PointingHandCursor
        onClicked: root.setSelected(modelData.name, !modelData.selected)
      }
    }
  }

  Rectangle {
    Layout.fillWidth: true
    Layout.maximumWidth: 520
    Layout.preferredHeight: 44
    radius: Theme.radiusMd
    color: root.mode === "remove"
        ? Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.14)
        : Theme.accentSoft
    border.width: 1
    border.color: root.mode === "remove" ? Theme.danger : Theme.accent
    visible: !root.confirming
    opacity: (root.applying || root.selectedCount === 0) ? 0.5 : 1
    Text {
      anchors.centerIn: parent
      text: {
        if (root.applying)
          return "Applying…"
        if (root.selectedCount === 0)
          return root.mode === "remove" ? "Select packages to remove" : "Select packages to install"
        return (root.mode === "remove" ? "Remove " : "Install ") + root.selectedCount + "…"
      }
      color: Theme.text
      font.family: Theme.fontFamily
      font.bold: true
      font.pixelSize: 12
    }
    MouseArea {
      anchors.fill: parent
      enabled: !root.applying && root.selectedCount > 0
      cursorShape: Qt.PointingHandCursor
      onClicked: root.proposeBatch()
    }
  }

  Text {
    Layout.fillWidth: true
    text: "Fact: pacman -Ss / -Qqe · Apply: pkexec proteus-pkg install|remove (multi)"
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 11
    wrapMode: Text.WordWrap
  }

  Timer {
    id: debounce
    interval: 280
    repeat: false
    onTriggered: root.search()
  }

  Connections {
    target: Packages
    function onPackageOpFinished(ok, message) {
      if (!root.active)
        return
      root.status = message
      root.refreshInstalled()
      if (ok)
        root.search()
    }
  }

  Process {
    id: installedProc
    command: ["pacman", "-Qq"]
    stdout: StdioCollector {
      onStreamFinished: {
        const map = ({})
        const lines = text.trim().split("\n")
        for (let i = 0; i < lines.length; i++) {
          const n = lines[i].trim()
          if (n.length)
            map[n] = true
        }
        root.installedSet = map
      }
    }
  }

  Process {
    id: removeListProc
    command: ["pacman", "-Qqe"]
    stdout: StdioCollector {
      onStreamFinished: {
        const q = root.query.trim().toLowerCase()
        const lines = text.trim().split("\n").filter(l => l.length)
        const out = []
        for (let i = 0; i < lines.length; i++) {
          const name = lines[i].trim()
          if (!name.length)
            continue
          if (q.length && name.toLowerCase().indexOf(q) < 0)
            continue
          out.push({
            name: name,
            repo: "",
            version: "",
            desc: "",
            installed: true,
            selected: false
          })
        }
        const ranked = Packages.sortSearchResults(root.query, out)
        root.results = ranked.slice(0, root.resultCap)
        root.busy = false
        root.status = ranked.length ? "" : (q.length ? "No installed packages matched." : "No explicitly installed packages.")
      }
    }
  }

  Process {
    id: browseProc
    command: [
      "bash",
      "-lc",
      "comm -23 <(pacman -Slq | sort -u) <(pacman -Qq | sort -u) | head -n " + String(root.resultCap)
    ]
    stdout: StdioCollector {
      onStreamFinished: {
        if (root.mode !== "install" || root.query.trim().length >= 2)
          return
        const lines = text.trim().split("\n").filter(l => l.length)
        const out = []
        for (let i = 0; i < lines.length; i++) {
          const name = lines[i].trim()
          if (!name.length)
            continue
          out.push({
            name: name,
            repo: "",
            version: "",
            desc: "Available",
            installed: false,
            selected: false
          })
        }
        root.results = out
        root.busy = false
        root.status = out.length
            ? "Browsing available packages — type ≥2 characters to search."
            : "No uninstalled packages found in sync DB."
      }
    }
    onExited: (exitCode, exitStatus) => {
      if (root.busy && root.mode === "install" && root.query.trim().length < 2 && root.results.length === 0 && exitCode !== 0)
        root.busy = false
    }
  }

  Process {
    id: searchProc
    command: ["true"]
    stdout: StdioCollector {
      onStreamFinished: {
        const lines = text.split("\n")
        const out = []
        let cur = null
        for (let i = 0; i < lines.length; i++) {
          const line = lines[i]
          const head = line.match(/^([a-z0-9_-]+)\/(\S+)\s+(\S+)/)
          if (head) {
            if (cur)
              out.push(cur)
            const rest = line.slice(head[0].length)
            cur = {
              repo: head[1],
              name: head[2],
              version: head[3],
              desc: "",
              installed: /\[installed/.test(rest) || root.isInstalled(head[2]),
              selected: false
            }
            continue
          }
          if (cur && line.match(/^\s+/))
            cur.desc = line.trim()
        }
        if (cur)
          out.push(cur)
        const ranked = Packages.sortSearchResults(root.query, out)
        root.results = ranked.slice(0, root.resultCap)
        root.busy = false
        root.status = ranked.length ? "" : "No packages matched."
      }
    }
    stderr: StdioCollector {
      onStreamFinished: {
        if (text.trim().length && root.results.length === 0) {
          root.busy = false
          root.status = text.trim().split("\n")[0]
        }
      }
    }
    onExited: (exitCode, exitStatus) => {
      if (root.busy && root.results.length === 0 && exitCode !== 0)
        root.busy = false
    }
  }

  onActiveChanged: {
    if (active) {
      refreshInstalled()
      search()
      Qt.callLater(() => searchInput.forceActiveFocus())
    } else {
      debounce.stop()
      clearPending()
    }
  }

  onModeChanged: {
    if (active)
      search()
  }
}
