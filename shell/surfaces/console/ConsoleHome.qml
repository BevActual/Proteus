import Quickshell
import QtQuick
import QtQuick.Layouts
import "../../shared"
import "../desktop"

// Console navigation — media-center list IA (Games · Media · Apps · Search · Settings).
Item {
  id: root
  anchors.fill: parent
  focus: true

  property real navOpacity: 1

  // focusZone: chrome | searchField | filterField | list | detail
  property string focusZone: "list"
  property int barSlot: 0
  property int listIndex: 0
  property string tab: "games"
  property string searchQuery: ""
  property string filterQuery: ""
  property string sheetReturnZone: "list"

  readonly property var topDestinations: ["games", "media", "apps", "search", "settings"]

  ConsoleLibrary { id: library }
  ConsoleAppsModel {
    id: appsModel
    query: root.searchQuery
    filterText: root.filterQuery
    section: root.tab === "media" ? "media" : (root.tab === "apps" ? "apps" : "games")
    hasLocalPlayer: library.hasMpv
    installedTitles: library.installedGames
    recentItems: library.recentItems
  }

  readonly property var listItems: {
    if (tab === "apps")
      return appsModel.appsList
    if (tab === "games")
      return appsModel.gamesList
    if (tab === "media")
      return appsModel.mediaList
    if (tab === "settings")
      return appsModel.settingsList
    return appsModel.filtered
  }

  readonly property var featured: {
    if (!listItems.length)
      return null
    let i = Math.max(0, Math.min(listIndex, listItems.length - 1))
    let it = listItems[i]
    if (it && (it.kind === "section" || it.isSection || it.selectable === false))
      return null
    return it
  }

  readonly property string emptyListCopy: {
    switch (tab) {
    case "apps":
      return "No apps yet"
    case "games":
      return "No games yet"
    case "media":
      return "No streaming apps yet"
    case "settings":
      return "No Settings pages available"
    case "search":
      return searchQuery.length || filterQuery.length
          ? "No matches"
          : "Shortcuts"
    default:
      return "Nothing here"
    }
  }

  readonly property string emptyListHint: {
    if (tab === "apps")
      return "Browser, Discord, Terminal, and other lean-back tools appear here. Games and streaming live under Games / Media."
    if (tab === "media")
      return "Install Spotify, Netflix, Plex, YouTube, … or add a streaming web app under Settings → Software → Web apps."
    if (tab === "games")
      return "Install Steam, RetroArch, or other games — they appear here A–Z. Stores are backends, not home."
    if (tab === "search" && (searchQuery.length || filterQuery.length))
      return "Try another query, or open Settings from the top bar."
    return ""
  }

  readonly property string emptyDetailCopy: {
    if (tab === "apps")
      return "No app selected"
    if (tab === "media")
      return "No streaming app selected"
    if (tab === "games")
      return "No game selected"
    if (tab === "settings")
      return "No Settings page selected"
    return "No result selected"
  }

  readonly property var mediaOptions: {
    const opts = []
    if (library.hasResumeMedia()) {
      opts.push({
        id: "resume",
        label: library.resumeMediaLabel(),
        hint: Config.consoleLastMediaPath
      })
    }
    opts.push({
      id: "sample",
      label: "Sample reel",
      hint: "Built-in loop"
    })
    opts.push({
      id: "pick",
      label: "Choose file…",
      hint: "zenity / kdialog"
    })
    return opts
  }

  function openMediaSheet() {
    sheetReturnZone = focusZone
    mediaSheet.options = mediaOptions
    mediaSheet.title = "Media"
    mediaSheet.subtitle = "Play with mpv" + (library.hasGamescope ? " · gamescope when available" : "")
    mediaSheet.openSheet()
  }

  function openDetailsSheet() {
    const it = featured
    if (!it)
      return
    sheetReturnZone = focusZone
    detailsSheet.title = it.title || "Details"
    detailsSheet.subtitle = [it.tag, it.meta].filter(function (s) {
      return s && String(s).length
    }).join(" · ")
    const opts = []
    if (it.kind === "media")
      opts.push({ id: "media", label: "Open Media menu", hint: "Resume · Sample · Choose file" })
    else
      opts.push({ id: "open", label: "Open", hint: it.meta || it.kind || "" })
    if (isRecentItem(it))
      opts.push({ id: "remove-recent", label: "Remove from Recent", hint: "Jump Back In" })
    detailsSheet.options = opts
    detailsSheet.openSheet()
  }

  function isRecentItem(it) {
    if (!it || !it.id)
      return false
    const rec = Config.consoleRecents || []
    for (let i = 0; i < rec.length; i++) {
      if (rec[i] && String(rec[i].id) === String(it.id))
        return true
    }
    return false
  }

  function isListSelectable(item) {
    return !!(item && item.kind !== "section" && !item.isSection && item.selectable !== false)
  }

  function nearestSelectableIndex(from, preferDelta) {
    const items = listItems
    if (!items.length)
      return 0
    const n = items.length
    let i = Math.max(0, Math.min(from, n - 1))
    if (isListSelectable(items[i]))
      return i
    const dir = preferDelta >= 0 ? 1 : -1
    for (let step = 1; step < n; step++) {
      const a = i + dir * step
      if (a >= 0 && a < n && isListSelectable(items[a]))
        return a
      const b = i - dir * step
      if (b >= 0 && b < n && isListSelectable(items[b]))
        return b
    }
    return i
  }

  function moveListIndex(delta) {
    const items = listItems
    if (!items.length)
      return
    let i = listIndex
    const n = items.length
    for (let step = 0; step < n; step++) {
      i += delta
      if (i < 0 || i >= n)
        return
      if (isListSelectable(items[i])) {
        listIndex = i
        return
      }
    }
  }

  function activateItem(item) {
    if (!item)
      return
    if (item.kind === "section" || item.isSection)
      return
    if (item.kind === "media") {
      openMediaSheet()
      return
    }
    if (item.kind === "settings") {
      root.focusConsoleSettings(item.settingsPage || item.paneId || "")
      return
    }
    library.activate(item)
  }

  function selectSettingsPage(page) {
    const p = String(page || "").trim()
    if (!p.length)
      return false
    const items = appsModel.settingsList
    for (let i = 0; i < items.length; i++) {
      if (!isListSelectable(items[i]))
        continue
      if (String(items[i].settingsPage || "") === p) {
        listIndex = i
        return true
      }
    }
    // Match by hub when a leaf was requested but only hub is listed
    try {
      const hub = EnvGate.paneHubFor(p)
      if (hub && hub.length) {
        for (let j = 0; j < items.length; j++) {
          if (!isListSelectable(items[j]))
            continue
          if (String(items[j].settingsPage || "") === hub) {
            listIndex = j
            return true
          }
        }
      }
    } catch (e) {
    }
    return false
  }

  function focusConsoleSettings(page) {
    const p = String(page || "").trim()
    ShellState.consoleSettingsPage = p
    if (tab !== "settings") {
      root.tab = "settings"
      root.barSlot = 4
      root.listIndex = 0
    }
    Qt.callLater(function () {
      if (p.length)
        root.selectSettingsPage(p)
      root.focusZone = "detail"
      if (sideList)
        sideList.clearFieldFocus()
      if (settingsPane) {
        settingsPane.mode = "hub"
        settingsPane.actionIndex = 0
      }
    })
  }

  function clampListIndex() {
    if (!listItems.length) {
      listIndex = 0
      return
    }
    listIndex = nearestSelectableIndex(
        Math.max(0, Math.min(listIndex, listItems.length - 1)), 1)
  }

  onListItemsChanged: Qt.callLater(clampListIndex)
  onTabChanged: {
    listIndex = 0
    clampListIndex()
  }

  function goGames() {
    tab = "games"
    focusZone = "list"
    barSlot = 0
    listIndex = 0
  }

  function selectDestination(id) {
    const map = { games: 0, media: 1, apps: 2, search: 3, settings: 4 }
    root.tab = id
    root.barSlot = map[id] !== undefined ? map[id] : 0
    root.listIndex = 0
    if (id === "search") {
      root.focusZone = "searchField"
      Qt.callLater(function () {
        if (sideList)
          sideList.focusSearchField()
      })
    } else {
      root.focusZone = "list"
      if (sideList)
        sideList.clearFieldFocus()
    }
  }

  // LB / RB (and wrap) — Games · Media · Apps · Search · Settings
  function cycleDestination(delta) {
    const ids = root.topDestinations
    let i = ids.indexOf(tab)
    if (i < 0)
      i = 0
    const n = ids.length
    i = ((i + delta) % n + n) % n
    selectDestination(ids[i])
  }

  function handlePad(button) {
    const b = String(button || "")
    if (mediaSheet.open) {
      if (b === "b" || b === "select") {
        mediaSheet.closeSheet()
        return
      }
      if (b === "a" || b === "start") {
        mediaSheet.activateFocused()
        return
      }
      if (b === "up") {
        mediaSheet.move(-1)
        return
      }
      if (b === "down") {
        mediaSheet.move(1)
        return
      }
      return
    }
    if (detailsSheet.open) {
      if (b === "b" || b === "select") {
        detailsSheet.closeSheet()
        return
      }
      if (b === "a" || b === "start") {
        detailsSheet.activateFocused()
        return
      }
      if (b === "up") {
        detailsSheet.move(-1)
        return
      }
      if (b === "down") {
        detailsSheet.move(1)
        return
      }
      return
    }
    if (ShellState.consoleExitConfirmOpen) {
      if (b === "a" || b === "start") {
        ShellState.consoleExitConfirmOpen = false
        library.activate({ id: "desktop", kind: "posture", title: "Desktop" })
      } else if (b === "b" || b === "select") {
        ShellState.consoleExitConfirmOpen = false
      }
      return
    }
    if (ShellState.controlCenterOpen)
      return
    if (ShellState.consoleSwitcherOpen)
      return
    // Shoulder bumpers always cycle top destinations (Xbox LB/RB · PS L1/R1)
    if (b === "lb" || b === "l1") {
      root.cycleDestination(-1)
      return
    }
    if (b === "rb" || b === "r1") {
      root.cycleDestination(1)
      return
    }
    if (b === "a") {
      root.activateCurrent()
      return
    }
    if (b === "b") {
      root.handleBack()
      return
    }
    if (b === "y") {
      if (tab === "settings" && (focusZone === "list" || focusZone === "detail")) {
        if (settingsPane)
          settingsPane.activateFocused()
        return
      }
      if (focusZone === "list" || focusZone === "detail")
        openDetailsSheet()
      return
    }
    if (b === "start") {
      ShellState.consoleExitConfirmOpen = true
      return
    }
    if (b === "left") {
      root.moveHorizontal(-1)
      return
    }
    if (b === "right") {
      root.moveHorizontal(1)
      return
    }
    if (b === "up") {
      root.moveVertical(-1)
      return
    }
    if (b === "down") {
      root.moveVertical(1)
    }
  }

  function activateCurrent() {
    if (mediaSheet.open) {
      mediaSheet.activateFocused()
      return
    }
    if (detailsSheet.open) {
      detailsSheet.activateFocused()
      return
    }
    if (ShellState.consoleSwitcherOpen) {
      switcher.activateFocused()
      return
    }
    if (focusZone === "chrome") {
      const ids = root.topDestinations
      if (barSlot >= 0 && barSlot < ids.length)
        selectDestination(ids[barSlot])
      return
    }
    if (focusZone === "searchField" || focusZone === "filterField") {
      focusZone = "list"
      if (sideList)
        sideList.clearFieldFocus()
      return
    }
    if (focusZone === "detail" && tab === "settings") {
      if (settingsPane)
        settingsPane.activateFocused()
      return
    }
    if (focusZone === "detail" || focusZone === "list")
      activateItem(featured)
  }

  function moveHorizontal(delta) {
    if (mediaSheet.open || detailsSheet.open)
      return
    if (ShellState.consoleSwitcherOpen) {
      switcher.moveFocus(delta)
      return
    }
    if (focusZone === "chrome") {
      barSlot = Math.max(0, Math.min(root.topDestinations.length - 1, barSlot + delta))
      return
    }
    if (focusZone === "list" && delta > 0 && featured) {
      focusZone = "detail"
      if (sideList)
        sideList.clearFieldFocus()
      return
    }
    if (focusZone === "detail" && delta < 0) {
      focusZone = "list"
      return
    }
    // Left/Right on list/fields cycle top destinations
    if (focusZone === "list" || focusZone === "searchField" || focusZone === "filterField") {
      const ids = root.topDestinations
      let i = ids.indexOf(tab)
      if (i < 0)
        i = 0
      i = Math.max(0, Math.min(ids.length - 1, i + delta))
      selectDestination(ids[i])
    }
  }

  function moveVertical(delta) {
    if (mediaSheet.open || detailsSheet.open || ShellState.consoleSwitcherOpen)
      return
    if (focusZone === "detail" && tab === "settings") {
      if (settingsPane)
        settingsPane.moveAction(delta)
      return
    }
    if (focusZone === "chrome") {
      if (delta > 0) {
        focusZone = "searchField"
        Qt.callLater(function () {
          if (sideList)
            sideList.focusSearchField()
        })
      }
      return
    }
    if (focusZone === "searchField") {
      if (delta < 0) {
        focusZone = "chrome"
        barSlot = root.topDestinations.indexOf(tab)
        if (sideList)
          sideList.clearFieldFocus()
      } else {
        focusZone = "filterField"
        Qt.callLater(function () {
          if (sideList)
            sideList.focusFilterField()
        })
      }
      return
    }
    if (focusZone === "filterField") {
      if (delta < 0) {
        focusZone = "searchField"
        Qt.callLater(function () {
          if (sideList)
            sideList.focusSearchField()
        })
      } else {
        focusZone = "list"
        if (sideList)
          sideList.clearFieldFocus()
        clampListIndex()
      }
      return
    }
    if (focusZone === "detail") {
      if (delta < 0) {
        focusZone = "chrome"
        barSlot = root.topDestinations.indexOf(tab)
      }
      return
    }
    // list
    if (delta < 0) {
      const before = listIndex
      moveListIndex(-1)
      if (listIndex === before) {
        focusZone = "filterField"
        Qt.callLater(function () {
          if (sideList)
            sideList.focusFilterField()
        })
      }
      return
    }
    moveListIndex(1)
  }

  function handleBack() {
    if (mediaSheet.open) {
      mediaSheet.closeSheet()
      return
    }
    if (detailsSheet.open) {
      detailsSheet.closeSheet()
      return
    }
    if (ShellState.controlCenterOpen) {
      ShellState.closeControlCenter()
      return
    }
    if (ShellState.consoleSwitcherOpen) {
      ShellState.closeConsoleSwitcher()
      return
    }
    if (focusZone === "detail" && tab === "settings" && settingsPane) {
      if (settingsPane.exitDrill())
        return
      focusZone = "list"
      return
    }
    if (focusZone === "detail") {
      focusZone = "list"
      return
    }
    if ((searchQuery.length || filterQuery.length) && (tab === "search" || focusZone === "searchField" || focusZone === "filterField")) {
      searchQuery = ""
      filterQuery = ""
      listIndex = 0
      return
    }
    if (tab !== "games") {
      goGames()
      return
    }
    if (focusZone !== "chrome") {
      focusZone = "chrome"
      barSlot = root.topDestinations.indexOf(tab)
      if (barSlot < 0)
        barSlot = 0
    }
  }

  function typeSearchChar(ch) {
    if (focusZone !== "searchField" && focusZone !== "filterField") {
      if (root.topDestinations.indexOf(tab) < 0)
        selectDestination("search")
      focusZone = "searchField"
      Qt.callLater(function () {
        if (sideList)
          sideList.focusSearchField()
      })
    }
    if (focusZone === "filterField")
      filterQuery += ch
    else
      searchQuery += ch
    listIndex = 0
  }

  Rectangle {
    anchors.fill: parent
    color: Theme.bg
  }

  ColumnLayout {
    anchors.fill: parent
    spacing: 0
    visible: !ShellState.consoleSwitcherOpen
    opacity: root.navOpacity
    transform: Translate {
      y: 10 * (1 - root.navOpacity)
    }

    ConsoleBar {
      id: bar
      Layout.fillWidth: true
      tab: root.tab
      focusedSlot: root.focusZone === "chrome" ? root.barSlot : -1
      sessionToggleVisible: library.hasGamescope
      sessionMode: library.sessionMode
      sessionEffective: library.sessionEffective
      onTabSelected: id => root.selectDestination(id)
      onSessionToggleRequested: library.toggleSessionMode()
    }

    RowLayout {
      Layout.fillWidth: true
      Layout.fillHeight: true
      spacing: 0

      ConsoleSideList {
        id: sideList
        Layout.preferredWidth: Math.min(360, Math.max(260, parent.width * 0.32))
        Layout.fillHeight: true
        items: root.listItems
        focusedIndex: root.listIndex
        listFocused: root.focusZone === "list"
        searchFocused: root.focusZone === "searchField"
        filterFocused: root.focusZone === "filterField"
        searchText: root.searchQuery
        filterText: root.filterQuery
        emptyCopy: root.emptyListCopy
        emptyHint: root.emptyListHint
        onSearchTextEdited: t => {
          root.searchQuery = t
          root.listIndex = 0
        }
        onFilterTextEdited: t => {
          root.filterQuery = t
          root.listIndex = 0
        }
        onIndexRequested: i => {
          const items = root.listItems
          if (items[i] && !root.isListSelectable(items[i])) {
            root.listIndex = root.nearestSelectableIndex(i, 1)
          } else {
            root.listIndex = i
          }
          root.focusZone = "list"
        }
        onItemActivated: item => root.activateItem(item)
        onSearchFocusRequested: root.focusZone = "searchField"
        onFilterFocusRequested: root.focusZone = "filterField"
        onListFocusRequested: root.focusZone = "list"
      }

      Rectangle {
        Layout.preferredWidth: 1
        Layout.fillHeight: true
        color: Theme.chromeHairline
        opacity: 0.4
      }

      ConsoleDetailPane {
        id: detailPane
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: root.tab !== "settings"
        item: root.tab === "settings" ? null : root.featured
        detailFocused: root.focusZone === "detail" && root.tab !== "settings"
        emptyCopy: root.emptyDetailCopy
        emptyHint: root.emptyListHint
        onLaunchRequested: root.activateItem(root.featured)
        onDetailsRequested: root.openDetailsSheet()
      }

      ConsoleSettingsPane {
        id: settingsPane
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: root.tab === "settings"
        item: root.tab === "settings" ? root.featured : null
        detailFocused: root.focusZone === "detail" && root.tab === "settings"
        librarySession: library
        onFullSettingsRequested: page => {
          library.statusHint = "Opening Full Settings…"
          ShellState.openSettings(page)
        }
        onPostureDesktopRequested: {
          library.activate({ id: "desktop", kind: "posture", title: "Desktop" })
        }
        onActionHint: t => {
          library.statusHint = t
        }
      }
    }

    ConsoleFooter {
      Layout.fillWidth: true
      hint: library.statusHint
      padActive: library.hasPad
    }
  }

  ConsoleSwitcher {
    id: switcher
    anchors.fill: parent
    // Gamescope session: Hyprland toplevels don't exist — the running list is
    // fed by the seat/focus-router registry instead.
    sessionMode: library.replacesHyprland
    rootDir: library.rootDir
  }

  ControlCenter {
    id: controlCenter
    anchors.fill: parent
    z: 20
  }

  ConsoleLeanSheet {
    id: mediaSheet
    title: "Media"
    onClosed: {
      root.focusZone = root.sheetReturnZone
      root.forceActiveFocus()
    }
    onOptionActivated: opt => {
      mediaSheet.closeSheet()
      if (!opt)
        return
      if (opt.id === "resume")
        library.launchMediaPath(Config.consoleLastMediaPath, "Media")
      else if (opt.id === "sample")
        library.launchMediaPath(library.sampleLoop, "Sample reel")
      else if (opt.id === "pick")
        library.pickMediaFile()
    }
  }

  ConsoleLeanSheet {
    id: detailsSheet
    title: "Details"
    showPrimary: false
    onClosed: {
      root.focusZone = root.sheetReturnZone
      root.forceActiveFocus()
    }
    onOptionActivated: opt => {
      detailsSheet.closeSheet()
      if (!opt)
        return
      if (opt.id === "media")
        root.openMediaSheet()
      else if (opt.id === "remove-recent")
        library.removeRecent(root.featured ? root.featured.id : "")
      else
        root.activateItem(root.featured)
    }
    onPrimaryActivated: {
      detailsSheet.closeSheet()
      root.activateItem(root.featured)
    }
  }

  Keys.onPressed: event => {
    if (mediaSheet.open || detailsSheet.open) {
      if (event.key === Qt.Key_Escape) {
        root.handleBack()
        event.accepted = true
        return
      }
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
        root.activateCurrent()
        event.accepted = true
        return
      }
      if (event.key === Qt.Key_Up) {
        if (mediaSheet.open)
          mediaSheet.move(-1)
        else
          detailsSheet.move(-1)
        event.accepted = true
        return
      }
      if (event.key === Qt.Key_Down) {
        if (mediaSheet.open)
          mediaSheet.move(1)
        else
          detailsSheet.move(1)
        event.accepted = true
        return
      }
      event.accepted = true
      return
    }
    // Let TextFields handle typing when focused
    if (focusZone === "searchField" || focusZone === "filterField"
        || (tab === "settings" && settingsPane && settingsPane.mode === "wifiPassword")) {
      if (event.key === Qt.Key_Escape) {
        root.handleBack()
        event.accepted = true
        return
      }
      if (event.key === Qt.Key_Up || event.key === Qt.Key_Down
          || event.key === Qt.Key_Left || event.key === Qt.Key_Right
          || event.key === Qt.Key_Return || event.key === Qt.Key_Enter
          || event.key === Qt.Key_Tab) {
        // fall through to pad grammar below
      } else {
        return
      }
    }
    if (event.key === Qt.Key_C && !(event.modifiers & Qt.ControlModifier)
        && focusZone !== "searchField" && focusZone !== "filterField") {
      ShellState.toggleControlCenter()
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Escape) {
      root.handleBack()
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Backspace && focusZone !== "searchField" && focusZone !== "filterField") {
      if (tab === "search" && searchQuery.length) {
        searchQuery = searchQuery.slice(0, -1)
        event.accepted = true
        return
      }
    }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
      root.activateCurrent()
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Left) {
      root.moveHorizontal(-1)
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Right) {
      root.moveHorizontal(1)
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Up) {
      root.moveVertical(-1)
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Down) {
      root.moveVertical(1)
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Tab) {
      root.moveVertical(event.modifiers & Qt.ShiftModifier ? -1 : 1)
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Y || event.key === Qt.Key_I) {
      root.openDetailsSheet()
      event.accepted = true
      return
    }
    if (event.text && event.text.length === 1 && event.text >= " " && !(event.modifiers & Qt.ControlModifier)) {
      const ch = event.text
      if (/^[a-zA-Z0-9 ._\-#]$/.test(ch)) {
        root.typeSearchChar(ch)
        event.accepted = true
      }
    }
  }

  Timer {
    id: hintClear
    interval: 3200
    onTriggered: library.clearHint()
  }

  Connections {
    target: library
    function onStatusHintChanged() {
      if (library.statusHint.length && library.statusHint.indexOf("Opening") !== 0
          && library.statusHint.indexOf("Choose") !== 0)
        hintClear.restart()
    }
  }

  Connections {
    target: ShellState
    function onConsoleSettingsRequested(page) {
      root.focusConsoleSettings(page)
    }
    function onConsoleNavVisibleChanged() {
      if (!ShellState.consoleNavVisible) {
        library.cancelLaunchWatch()
      } else {
        root.forceActiveFocus()
        // Titles may have changed while an app had the seat (installs, playlists)
        library.refreshGames()
      }
    }
    function onConsoleSwitcherOpenChanged() {
      if (ShellState.consoleSwitcherOpen)
        root.forceActiveFocus()
    }
    function onControlCenterOpenChanged() {
      if (!ShellState.controlCenterOpen && ShellState.consoleNavVisible)
        root.forceActiveFocus()
    }
    function onPadAction(button) {
      if (ShellState.sessionLocked)
        return
      if (ShellState.controlCenterOpen)
        return
      if (!ShellState.consoleNavVisible && !ShellState.consoleSwitcherOpen
          && !ShellState.consoleExitConfirmOpen && !mediaSheet.open && !detailsSheet.open)
        return
      root.handlePad(button)
    }
  }

  Rectangle {
    anchors.fill: parent
    z: 30
    visible: ShellState.consoleExitConfirmOpen
    color: Theme.scrimFill
    MouseArea {
      anchors.fill: parent
      onClicked: ShellState.consoleExitConfirmOpen = false
    }
    Rectangle {
      anchors.centerIn: parent
      width: Math.min(parent.width - 64, 420)
      height: confirmCol.implicitHeight + 40
      radius: Theme.radiusXl
      color: Theme.menuPlateFill
      border.width: 1
      border.color: Theme.chromeBorder
      ColumnLayout {
        id: confirmCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.spaceLg
        spacing: Theme.spaceMd
        Text {
          Layout.fillWidth: true
          text: "Return to Desktop?"
          color: Theme.text
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSize + 4
          font.weight: Font.DemiBold
          horizontalAlignment: Text.AlignHCenter
        }
        Text {
          Layout.fillWidth: true
          text: "Ⓐ Confirm   Ⓑ Menu"
          color: Theme.textMute
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSizeSm
          horizontalAlignment: Text.AlignHCenter
        }
      }
    }
  }

  Component.onCompleted: {
    forceActiveFocus()
    library.refreshAvailability()
  }
}
