import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../shared"
import "../kit"

// Packages → Flathub: Install | Installed with sticky action bar, rich rows, live ops.
ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: 12
  focus: active

  property bool active: false
  property string mode: "installed"
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
  property int listMaxHeight: 360
  readonly property string leafKey: "packages-flatpak"
  readonly property bool confirming: pendingAction.length > 0
  readonly property bool applying: Packages.packageOpBusy
  readonly property bool flatpakOk: Packages.flatpakAvailable
  readonly property bool onInstalled: mode === "installed"
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

  function persistUi() {
    Packages.saveLeafUi(leafKey, mode, query)
  }

  function restoreUi() {
    const st = Packages.loadLeafUi(leafKey)
    if (!st)
      return
    if (st.mode === "install" || st.mode === "installed")
      mode = st.mode
    query = st.query || ""
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
    for (let i = 0; i < results.length; i++)
      next.push(Object.assign({}, results[i], { selected: !!on }))
    results = next
  }

  function startPopularBrowse() {
    const seeds = Packages.popularFlatpakApps.join(" ")
    browseProc.command = [
      "bash",
      "-lc",
      "for r in " + seeds + "; do "
          + "if info=$(flatpak remote-info flathub \"$r\" 2>/dev/null); then "
          + "name=$(printf '%s\\n' \"$info\" | awk -F': ' '/^Name|Title/{print $2; exit}'); "
          + "ver=$(printf '%s\\n' \"$info\" | awk -F': ' '/^Version/{print $2; exit}'); "
          + "desc=$(printf '%s\\n' \"$info\" | awk -F': ' '/^Comment|Description/{print $2; exit}'); "
          + "printf '%s\\t%s\\t%s\\t%s\\n' \"$r\" \"${name:-$r}\" \"$ver\" \"${desc:-Popular}\"; "
          + "else "
          + "printf '%s\\t%s\\t\\tPopular\\n' \"$r\" \"$r\"; "
          + "fi; done"
    ]
    browseProc.running = false
    browseProc.running = true
  }

  function search() {
    clearPending()
    persistUi()
    if (!flatpakOk) {
      status = "Install flatpak to use Flathub from Settings."
      results = []
      busy = false
      return
    }
    if (onInstalled) {
      const q = query.trim().toLowerCase()
      const out = []
      for (let i = 0; i < installed.length; i++) {
        const it = installed[i]
        const hay = (it.name + " " + it.ref + " " + (it.desc || "")).toLowerCase()
        if (q.length && hay.indexOf(q) < 0)
          continue
        out.push({
          ref: it.ref,
          name: it.name,
          version: it.version || "",
          desc: it.desc || it.ref,
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
      status = "Loading popular Flatpaks…"
      startPopularBrowse()
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
    pendingAction = onInstalled ? "remove" : "install"
    const preview = refs.length <= 6 ? refs.join(", ") : (refs.slice(0, 6).join(", ") + "…")
    pendingDetail = onInstalled
        ? ("Uninstall " + refs.length + " Flatpak(s) (--user): " + preview)
        : ("Install from Flathub (--user): " + preview)
  }

  function proposeOne(ref) {
    if (!ref || !String(ref).length)
      return
    pendingRefs = [String(ref)]
    pendingAction = onInstalled ? "remove" : "install"
    pendingDetail = onInstalled
        ? ("Uninstall Flatpak (--user): " + ref)
        : ("Install from Flathub (--user): " + ref)
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

  Keys.onPressed: event => {
    if (event.key === Qt.Key_Slash && !searchInput.activeFocus) {
      searchInput.forceActiveFocus()
      event.accepted = true
    } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !searchInput.activeFocus) {
      if (confirming) {
        runPending()
        event.accepted = true
      } else if (selectedCount > 0 && !applying) {
        proposeBatch()
        event.accepted = true
      }
    } else if (event.key === Qt.Key_Space && results.length && !searchInput.activeFocus) {
      const first = results[0]
      if (first && (onInstalled || !first.installed))
        setSelected(first.ref, !first.selected)
      event.accepted = true
    } else if (event.key === Qt.Key_Escape && confirming) {
      clearPending()
      event.accepted = true
    }
  }

  Text {
    Layout.fillWidth: true
    text: !flatpakOk
        ? "Flatpak is not installed. Install the flatpak package, then reopen this page."
        : (hasFlathub
            ? "Flathub (--user) — Install or Installed. / search · Space toggle · Enter confirm."
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
      { id: "install", label: "Install" },
      { id: "installed", label: "Installed" }
    ]
    selected: root.mode
    onActivated: id => {
      root.mode = id
      root.results = []
      root.search()
      Qt.callLater(() => searchInput.forceActiveFocus())
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

  PackagesOpProgress {}

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
          text: root.onInstalled ? "Filter installed…" : "Search or browse popular…"
          color: Theme.textMute
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSize
          visible: !searchInput.text.length && !searchInput.activeFocus
        }
      }
    }
  }

  Text {
    Layout.fillWidth: true
    text: root.busy ? "Loading…" : root.status
    color: Theme.textDim
    font.family: Theme.fontFamily
    font.pixelSize: 12
    wrapMode: Text.WordWrap
    visible: root.results.length === 0 && !root.confirming && !root.applying
  }

  ListView {
    id: list
    Layout.fillWidth: true
    Layout.maximumWidth: 520
    Layout.preferredHeight: Math.min(root.listMaxHeight, Math.max(0, contentHeight))
    clip: true
    spacing: 8
    visible: !root.confirming
    model: root.results
    boundsBehavior: Flickable.StopAtBounds
    delegate: PackagesPickerRow {
      required property var modelData
      width: list.width
      title: modelData.name || modelData.ref
      subtitle: modelData.desc || modelData.ref || ""
      version: modelData.version || ""
      badge: (!root.onInstalled && modelData.installed) ? "Installed" : ""
      selected: !!modelData.selected
      rowEnabled: root.onInstalled || !modelData.installed
      applying: root.applying
      showAction: root.onInstalled || !modelData.installed
      actionLabel: root.onInstalled ? "Remove" : "Install"
      actionDanger: root.onInstalled
      onToggled: root.setSelected(modelData.ref, !modelData.selected)
      onActionClicked: root.proposeOne(modelData.ref)
    }
  }

  PackagesActionBar {
    visible: root.flatpakOk && !root.confirming
    selectedCount: root.selectedCount
    totalCount: root.results.length
    applying: root.applying
    danger: root.onInstalled
    idleLabel: root.onInstalled ? "Select apps to remove" : "Select apps to install"
    activePrefix: root.onInstalled ? "Remove" : "Install"
    onSelectAllClicked: root.setAllSelected(root.selectedCount !== root.results.length)
    onActionClicked: root.proposeBatch()
  }

  Text {
    Layout.fillWidth: true
    text: "Fact: flatpak search/list · Apply: flatpak --user flathub (multi). Snap is Out."
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
        if (root.active && root.flatpakOk && !hub && !root.onInstalled)
          root.ensureFlathubPrompt()
        else if (root.active && !root.onInstalled && hub)
          root.search()
      }
    }
  }

  Process {
    id: installedProc
    command: ["flatpak", "list", "--user", "--app", "--columns=application:f,name,version,description"]
    stdout: StdioCollector {
      onStreamFinished: {
        const out = []
        text.trim().split("\n").forEach(line => {
          if (!line.length)
            return
          const parts = line.split(/\t/)
          const ref = (parts[0] || "").trim()
          if (!ref.length || ref === "Application")
            return
          out.push({
            ref: ref,
            name: (parts[1] || ref).trim(),
            version: (parts[2] || "").trim(),
            desc: (parts[3] || "").trim()
          })
        })
        root.installed = out
        if (root.active && root.onInstalled)
          root.search()
      }
    }
  }

  Process {
    id: browseProc
    command: ["true"]
    stdout: StdioCollector {
      onStreamFinished: {
        if (root.onInstalled || root.query.trim().length >= 2)
          return
        const out = []
        text.trim().split("\n").forEach(line => {
          if (!line.length)
            return
          const parts = line.split("\t")
          const ref = (parts[0] || "").trim()
          if (!ref.length || root.isInstalled(ref))
            return
          out.push({
            ref: ref,
            name: (parts[1] || ref).trim() || ref,
            version: (parts[2] || "").trim(),
            desc: (parts[3] || ref).trim(),
            installed: false,
            repo: "flathub",
            selected: false
          })
        })
        root.results = out.slice(0, root.resultCap)
        root.busy = false
        root.status = out.length
            ? "Popular Flatpaks — type ≥2 characters to search."
            : "No popular Flatpaks available to install."
      }
    }
    onExited: (exitCode, exitStatus) => {
      if (root.busy && !root.onInstalled && root.query.trim().length < 2 && root.results.length === 0 && exitCode !== 0)
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
      restoreUi()
      Packages.refreshHelpers()
      if (Packages.flatpakAvailable) {
        refreshMeta()
        if (onInstalled)
          search()
        forceActiveFocus()
        Qt.callLater(() => searchInput.forceActiveFocus())
      } else {
        status = "Install flatpak to use Flathub from Settings."
      }
    } else {
      persistUi()
      debounce.stop()
      clearPending()
    }
  }

  onModeChanged: {
    if (active && flatpakOk) {
      persistUi()
      search()
    }
  }
}
