import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../shared"
import "../kit"

// Packages → Flathub: Flatpak (--user) Install / Remove picker via the Flathub remote.
ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: 12

  property bool active: false
  property string mode: "remove" // open on installed Flatpaks
  property var results: []
  property var installed: []
  property var remotes: []
  property string status: ""
  property bool busy: false
  property string query: ""
  property string pendingDetail: ""
  property string pendingAction: "" // install | remove | update | flathub
  property var pendingRefs: []
  property int resultCap: 60

  readonly property bool confirming: pendingAction.length > 0
  readonly property bool applying: Packages.packageOpBusy
  readonly property bool flatpakOk: Packages.flatpakAvailable
  readonly property bool hasFlathub: {
    if (Packages.flathubConfigured)
      return true
    for (let i = 0; i < remotes.length; i++) {
      if (String(remotes[i]).toLowerCase() === "flathub")
        return true
    }
    return false
  }
  readonly property var installedSet: {
    const map = ({})
    for (let i = 0; i < installed.length; i++) {
      if (installed[i].ref)
        map[installed[i].ref] = true
    }
    return map
  }
  readonly property var selectedRefs: {
    const out = []
    for (let i = 0; i < results.length; i++) {
      if (results[i].selected)
        out.push(results[i].ref)
    }
    return out
  }
  readonly property int selectedCount: selectedRefs.length

  function clearPending() {
    pendingDetail = ""
    pendingAction = ""
    pendingRefs = []
  }

  function isInstalled(ref) {
    return !!(installedSet && installedSet[ref])
  }

  function refreshMeta() {
    if (!flatpakOk)
      return
    remotesProc.running = false
    remotesProc.running = true
    installedProc.running = false
    installedProc.running = true
  }

  function ensureFlathubPrompt() {
    if (!flatpakOk || hasFlathub || confirming || applying)
      return
    pendingAction = "flathub"
    pendingDetail = "Adds the Flathub remote for your user (--if-not-exists). Needed to search and install apps."
  }

  function setSelected(ref, on) {
    const next = []
    for (let i = 0; i < results.length; i++) {
      const u = results[i]
      next.push(Object.assign({}, u, {
        selected: u.ref === ref ? !!on : !!u.selected
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
    if (!flatpakOk) {
      status = "Install flatpak to use Flatpak from Settings."
      results = []
      busy = false
      return
    }
    if (mode === "remove") {
      const q = query.trim().toLowerCase()
      const out = []
      for (let i = 0; i < installed.length; i++) {
        const it = installed[i]
        const hay = (it.name + " " + it.ref).toLowerCase()
        if (q.length && hay.indexOf(q) < 0)
          continue
        out.push({
          ref: it.ref,
          name: it.name,
          version: "",
          desc: it.ref,
          repo: "flathub",
          installed: true,
          selected: false
        })
      }
      results = Packages.sortSearchResults(query, out).slice(0, resultCap)
      busy = false
      status = results.length ? "" : (q.length ? "No installed Flatpaks matched." : "No user Flatpaks installed.")
      return
    }
    if (!hasFlathub) {
      status = "Add Flathub to search and install apps."
      results = []
      busy = false
      ensureFlathubPrompt()
      return
    }
    const q = query.trim()
    if (q.length < 2) {
      busy = true
      status = "Loading Flathub apps…"
      browseProc.running = false
      browseProc.running = true
      return
    }
    busy = true
    status = "Searching Flathub…"
    searchProc.command = ["flatpak", "search", "--columns=application:f,name,version,description", q]
    searchProc.running = false
    searchProc.running = true
  }

  function scheduleSearch() {
    if (!flatpakOk)
      return
    debounce.restart()
  }

  function proposeBatch() {
    const refs = selectedRefs
    if (!refs.length)
      return
    pendingRefs = refs.slice()
    pendingAction = mode
    const preview = refs.length <= 6 ? refs.join(", ") : (refs.slice(0, 6).join(", ") + "…")
    pendingDetail = mode === "remove"
        ? ("Uninstall " + refs.length + " Flatpak(s) (--user): " + preview)
        : ("Install from Flathub (--user): " + preview)
  }

  function runPending() {
    const act = pendingAction
    const refs = pendingRefs.slice()
    clearPending()
    if (act === "update")
      Packages.flatpakUpdate()
    else if (act === "flathub")
      Packages.flatpakAddFlathub()
    else if (act === "remove")
      Packages.flatpakRemoveMany(refs)
    else
      Packages.flatpakInstallMany(refs)
  }

  Text {
    Layout.fillWidth: true
    text: !flatpakOk
        ? "Flatpak is not installed. Install the flatpak package, then reopen this page."
        : (hasFlathub
            ? "Flathub (--user) — searchable multi-select Install / Remove."
            : "Flathub remote is missing. Add it once, then search and install apps.")
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 12
    wrapMode: Text.WordWrap
  }

  SettingsSegmented {
    Layout.maximumWidth: 520
    visible: root.flatpakOk && !root.confirming
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

  RowLayout {
    Layout.fillWidth: true
    Layout.maximumWidth: 520
    spacing: Theme.spaceSm
    visible: root.flatpakOk && !root.confirming

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 36
      radius: Theme.radiusMd
      color: Theme.bgPanel
      border.width: 1
      border.color: Theme.border
      opacity: root.applying ? 0.6 : 1
      Text {
        anchors.centerIn: parent
        text: "Update…"
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: 12
      }
      MouseArea {
        anchors.fill: parent
        enabled: !root.applying
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          root.pendingAction = "update"
          root.pendingDetail = "Runs flatpak update -y --user."
        }
      }
    }
    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 36
      radius: Theme.radiusMd
      color: Theme.accentSoft
      border.width: 1
      border.color: Theme.accent
      visible: !root.hasFlathub
      Text {
        anchors.centerIn: parent
        text: "Add Flathub…"
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: 12
        font.bold: true
      }
      MouseArea {
        anchors.fill: parent
        enabled: !root.applying
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          root.pendingAction = "flathub"
          root.pendingDetail = "Adds the Flathub remote for your user (--if-not-exists)."
        }
      }
    }
  }

  PackagesConfirm {
    open: root.confirming
    title: root.pendingAction === "update" ? "Update Flatpaks?"
        : (root.pendingAction === "flathub" ? "Add Flathub?"
            : (root.pendingAction === "remove" ? "Remove Flatpaks?" : "Install Flatpaks?"))
    detail: root.pendingDetail
    footnote: "Runs flatpak as your user."
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
    visible: root.flatpakOk && !root.confirming
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
          text: root.mode === "remove" ? "Filter installed…" : "Search or browse Flathub…"
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
    text: root.busy ? "Searching…" : root.status
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
      Layout.preferredHeight: row.implicitHeight + 20
      radius: Theme.radiusMd
      color: Theme.bgPanel
      border.width: 1
      border.color: modelData.selected ? Theme.accent : Theme.border
      visible: !root.confirming
      opacity: root.applying ? 0.7 : 1
      RowLayout {
        id: row
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.spaceMd
        spacing: Theme.spaceMd
        Rectangle {
          Layout.preferredWidth: 20
          Layout.preferredHeight: 20
          radius: 4
          color: modelData.selected ? Theme.accent : "transparent"
          border.width: 1
          border.color: modelData.selected ? Theme.accent : Theme.border
          Text {
            anchors.centerIn: parent
            text: modelData.selected ? "✓" : ""
            color: "#ffffff"
            font.bold: true
            visible: modelData.selected
          }
        }
        ColumnLayout {
          Layout.fillWidth: true
          spacing: 2
          Text {
            Layout.fillWidth: true
            text: modelData.name
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            font.bold: true
            elide: Text.ElideRight
          }
          Text {
            Layout.fillWidth: true
            text: modelData.ref + (modelData.version ? (" · " + modelData.version) : "")
            color: Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: 11
            elide: Text.ElideMiddle
          }
          Text {
            Layout.fillWidth: true
            text: modelData.desc || ""
            color: Theme.textMute
            font.family: Theme.fontFamily
            font.pixelSize: 11
            wrapMode: Text.WordWrap
            visible: !!(modelData.desc && modelData.desc.length && modelData.desc !== modelData.ref)
          }
        }
      }
      MouseArea {
        anchors.fill: parent
        enabled: !root.applying
        cursorShape: Qt.PointingHandCursor
        onClicked: root.setSelected(modelData.ref, !modelData.selected)
      }
    }
  }

  Rectangle {
    Layout.fillWidth: true
    Layout.maximumWidth: 520
    Layout.preferredHeight: 44
    radius: Theme.radiusMd
    color: root.mode === "remove" ? Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.14) : Theme.accentSoft
    border.width: 1
    border.color: root.mode === "remove" ? Theme.danger : Theme.accent
    visible: root.flatpakOk && !root.confirming
    opacity: (root.applying || root.selectedCount === 0) ? 0.5 : 1
    Text {
      anchors.centerIn: parent
      text: root.applying ? "Applying…"
          : (root.selectedCount === 0
              ? (root.mode === "remove" ? "Select Flatpaks to remove" : "Select Flatpaks to install")
              : ((root.mode === "remove" ? "Remove " : "Install ") + root.selectedCount + "…"))
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
    text: "Fact: flatpak search/list · Apply: flatpak --user flathub (multi). Snap is Out."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 11
  }

  Timer {
    id: debounce
    interval: 280
    onTriggered: root.search()
  }

  Connections {
    target: Packages
    function onPackageOpFinished(ok, message) {
      if (!root.active)
        return
      root.status = message
      root.refreshMeta()
      Packages.refreshHelpers()
      if (ok)
        Qt.callLater(() => root.search())
    }
  }

  Process {
    id: remotesProc
    command: ["flatpak", "remotes", "--user", "--columns=name"]
    stdout: StdioCollector {
      onStreamFinished: {
        root.remotes = text.trim().split("\n").map(s => s.trim()).filter(s => s.length)
        let hub = false
        for (let i = 0; i < root.remotes.length; i++) {
          if (String(root.remotes[i]).toLowerCase() === "flathub") {
            hub = true
            break
          }
        }
        Packages.noteFlathubConfigured(hub)
        if (root.active && root.flatpakOk && !hub)
          root.ensureFlathubPrompt()
      }
    }
  }

  Process {
    id: installedProc
    command: ["flatpak", "list", "--user", "--app", "--columns=application:f,name"]
    stdout: StdioCollector {
      onStreamFinished: {
        const out = []
        text.trim().split("\n").forEach(line => {
          if (!line.length)
            return
          const parts = line.split(/\t+|\s{2,}/)
          const ref = (parts[0] || "").trim()
          if (!ref.length || ref === "Application")
            return
          out.push({
            ref: ref,
            name: (parts[1] || ref).trim()
          })
        })
        root.installed = out
        if (root.mode === "remove" && root.active)
          root.search()
      }
    }
  }

  Process {
    id: browseProc
    command: [
      "bash",
      "-lc",
      "flatpak remote-ls flathub --app --columns=application:f,name 2>/dev/null | head -n " + String(root.resultCap)
    ]
    stdout: StdioCollector {
      onStreamFinished: {
        if (root.mode !== "install" || root.query.trim().length >= 2)
          return
        const out = []
        text.trim().split("\n").forEach(line => {
          if (!line.length)
            return
          const parts = line.split(/\t+|\s{2,}/)
          const ref = (parts[0] || "").trim()
          if (!ref.length || ref === "Application")
            return
          if (root.isInstalled(ref))
            return
          out.push({
            ref: ref,
            name: (parts[1] || ref).trim(),
            version: "",
            desc: ref,
            installed: false,
            repo: "flathub",
            selected: false
          })
        })
        root.results = out.slice(0, root.resultCap)
        root.busy = false
        root.status = root.results.length
            ? "Browsing Flathub — type ≥2 characters to search."
            : "No Flathub browse results."
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
        const out = []
        text.trim().split("\n").forEach(line => {
          if (!line.length)
            return
          const parts = line.split(/\t/)
          if (parts.length < 2)
            return
          const ref = parts[0].trim()
          if (!ref.length || ref === "Application")
            return
          out.push({
            ref: ref,
            name: (parts[1] || ref).trim(),
            version: (parts[2] || "").trim(),
            desc: (parts[3] || "").trim(),
            installed: root.isInstalled(ref),
            repo: "flathub",
            selected: false
          })
        })
        root.results = Packages.sortSearchResults(root.query, out).slice(0, root.resultCap)
        root.busy = false
        root.status = root.results.length ? "" : "No Flatpaks matched."
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
      Packages.refreshHelpers()
      if (Packages.flatpakAvailable) {
        refreshMeta()
        status = mode === "remove" ? "" : (hasFlathub
            ? "Loading Flathub…"
            : "Checking Flathub remote…")
        if (mode === "remove" || hasFlathub)
          search()
        Qt.callLater(() => searchInput.forceActiveFocus())
      } else {
        status = "Install flatpak to use Flathub from Settings."
      }
    } else {
      debounce.stop()
      clearPending()
    }
  }
}
