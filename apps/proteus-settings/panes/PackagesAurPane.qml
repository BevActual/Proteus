import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../shared"
import "../kit"

// Packages → AUR: Install | Installed with sticky action bar, rich rows, live ops.
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
  property string query: ""
  property string pendingDetail: ""
  property string pendingAction: ""
  property var pendingNames: []
  property var installedSet: ({})
  property int resultCap: 60
  property int listMaxHeight: 360
  readonly property string leafKey: "packages-aur"
  readonly property bool confirming: pendingAction.length > 0
  readonly property bool applying: Packages.packageOpBusy
  readonly property string helper: Packages.aurHelper
  readonly property bool helperOk: helper.length > 0
  readonly property bool onInstalled: mode === "installed"
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

  function startPopularBrowse() {
    const seeds = Packages.popularAurHints.join(" ")
    const h = helper
    browseProc.command = [
      "bash",
      "-lc",
      "for p in " + seeds + "; do "
          + "pacman -Qq \"$p\" >/dev/null 2>&1 && continue; "
          + "if info=$(" + h + " -Si \"$p\" 2>/dev/null); then "
          + "ver=$(printf '%s\\n' \"$info\" | awk -F': ' '/^Version/{print $2; exit}'); "
          + "desc=$(printf '%s\\n' \"$info\" | awk -F': ' '/^Description/{print $2; exit}'); "
          + "printf '%s\\t%s\\t%s\\taur\\n' \"$p\" \"$ver\" \"$desc\"; "
          + "else "
          + "line=$(" + h + " -Ssa -- \"$p\" 2>/dev/null | head -1); "
          + "[ -n \"$line\" ] || continue; "
          + "name=$(printf '%s\\n' \"$line\" | awk '{print $1}' | awk -F/ '{print $NF}'); "
          + "ver=$(printf '%s\\n' \"$line\" | awk '{print $2}'); "
          + "printf '%s\\t%s\\t%s\\taur\\n' \"${name:-$p}\" \"$ver\" \"Popular AUR\"; "
          + "fi; done"
    ]
    browseProc.running = false
    browseProc.running = true
  }

  function search() {
    clearPending()
    persistUi()
    if (!helperOk) {
      status = "Install yay or paru to use the AUR from Settings."
      results = []
      busy = false
      return
    }
    if (onInstalled) {
      busy = true
      status = "Loading foreign packages…"
      removeListProc.running = false
      removeListProc.running = true
      return
    }
    const q = query.trim()
    if (q.length < 2) {
      busy = true
      status = "Loading popular AUR packages…"
      startPopularBrowse()
      return
    }
    busy = true
    status = "Searching AUR…"
    searchProc.triedFallback = false
    searchProc.command = [helper, "-Ssa", "--", q]
    searchProc.running = false
    searchProc.running = true
  }

  function scheduleSearch() {
    if (!helperOk)
      return
    debounce.restart()
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
            + " via " + helper + " -Rns: " + preview)
        : ("Install " + names.length + " package" + (names.length === 1 ? "" : "s")
            + " via " + helper + " -S: " + preview)
  }

  function proposeOne(name) {
    if (!name || !String(name).length)
      return
    pendingNames = [String(name)]
    pendingAction = onInstalled ? "remove" : "install"
    pendingDetail = onInstalled
        ? ("Remove via " + helper + " -Rns: " + name)
        : ("Install via " + helper + " -S: " + name)
  }

  function runPending() {
    const act = pendingAction
    const names = pendingNames.slice()
    clearPending()
    if (act === "remove")
      Packages.aurRemoveMany(names)
    else
      Packages.aurInstallMany(names)
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
    text: helperOk
        ? ("AUR via " + helper + " — Install or Installed. / search · Space toggle · Enter confirm.")
        : "Install yay or paru to use the AUR from Settings."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 12
    wrapMode: Text.WordWrap
  }

  SettingsSegmented {
    Layout.maximumWidth: 520
    visible: root.helperOk && !root.confirming
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

  PackagesConfirm {
    open: root.confirming
    title: root.pendingAction === "remove" ? "Remove AUR packages?" : "Install AUR packages?"
    detail: root.pendingDetail
    footnote: "Runs " + (root.helper || "yay/paru") + " as your user."
    onCancelled: root.clearPending()
    onConfirmed: root.runPending()
  }

  PackagesOpProgress {}

  RowLayout {
    Layout.fillWidth: true
    Layout.maximumWidth: 520
    visible: root.helperOk && !root.confirming
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
          text: root.onInstalled ? "Filter foreign packages…" : "Search or browse popular AUR…"
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
    visible: root.helperOk && root.results.length === 0 && !root.confirming && !root.applying
  }

  ListView {
    id: list
    Layout.fillWidth: true
    Layout.maximumWidth: 520
    Layout.preferredHeight: Math.min(root.listMaxHeight, Math.max(0, contentHeight))
    clip: true
    spacing: 8
    visible: root.helperOk && !root.confirming
    model: root.results
    boundsBehavior: Flickable.StopAtBounds
    delegate: PackagesPickerRow {
      required property var modelData
      width: list.width
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

  PackagesActionBar {
    visible: root.helperOk && !root.confirming
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
    text: "Fact: yay/paru -Ssa / pacman -Qqm · Apply: user-session AUR helper (multi)"
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
    command: [
      "bash",
      "-lc",
      "if command -v expac >/dev/null 2>&1; then "
          + "pkgs=$(pacman -Qqm | head -n " + String(root.resultCap) + "); "
          + "[ -n \"$pkgs\" ] && expac -Q '%n\\t%v\\t%d' $pkgs; "
          + "else pacman -Qm | head -n " + String(root.resultCap) + " | awk '{print $1\"\\t\"$2\"\\t\"}'; fi"
    ]
    stdout: StdioCollector {
      onStreamFinished: {
        const q = root.query.trim().toLowerCase()
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
            repo: "aur",
            version: version,
            desc: desc,
            installed: true,
            selected: false
          })
        })
        const ranked = Packages.sortSearchResults(root.query, out)
        root.results = ranked.slice(0, root.resultCap)
        root.busy = false
        root.status = ranked.length
            ? ""
            : (q.length ? "No foreign packages matched." : "No foreign (AUR) packages installed.")
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
          const name = (parts[0] || "").trim()
          if (!name.length || root.isInstalled(name))
            return
          out.push({
            name: name,
            repo: (parts[3] || "aur").trim() || "aur",
            version: (parts[1] || "").trim(),
            desc: (parts[2] || "Popular AUR").trim(),
            installed: false,
            selected: false
          })
        })
        root.results = out.slice(0, root.resultCap)
        root.busy = false
        root.status = out.length
            ? "Popular AUR — type ≥2 characters to search."
            : "No popular AUR packages available to install."
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
    property bool triedFallback: false
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
        searchProc.triedFallback = false
        root.status = ranked.length ? "" : "No packages matched."
      }
    }
    stderr: StdioCollector {
      onStreamFinished: {
        if (text.trim().length && root.busy && root.results.length === 0
            && !searchProc.triedFallback && root.helperOk) {
          searchProc.triedFallback = true
          searchProc.command = [root.helper, "-Ss", "--", root.query.trim()]
          searchProc.running = false
          searchProc.running = true
          return
        }
        if (text.trim().length && root.results.length === 0) {
          root.busy = false
          root.status = text.trim().split("\n")[0]
        }
      }
    }
    onExited: (exitCode, exitStatus) => {
      if (root.busy && root.results.length === 0 && exitCode !== 0
          && !searchProc.triedFallback && root.helperOk) {
        searchProc.triedFallback = true
        searchProc.command = [root.helper, "-Ss", "--", root.query.trim()]
        searchProc.running = false
        searchProc.running = true
        return
      }
      if (root.busy && root.results.length === 0 && exitCode !== 0)
        root.busy = false
    }
  }

  onActiveChanged: {
    if (active) {
      restoreUi()
      Packages.refreshHelpers()
      refreshInstalled()
      if (Packages.aurHelper.length)
        search()
      else
        status = "Install yay or paru to use the AUR from Settings."
      forceActiveFocus()
      Qt.callLater(() => {
        if (root.helperOk)
          searchInput.forceActiveFocus()
      })
    } else {
      persistUi()
      debounce.stop()
      clearPending()
    }
  }

  onModeChanged: {
    if (active && helperOk) {
      persistUi()
      search()
    }
  }
}
