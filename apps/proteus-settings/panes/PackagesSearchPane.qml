import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../shared"
import "../kit"
import ".." // root module — SettingsNav singleton

// Packages → Repos: Install | Installed with sticky action bar, rich rows, live ops.
ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: 12
  focus: active

  property bool active: false
  property string mode: "installed"
  property var results: []
  property string status: ""
  property bool busy: false
  property string installQuery: ""
  property string installedQuery: ""
  property int searchGen: 0
  property bool syncingQuery: false
  property string pendingDetail: ""
  property string pendingAction: ""
  property var pendingNames: []
  property var installedSet: ({})
  property int resultCap: 60
  property int listMaxHeight: 360
  readonly property string leafKey: "packages-search"
  readonly property bool confirming: pendingAction.length > 0
  readonly property bool applying: Packages.packageOpBusy
  readonly property bool onInstalled: mode === "installed"
  readonly property string activeQuery: onInstalled ? installedQuery : installQuery
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

  function persistUi() {
    Packages.saveLeafUi(leafKey, mode, installQuery, installedQuery)
  }

  function restoreUi() {
    const st = Packages.loadLeafUi(leafKey)
    if (!st)
      return
    if (st.mode === "install" || st.mode === "installed")
      mode = st.mode
    installQuery = st.installQuery || (st.mode === "install" ? (st.query || "") : "")
    installedQuery = st.installedQuery || (st.mode === "installed" ? (st.query || "") : "")
  }

  function abortInstallLoads() {
    debounce.stop()
    browseProc.requestGen = -1
    searchProc.requestGen = -1
    if (browseProc.running)
      browseProc.running = false
    if (searchProc.running)
      searchProc.running = false
  }

  function abortInstalledLoads() {
    removeListProc.requestGen = -1
    if (removeListProc.running)
      removeListProc.running = false
  }

  function beginSearch() {
    searchGen += 1
    results = []
    return searchGen
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
    for (let i = 0; i < results.length; i++)
      next.push(Object.assign({}, results[i], { selected: !!on }))
    results = next
  }

  function startPopularBrowse(gen) {
    if (gen !== searchGen || mode !== "install")
      return
    const seeds = Packages.popularRepoPackages.join(" ")
    browseProc.requestGen = gen
    browseProc.command = [
      "bash",
      "-lc",
      "for p in " + seeds + "; do "
          + "pacman -Qq \"$p\" >/dev/null 2>&1 && continue; "
          + "if command -v expac >/dev/null 2>&1; then "
          + "expac -S '%n\\t%v\\t%d\\t%r' \"$p\" 2>/dev/null | head -1; "
          + "else "
          + "info=$(pacman -Si \"$p\" 2>/dev/null) || continue; "
          + "ver=$(printf '%s\\n' \"$info\" | awk -F': ' '/^Version/{print $2; exit}'); "
          + "desc=$(printf '%s\\n' \"$info\" | awk -F': ' '/^Description/{print $2; exit}'); "
          + "repo=$(printf '%s\\n' \"$info\" | awk -F': ' '/^Repository/{print $2; exit}'); "
          + "printf '%s\\t%s\\t%s\\t%s\\n' \"$p\" \"$ver\" \"$desc\" \"$repo\"; "
          + "fi; done"
    ]
    browseProc.running = false
    browseProc.running = true
  }

  function search() {
    clearPending()
    persistUi()
    const gen = beginSearch()
    if (onInstalled) {
      abortInstallLoads()
      busy = true
      status = "Loading installed packages…"
      removeListProc.requestGen = gen
      removeListProc.running = false
      removeListProc.running = true
      return
    }
    abortInstalledLoads()
    const q = installQuery.trim()
    if (q.length < 2) {
      busy = true
      status = "Loading popular packages…"
      startPopularBrowse(gen)
      return
    }
    busy = true
    status = "Searching…"
    searchProc.requestGen = gen
    searchProc.command = ["pacman", "-Ss", "--", q]
    searchProc.running = false
    searchProc.running = true
  }

  function scheduleSearch() {
    if (syncingQuery)
      return
    debounce.restart()
  }

  function syncSearchField() {
    syncingQuery = true
    searchInput.text = activeQuery
    syncingQuery = false
  }

  property int appliedSeedEpoch: 0

  function applySearchSeed() {
    let q = ""
    if (SettingsNav.hasPendingInstall(leafKey))
      q = SettingsNav.takePendingInstall(leafKey)
    else if (Packages.hasSearchSeedFor(leafKey))
      q = Packages.takeSearchSeed()
    if (!q.length)
      return false
    // Query before mode so activeQuery binding never flashes empty Install.
    installQuery = q
    mode = "install"
    appliedSeedEpoch = Math.max(SettingsNav.pendingInstallEpoch, Packages.searchSeedEpoch)
    return true
  }

  function ingestSeed() {
    if (!applySearchSeed())
      return false
    syncSearchField()
    search()
    return true
  }

  function activateLeaf() {
    if (!applySearchSeed()) {
      // ingestSeed may have already applied this epoch (PackagesPane push).
      const epoch = Math.max(SettingsNav.pendingInstallEpoch, Packages.searchSeedEpoch)
      if (!(appliedSeedEpoch > 0 && appliedSeedEpoch === epoch))
        restoreUi()
    }
    syncSearchField()
    refreshInstalled()
    search()
    forceActiveFocus()
    Qt.callLater(() => searchInput.forceActiveFocus())
  }

  function proposeBatch() {
    const names = selectedNames
    if (!names.length)
      return
    pendingNames = names.slice()
    pendingAction = onInstalled ? "remove" : "install"
    const preview = names.length <= 8 ? names.join(", ") : (names.slice(0, 8).join(", ") + "…")
    pendingDetail = onInstalled
        ? ("Remove " + names.length + " package" + (names.length === 1 ? "" : "s")
            + " via proteus-pkg remove → pacman -Rns: " + preview)
        : ("Install " + names.length + " package" + (names.length === 1 ? "" : "s")
            + " via proteus-pkg install: " + preview)
  }

  function proposeOne(name) {
    if (!name || !String(name).length)
      return
    pendingNames = [String(name)]
    pendingAction = onInstalled ? "remove" : "install"
    pendingDetail = onInstalled
        ? ("Remove via proteus-pkg remove → pacman -Rns: " + name)
        : ("Install via proteus-pkg install: " + name)
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
        setSelected(first.name, !first.selected)
      event.accepted = true
    } else if (event.key === Qt.Key_Escape && confirming) {
      clearPending()
      event.accepted = true
    }
  }

  Text {
    Layout.fillWidth: true
    text: "Official repos — Install or Installed. / search · Space toggle · Enter confirm."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 12
    wrapMode: Text.WordWrap
  }

  SettingsSegmented {
    Layout.maximumWidth: 520
    visible: !root.confirming
    options: [
      { id: "install", label: "Install" },
      { id: "installed", label: "Installed" }
    ]
    selected: root.mode
    onActivated: id => {
      if (root.mode === id)
        return
      root.abortInstallLoads()
      root.abortInstalledLoads()
      root.mode = id
      root.results = []
      root.busy = false
      root.status = ""
      root.syncSearchField()
      root.search()
      Qt.callLater(() => searchInput.forceActiveFocus())
    }
  }

  PackagesConfirm {
    open: root.confirming
    title: root.pendingAction === "remove" ? "Remove packages?" : "Install packages?"
    detail: root.pendingDetail
    onCancelled: root.clearPending()
    onConfirmed: root.runPending()
  }

  PackagesOpProgress {}

  RowLayout {
    Layout.fillWidth: true
    Layout.maximumWidth: 520
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
        text: root.activeQuery
        onTextChanged: {
          if (root.syncingQuery)
            return
          if (root.onInstalled)
            root.installedQuery = text
          else
            root.installQuery = text
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
              && (root.busy || root.status.length > 0)
  }

  Flickable {
    id: listFlick
    Layout.fillWidth: true
    Layout.maximumWidth: 520
    Layout.preferredHeight: Math.min(root.listMaxHeight, Math.max(0, listCol.implicitHeight))
    contentWidth: width
    contentHeight: listCol.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    visible: !root.confirming
    interactive: contentHeight > height

    ColumnLayout {
      id: listCol
      width: listFlick.width
      spacing: 8

      Repeater {
        model: root.results
        PackagesPickerRow {
          required property var modelData
          Layout.fillWidth: true
          title: modelData.repo ? (modelData.repo + "/" + modelData.name) : modelData.name
          subtitle: modelData.desc || ""
          version: modelData.version || ""
          badge: (!root.onInstalled && modelData.installed) ? "Installed" : ""
          selected: !!modelData.selected
          rowEnabled: root.onInstalled || !modelData.installed
          applying: root.applying
          showAction: root.onInstalled || !modelData.installed
          actionLabel: root.onInstalled ? "Remove" : "Install"
          actionDanger: root.onInstalled
          onToggled: root.setSelected(modelData.name, !modelData.selected)
          onActionClicked: root.proposeOne(modelData.name)
        }
      }
    }
  }

  PackagesActionBar {
    visible: !root.confirming
    selectedCount: root.selectedCount
    totalCount: root.results.length
    applying: root.applying
    danger: root.onInstalled
    idleLabel: root.onInstalled ? "Select packages to remove" : "Select packages to install"
    activePrefix: root.onInstalled ? "Remove" : "Install"
    onSelectAllClicked: root.setAllSelected(root.selectedCount !== root.results.length)
    onActionClicked: root.proposeBatch()
  }

  Text {
    Layout.fillWidth: true
    text: "Fact: pacman -Ss / -Qe · Apply: pkexec proteus-pkg install|remove (multi)"
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
        text.trim().split("\n").forEach(n => {
          n = n.trim()
          if (n.length)
            map[n] = true
        })
        root.installedSet = map
      }
    }
  }

  Process {
    id: removeListProc
    property int requestGen: -1
    command: [
      "bash",
      "-lc",
      "if command -v expac >/dev/null 2>&1; then "
          + "expac -Q '%n\\t%v\\t%d' $(pacman -Qqe | head -n " + String(root.resultCap) + "); "
          + "else pacman -Qe | head -n " + String(root.resultCap) + " | awk '{print $1\"\\t\"$2\"\\t\"}'; fi"
    ]
    stdout: StdioCollector {
      onStreamFinished: {
        const gen = removeListProc.requestGen
        if (gen < 0 || gen !== root.searchGen || root.mode !== "installed")
          return
        const q = root.installedQuery.trim().toLowerCase()
        const out = []
        text.trim().split("\n").forEach(line => {
          if (!line.length)
            return
          const parts = line.split("\t")
          const name = (parts[0] || "").trim()
          if (!name.length)
            return
          const version = (parts[1] || "").trim()
          const desc = (parts[2] || "").trim()
          const hay = (name + " " + desc).toLowerCase()
          if (q.length && hay.indexOf(q) < 0)
            return
          out.push({
            name: name,
            repo: "",
            version: version,
            desc: desc,
            installed: true,
            selected: false
          })
        })
        if (gen !== root.searchGen || root.mode !== "installed")
          return
        const ranked = Packages.sortSearchResults(root.installedQuery, out)
        root.results = ranked.slice(0, root.resultCap)
        root.busy = false
        root.status = ranked.length
            ? ""
            : (q.length
                ? ("No installed packages matched “" + root.installedQuery.trim() + "”.")
                : "No explicitly installed packages. Switch to Install to browse popular apps.")
      }
    }
  }

  Process {
    id: browseProc
    property int requestGen: -1
    command: ["true"]
    stdout: StdioCollector {
      onStreamFinished: {
        const gen = browseProc.requestGen
        if (gen < 0 || gen !== root.searchGen || root.mode !== "install")
          return
        if (root.installQuery.trim().length >= 2)
          return
        const out = []
        text.trim().split("\n").forEach(line => {
          if (!line.length)
            return
          const parts = line.split("\t")
          const name = (parts[0] || "").trim()
          if (!name.length || root.isInstalled(name))
            return
          out.push({
            name: name,
            repo: (parts[3] || "").trim(),
            version: (parts[1] || "").trim(),
            desc: (parts[2] || "Popular").trim(),
            installed: false,
            selected: false
          })
        })
        if (gen !== root.searchGen || root.mode !== "install")
          return
        root.results = out.slice(0, root.resultCap)
        root.busy = false
        root.status = out.length
            ? "Popular packages — type ≥2 characters to search all repos."
            : "No popular packages available to install."
      }
    }
    onExited: (exitCode, exitStatus) => {
      const gen = browseProc.requestGen
      if (gen < 0 || gen !== root.searchGen || root.mode !== "install")
        return
      if (root.busy && root.installQuery.trim().length < 2 && root.results.length === 0 && exitCode !== 0)
        root.busy = false
    }
  }

  Process {
    id: searchProc
    property int requestGen: -1
    command: ["true"]
    stdout: StdioCollector {
      onStreamFinished: {
        const gen = searchProc.requestGen
        if (gen < 0 || gen !== root.searchGen || root.mode !== "install")
          return
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
        if (gen !== root.searchGen || root.mode !== "install")
          return
        const ranked = Packages.sortSearchResults(root.installQuery, out)
        root.results = ranked.slice(0, root.resultCap)
        root.busy = false
        root.status = ranked.length ? "" : "No packages matched."
      }
    }
    stderr: StdioCollector {
      onStreamFinished: {
        const gen = searchProc.requestGen
        if (gen < 0 || gen !== root.searchGen || root.mode !== "install")
          return
        if (text.trim().length && root.results.length === 0) {
          root.busy = false
          root.status = text.trim().split("\n")[0]
        }
      }
    }
    onExited: (exitCode, exitStatus) => {
      const gen = searchProc.requestGen
      if (gen < 0 || gen !== root.searchGen || root.mode !== "install")
        return
      if (root.busy && root.results.length === 0 && exitCode !== 0)
        root.busy = false
    }
  }

  Connections {
    target: Packages
    function onSearchSeedEpochChanged() {
      if (root.active)
        root.ingestSeed()
    }
  }

  Connections {
    target: SettingsNav
    function onPendingInstallEpochChanged() {
      if (root.active)
        root.ingestSeed()
    }
  }

  onActiveChanged: {
    if (active) {
      activateLeaf()
    } else {
      persistUi()
      abortInstallLoads()
      abortInstalledLoads()
      results = []
      busy = false
      clearPending()
    }
  }

  onModeChanged: {
    if (active)
      persistUi()
  }
}
