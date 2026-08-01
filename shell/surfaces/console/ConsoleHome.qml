import Quickshell
import QtQuick
import QtQuick.Layouts
import "../../shared"
import "../desktop"

// Console navigation layer root — home + library/search + switcher + CC.
Item {
  id: root
  anchors.fill: parent
  focus: true

  // focusZone: bar | hero | jump | apps | library | search
  property string focusZone: "jump"
  property int barSlot: 0
  property int heroAction: 0
  property int jumpIndex: 0
  property int appsIndex: 0
  property int libraryIndex: 0
  property string tab: "home"
  property string searchQuery: ""

  ConsoleLibrary { id: library }
  ConsoleAppsModel { id: appsModel; query: root.searchQuery }

  function handlePad(button) {
    const b = String(button || "")
    if (ShellState.consoleExitConfirmOpen) {
      if (b === "a" || b === "start") {
        ShellState.consoleExitConfirmOpen = false
        library.activate({ id: "desktop", kind: "posture", title: "Desktop" })
      } else if (b === "b" || b === "select") {
        ShellState.consoleExitConfirmOpen = false
      }
      return
    }
    if (ShellState.controlCenterOpen) {
      // CC owns pad via its own Connections
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
    if (b === "x") {
      if (ShellState.consoleSwitcherOpen)
        switcher.closeFocused()
      return
    }
    if (b === "y") {
      if (focusZone === "hero")
        library.statusHint = (featured.title || "Item") + " — open from Library for details"
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

  readonly property var featured: {
    if (library.games.length && jumpIndex >= 0 && jumpIndex < library.games.length)
      return library.games[jumpIndex]
    return library.featured
  }

  readonly property var libraryItems: appsModel.allApps
  readonly property var searchItems: appsModel.filtered

  function activateCurrent() {
    if (ShellState.consoleSwitcherOpen) {
      switcher.activateFocused()
      return
    }
    if (focusZone === "bar") {
      if (barSlot === 3) {
        ShellState.toggleControlCenter()
        return
      }
      const tabs = ["home", "library", "search"]
      tab = tabs[Math.max(0, Math.min(barSlot, 2))]
      if (tab === "library")
        focusZone = "library"
      else if (tab === "search")
        focusZone = "search"
      return
    }
    if (focusZone === "hero") {
      if (heroAction === 0)
        library.activate(featured)
      else
        library.statusHint = (featured.title || "Item") + " — open from Library for details"
      return
    }
    if (focusZone === "jump") {
      if (library.games.length)
        library.activate(library.games[jumpIndex])
      return
    }
    if (focusZone === "apps") {
      if (library.apps.length)
        library.activate(library.apps[appsIndex])
      return
    }
    if (focusZone === "library") {
      if (libraryItems.length)
        library.activate(libraryItems[libraryIndex])
      return
    }
    if (focusZone === "search") {
      if (searchItems.length)
        library.activate(searchItems[libraryIndex])
      return
    }
  }

  function moveHorizontal(delta) {
    if (ShellState.consoleSwitcherOpen) {
      switcher.moveFocus(delta)
      return
    }
    if (focusZone === "bar") {
      barSlot = Math.max(0, Math.min(3, barSlot + delta))
      return
    }
    if (focusZone === "hero") {
      heroAction = Math.max(0, Math.min(1, heroAction + delta))
      return
    }
    if (focusZone === "jump") {
      if (!library.games.length)
        return
      jumpIndex = Math.max(0, Math.min(library.games.length - 1, jumpIndex + delta))
      return
    }
    if (focusZone === "apps") {
      if (!library.apps.length)
        return
      appsIndex = Math.max(0, Math.min(library.apps.length - 1, appsIndex + delta))
      return
    }
    if (focusZone === "library") {
      if (!libraryItems.length)
        return
      libraryIndex = Math.max(0, Math.min(libraryItems.length - 1, libraryIndex + delta))
      return
    }
    if (focusZone === "search") {
      if (!searchItems.length)
        return
      libraryIndex = Math.max(0, Math.min(searchItems.length - 1, libraryIndex + delta))
    }
  }

  function moveVertical(delta) {
    if (ShellState.consoleSwitcherOpen)
      return
    if (tab === "library") {
      focusZone = "library"
      return
    }
    if (tab === "search") {
      focusZone = delta < 0 ? "bar" : "search"
      return
    }
    const zones = ["bar", "hero", "jump", "apps"]
    let i = zones.indexOf(focusZone)
    if (i < 0)
      i = 0
    i = Math.max(0, Math.min(zones.length - 1, i + delta))
    focusZone = zones[i]
  }

  function handleBack() {
    if (ShellState.controlCenterOpen) {
      ShellState.closeControlCenter()
      return
    }
    if (ShellState.consoleSwitcherOpen) {
      ShellState.closeConsoleSwitcher()
      return
    }
    if (tab === "search" && searchQuery.length) {
      searchQuery = ""
      return
    }
    if (tab !== "home") {
      tab = "home"
      focusZone = "jump"
      return
    }
  }

  function typeSearchChar(ch) {
    if (tab !== "search") {
      tab = "search"
      focusZone = "search"
      barSlot = 2
      searchQuery = ""
    }
    searchQuery += ch
    libraryIndex = 0
  }

  Rectangle {
    anchors.fill: parent
    color: Theme.bg
  }

  Rectangle {
    anchors.fill: parent
    gradient: Gradient {
      GradientStop { position: 0.0; color: Theme.bg }
      GradientStop { position: 1.0; color: Qt.rgba(Theme.bgElevated.r, Theme.bgElevated.g, Theme.bgElevated.b, 0.55) }
    }
  }

  ColumnLayout {
    anchors.fill: parent
    spacing: 0
    visible: ShellState.consoleNavVisible && !ShellState.consoleSwitcherOpen

    ConsoleBar {
      id: bar
      Layout.fillWidth: true
      tab: root.tab
      focusedSlot: root.focusZone === "bar" ? root.barSlot : -1
      onTabSelected: id => {
        root.tab = id
        root.focusZone = id === "home" ? "jump" : id
        if (id === "library" || id === "search")
          root.libraryIndex = 0
        if (id === "home")
          root.barSlot = 0
        else if (id === "library")
          root.barSlot = 1
        else if (id === "search")
          root.barSlot = 2
      }
      onControlCenterRequested: ShellState.toggleControlCenter()
    }

    Item {
      Layout.fillWidth: true
      Layout.fillHeight: true

      // Home
      ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spaceXl
        spacing: Theme.spaceXl
        visible: root.tab === "home"

        ConsoleHero {
          Layout.fillWidth: true
          item: root.featured
          focusedAction: root.focusZone === "hero" ? root.heroAction : -1
          onResumeRequested: library.activate(root.featured)
          onDetailsRequested: library.statusHint = (root.featured.title || "Item") + " — open from Library for details"
        }

        ConsoleRow {
          Layout.fillWidth: true
          title: "JUMP BACK IN"
          items: library.games
          focusedIndex: root.focusZone === "jump" ? root.jumpIndex : -1
          cardWidth: 188
          cardHeight: 112
          onFocusRequested: i => {
            root.focusZone = "jump"
            root.jumpIndex = i
          }
          onItemActivated: item => library.activate(item)
        }

        ConsoleRow {
          Layout.fillWidth: true
          title: "APPS"
          items: library.apps
          focusedIndex: root.focusZone === "apps" ? root.appsIndex : -1
          cardWidth: 128
          cardHeight: 96
          onFocusRequested: i => {
            root.focusZone = "apps"
            root.appsIndex = i
          }
          onItemActivated: item => library.activate(item)
        }

        Item { Layout.fillHeight: true }
      }

      // Library
      ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spaceXl
        spacing: Theme.spaceLg
        visible: root.tab === "library"

        Text {
          text: "LIBRARY"
          color: Theme.textDim
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSizeSm
          font.letterSpacing: 1.2
          font.weight: Font.DemiBold
        }

        Text {
          visible: !libraryItems.length
          text: "No applications found"
          color: Theme.textMute
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSize
        }

        ConsoleRow {
          Layout.fillWidth: true
          visible: libraryItems.length > 0
          title: ""
          items: libraryItems
          focusedIndex: root.focusZone === "library" ? root.libraryIndex : -1
          cardWidth: 148
          cardHeight: 100
          onFocusRequested: i => {
            root.focusZone = "library"
            root.libraryIndex = i
          }
          onItemActivated: item => library.activate(item)
        }

        Item { Layout.fillHeight: true }
      }

      // Search
      ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spaceXl
        spacing: Theme.spaceLg
        visible: root.tab === "search"

        Text {
          text: "SEARCH"
          color: Theme.textDim
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSizeSm
          font.letterSpacing: 1.2
          font.weight: Font.DemiBold
        }

        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 44
          radius: Theme.radiusLg
          color: Theme.elevatedFill
          border.width: root.focusZone === "search" && !searchItems.length ? 2 : 1
          border.color: root.focusZone === "search" ? Theme.accent : Theme.chromeBorder

          Text {
            anchors.fill: parent
            anchors.margins: Theme.spaceMd
            verticalAlignment: Text.AlignVCenter
            text: root.searchQuery.length ? root.searchQuery : "Type to filter apps…"
            color: root.searchQuery.length ? Theme.text : Theme.textMute
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize + 2
            elide: Text.ElideRight
          }
        }

        Text {
          visible: root.searchQuery.length > 0 && !searchItems.length
          text: "No matches"
          color: Theme.textMute
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSize
        }

        ConsoleRow {
          Layout.fillWidth: true
          visible: searchItems.length > 0
          title: root.searchQuery.length ? "RESULTS" : "ALL APPS"
          items: searchItems
          focusedIndex: root.focusZone === "search" ? root.libraryIndex : -1
          cardWidth: 148
          cardHeight: 100
          onFocusRequested: i => {
            root.focusZone = "search"
            root.libraryIndex = i
          }
          onItemActivated: item => library.activate(item)
        }

        Item { Layout.fillHeight: true }
      }
    }

    ConsoleFooter {
      Layout.fillWidth: true
      hint: library.statusHint
    }
  }

  ConsoleSwitcher {
    id: switcher
    anchors.fill: parent
  }

  ControlCenter {
    id: controlCenter
    anchors.fill: parent
    z: 20
  }

  Keys.onPressed: event => {
    if (event.key === Qt.Key_C && !(event.modifiers & Qt.ControlModifier) && tab !== "search") {
      ShellState.toggleControlCenter()
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Escape) {
      root.handleBack()
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Backspace && tab === "search") {
      if (searchQuery.length)
        searchQuery = searchQuery.slice(0, -1)
      event.accepted = true
      return
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
    if (event.key === Qt.Key_Delete || event.key === Qt.Key_X) {
      if (ShellState.consoleSwitcherOpen) {
        switcher.closeFocused()
        event.accepted = true
      }
      return
    }
    // Printable → search
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
      if (library.statusHint.length && library.statusHint.indexOf("Opening") !== 0)
        hintClear.restart()
    }
  }

  Connections {
    target: ShellState
    function onConsoleNavVisibleChanged() {
      if (!ShellState.consoleNavVisible)
        library.cancelLaunchWatch()
      else
        root.forceActiveFocus()
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
      if (!ShellState.consoleNavVisible && !ShellState.consoleSwitcherOpen && !ShellState.consoleExitConfirmOpen)
        return
      root.handlePad(button)
    }
  }

  // Return-to-desktop confirm (Guide Start / pad Start)
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
          text: "Ⓐ Confirm   Ⓑ Cancel"
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
