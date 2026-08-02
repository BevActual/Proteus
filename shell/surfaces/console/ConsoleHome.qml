import Quickshell
import QtQuick
import QtQuick.Layouts
import "../../shared"
import "../desktop"

// Console navigation — tvOS-inspired shelf Home + Library/Search destinations.
Item {
  id: root
  anchors.fill: parent
  focus: true

  property real navOpacity: 1

  // focusZone: chrome | hero | shelf | libSection | library | search
  property string focusZone: "hero"
  property int barSlot: 0
  property int heroAction: 0
  property int shelfIndex: 0
  property int cardIndex: 0
  property int libraryIndex: 0
  property int libSectionIndex: 0
  property string tab: "home"
  property string searchQuery: ""
  property string sheetReturnZone: "hero"

  readonly property var libSections: appsModel.sectionLabels
  readonly property string libSectionId: {
    const s = libSections[Math.max(0, Math.min(libSectionIndex, libSections.length - 1))]
    return s ? s.id : "all"
  }

  ConsoleLibrary { id: library }
  ConsoleAppsModel {
    id: appsModel
    query: root.searchQuery
    section: root.libSectionId
  }

  // Home Web shelf: browsers + proteus-web-* (not Library's full web section dump).
  readonly property var webItems: {
    const out = []
    for (let i = 0; i < appsModel.allApps.length; i++) {
      const a = appsModel.allApps[i]
      const id = String(a.id || "").toLowerCase()
      if (id.indexOf("proteus-web-") === 0) {
        out.push(a)
        continue
      }
      if (id.indexOf("firefox") >= 0 || id.indexOf("chromium") >= 0 || id.indexOf("chrome") >= 0
          || id.indexOf("brave") >= 0 || id.indexOf("librewolf") >= 0)
        out.push(a)
    }
    if (out.length)
      return out
    return [{
      id: "webapps-install",
      title: "Install Web apps",
      tag: "WEB",
      kind: "settings",
      settingsPage: "packages-webapps",
      chromeStyle: true,
      color0: Theme.elevatedFill,
      color1: Theme.bgElevated,
      meta: "Software → Web apps"
    }]
  }

  // Media lean-sheet entry (console play path) — not a DesktopEntry card.
  readonly property var mediaPlayCard: {
    if (!library.hasMpv)
      return null
    return library.seatMedia()
  }

  readonly property var mediaShelfItems: {
    const out = []
    if (root.mediaPlayCard)
      out.push(root.mediaPlayCard)
    const apps = appsModel.mediaShelf
    for (let i = 0; i < apps.length; i++)
      out.push(apps[i])
    return out
  }

  // Home shelves: one card per application / web app (DesktopEntries).
  // Jump Back In = recent launches; Media play card opens the lean sheet.
  readonly property var homeShelves: {
    const shelves = []
    shelves.push({
      id: "jump",
      title: "Jump Back In",
      items: library.games,
      chromeStyle: false,
      allowRemove: true,
      cardWidth: 240,
      cardHeight: 140
    })
    if (appsModel.appsShelf.length) {
      shelves.push({
        id: "apps",
        title: "Apps",
        items: appsModel.appsShelf,
        chromeStyle: true,
        allowRemove: false,
        cardWidth: 160,
        cardHeight: 120
      })
    }
    shelves.push({
      id: "web",
      title: "Web Apps",
      items: root.webItems,
      chromeStyle: true,
      allowRemove: false,
      cardWidth: 160,
      cardHeight: 120
    })
    if (appsModel.gamesShelf.length) {
      shelves.push({
        id: "games",
        title: "Games",
        items: appsModel.gamesShelf,
        chromeStyle: false,
        allowRemove: false,
        cardWidth: 180,
        cardHeight: 120
      })
    }
    if (root.mediaShelfItems.length) {
      shelves.push({
        id: "media",
        title: "Media",
        items: root.mediaShelfItems,
        chromeStyle: false,
        allowRemove: false,
        cardWidth: 180,
        cardHeight: 120
      })
    }
    return shelves
  }

  readonly property var currentShelf: {
    if (!homeShelves.length)
      return null
    return homeShelves[Math.max(0, Math.min(shelfIndex, homeShelves.length - 1))]
  }

  readonly property string currentShelfId: currentShelf ? currentShelf.id : ""

  readonly property string featuredShelfTitle: currentShelf ? (currentShelf.title || "") : ""

  // Hero always tracks the focused card on the active shelf (any shelf).
  readonly property var featured: {
    if (focusZone === "shelf" || focusZone === "hero") {
      const items = shelfItemsAt(shelfIndex)
      if (items.length) {
        const i = Math.max(0, Math.min(cardIndex, items.length - 1))
        return items[i]
      }
    }
    if (library.games.length)
      return library.games[0]
    const apps = appsModel.appsShelf
    if (apps.length)
      return apps[0]
    return library.featured
  }

  readonly property string featuredMetaLine: {
    const it = featured
    if (!it)
      return ""
    const bits = []
    if (featuredShelfTitle.length && focusZone === "shelf")
      bits.push(featuredShelfTitle)
    else if (featuredShelfTitle.length && focusZone === "hero")
      bits.push(featuredShelfTitle)
    const tag = String(it.tag || "").toUpperCase()
    if (tag === "GAMES" || tag === "WEB" || tag === "MEDIA" || tag === "TOOLS")
      bits.push(tag)
    if (it.meta && String(it.meta).length && String(it.meta) !== String(it.id))
      bits.push(String(it.meta))
    else if (it.id && String(it.id) !== String(it.title))
      bits.push(String(it.id))
    return bits.join(" · ")
  }

  readonly property var libraryItems: appsModel.sectionedApps
  readonly property var searchItems: appsModel.filtered

  readonly property string emptyLibraryCopy: {
    switch (libSectionId) {
    case "games":
      return "No games yet"
    case "media":
      return "No media apps yet"
    case "web":
      return "No web apps yet"
    case "apps":
      return "No apps in this section"
    default:
      return "No applications found"
    }
  }

  readonly property string padHintLine: {
    if (mediaSheet.open)
      return "◎ Media · ↑/↓ options · Ⓐ Open · Ⓑ Menu"
    if (detailsSheet.open)
      return "◎ Details · Ⓐ Open · Ⓑ Menu"
    if (ShellState.controlCenterOpen)
      return "◎ Control Center · pad moves tiles · Ⓑ Menu"
    if (ShellState.consoleSwitcherOpen)
      return "◎ Switcher · ←/→ pick · Ⓐ focus · Ⓑ Menu"
    if (ShellState.consoleExitConfirmOpen)
      return "◎ Return to Desktop? · Ⓐ confirm · Ⓑ Menu"
    if (focusZone === "chrome")
      return "◎ Menu · Library (all apps) · Search · Control Center · Ⓐ open"
    if (focusZone === "hero")
      return "◎ Featured · Ⓐ Open · Ⓨ Details · ↓ shelves · Ⓑ Menu"
    if (focusZone === "shelf") {
      if (currentShelfId === "jump")
        return "◎ Jump Back In · ←/→ · Ⓐ Open · Ⓨ Details · ✕ remove"
      return "◎ " + (currentShelf ? currentShelf.title : "Shelf")
          + " · ←/→ · Ⓐ Open · ↑/↓ · Library for all apps"
    }
    if (focusZone === "libSection")
      return "◎ Library (all apps) · ←/→ filter · ↓ cards · Ⓑ Home"
    if (focusZone === "library")
      return "◎ Library · ←/→ · Ⓐ Open · Ⓑ Home"
    if (focusZone === "search")
      return searchQuery.length
          ? "◎ Results · ←/→ · Ⓐ Open · Ⓑ Menu"
          : "◎ Shortcuts · ←/→ · type to search · Ⓑ Home"
    return "◎ Ⓐ Open · Ⓑ Menu · Ⓨ Details"
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
    detailsSheet.options = opts
    detailsSheet.openSheet()
  }

  function activateItem(item) {
    if (!item)
      return
    if (item.kind === "media") {
      openMediaSheet()
      return
    }
    library.activate(item)
  }

  function shelfItemsAt(i) {
    const s = homeShelves[i]
    return s && s.items ? s.items : []
  }

  function clampCardIndex() {
    const items = shelfItemsAt(shelfIndex)
    if (!items.length) {
      cardIndex = 0
      return
    }
    cardIndex = Math.max(0, Math.min(cardIndex, items.length - 1))
  }

  function ensureActiveShelfVisible() {
    if (tab !== "home" || !homeFlick)
      return
    // Approximate scroll so the active shelf sits near the top of the shelf pane.
    let y = 0
    for (let i = 0; i < shelfIndex && i < homeShelves.length; i++) {
      const s = homeShelves[i]
      const h = Math.round((s.cardHeight || 120) * 0.72) + 36
      y += h + Theme.spaceMd
    }
    const maxY = Math.max(0, homeFlick.contentHeight - homeFlick.height)
    homeFlick.contentY = Math.max(0, Math.min(maxY, y - 8))
  }

  onShelfIndexChanged: Qt.callLater(ensureActiveShelfVisible)
  onFocusZoneChanged: {
    if (focusZone === "shelf" || focusZone === "hero")
      Qt.callLater(ensureActiveShelfVisible)
  }

  function removeJumpFocused() {
    if (!library.games.length)
      return
    const i = Math.max(0, Math.min(cardIndex, library.games.length - 1))
    const item = library.games[i]
    if (!item)
      return
    if (library.removeRecent(item.id))
      clampCardIndex()
  }

  function goHomeShelves() {
    tab = "home"
    focusZone = "hero"
    heroAction = 0
    barSlot = 0
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
      else if (focusZone === "shelf" && currentShelfId === "jump")
        root.removeJumpFocused()
      return
    }
    if (b === "y") {
      if (focusZone === "hero" || focusZone === "shelf")
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
      if (barSlot === 3) {
        ShellState.toggleControlCenter()
        return
      }
      if (barSlot === 0) {
        goHomeShelves()
        return
      }
      if (barSlot === 1) {
        tab = "library"
        focusZone = "libSection"
        libraryIndex = 0
        return
      }
      if (barSlot === 2) {
        tab = "search"
        focusZone = "search"
        libraryIndex = 0
      }
      return
    }
    if (focusZone === "hero") {
      if (heroAction === 0)
        activateItem(featured)
      else
        openDetailsSheet()
      return
    }
    if (focusZone === "shelf") {
      const items = shelfItemsAt(shelfIndex)
      if (items.length)
        activateItem(items[Math.max(0, Math.min(cardIndex, items.length - 1))])
      return
    }
    if (focusZone === "libSection") {
      focusZone = "library"
      libraryIndex = 0
      return
    }
    if (focusZone === "library") {
      if (libraryItems.length)
        activateItem(libraryItems[libraryIndex])
      return
    }
    if (focusZone === "search") {
      if (searchItems.length)
        activateItem(searchItems[libraryIndex])
    }
  }

  function moveHorizontal(delta) {
    if (mediaSheet.open || detailsSheet.open)
      return
    if (ShellState.consoleSwitcherOpen) {
      switcher.moveFocus(delta)
      return
    }
    if (focusZone === "chrome") {
      barSlot = Math.max(0, Math.min(3, barSlot + delta))
      return
    }
    if (focusZone === "hero") {
      heroAction = Math.max(0, Math.min(1, heroAction + delta))
      return
    }
    if (focusZone === "shelf") {
      const items = shelfItemsAt(shelfIndex)
      if (!items.length)
        return
      cardIndex = Math.max(0, Math.min(items.length - 1, cardIndex + delta))
      return
    }
    if (focusZone === "libSection") {
      libSectionIndex = Math.max(0, Math.min(libSections.length - 1, libSectionIndex + delta))
      libraryIndex = 0
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
    if (mediaSheet.open || detailsSheet.open || ShellState.consoleSwitcherOpen)
      return
    if (tab === "library") {
      if (delta < 0) {
        if (focusZone === "library")
          focusZone = "libSection"
        else
          focusZone = "chrome"
      } else {
        if (focusZone === "chrome" || focusZone === "libSection")
          focusZone = focusZone === "chrome" ? "libSection" : "library"
        else
          focusZone = "library"
      }
      return
    }
    if (tab === "search") {
      focusZone = delta < 0 ? "chrome" : "search"
      return
    }
    // Home: chrome ↔ hero ↔ shelves
    if (delta < 0) {
      if (focusZone === "shelf") {
        if (shelfIndex > 0) {
          shelfIndex--
          clampCardIndex()
        } else {
          focusZone = "hero"
        }
      } else if (focusZone === "hero") {
        focusZone = "chrome"
        barSlot = 0
      }
      return
    }
    if (focusZone === "chrome") {
      focusZone = "hero"
      return
    }
    if (focusZone === "hero") {
      focusZone = "shelf"
      shelfIndex = 0
      clampCardIndex()
      return
    }
    if (focusZone === "shelf") {
      if (shelfIndex < homeShelves.length - 1) {
        shelfIndex++
        clampCardIndex()
      }
    }
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
    if (tab === "search" && searchQuery.length) {
      searchQuery = ""
      libraryIndex = 0
      return
    }
    if (tab !== "home") {
      goHomeShelves()
      return
    }
    if (focusZone === "shelf") {
      focusZone = "hero"
      return
    }
    if (focusZone === "hero") {
      focusZone = "chrome"
      barSlot = 0
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

  function selectDestination(id) {
    root.tab = id
    if (id === "home") {
      root.focusZone = "hero"
      root.barSlot = 0
    } else if (id === "library") {
      root.focusZone = "libSection"
      root.libraryIndex = 0
      root.barSlot = 1
    } else if (id === "search") {
      root.focusZone = "search"
      root.libraryIndex = 0
      root.barSlot = 2
    }
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
      onTabSelected: id => root.selectDestination(id)
      onControlCenterRequested: ShellState.toggleControlCenter()
    }

    Item {
      Layout.fillWidth: true
      Layout.fillHeight: true

      // Home — pinned cinematic hero + scrolling shelf stack
      Item {
        id: homeRoot
        anchors.fill: parent
        visible: root.tab === "home"

        ConsoleHero {
          id: homeHero
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          bandHeight: Math.max(280, Math.min(420, homeRoot.height * 0.5))
          item: root.featured
          metaLine: root.featuredMetaLine
          bandFocused: root.focusZone === "hero"
          focusedAction: root.focusZone === "hero" ? root.heroAction : -1
          onResumeRequested: root.activateItem(root.featured)
          onDetailsRequested: root.openDetailsSheet()
        }

        Flickable {
          id: homeFlick
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: homeHero.bottom
          anchors.bottom: parent.bottom
          contentWidth: width
          contentHeight: shelfCol.implicitHeight + Theme.spaceXl
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height

          ColumnLayout {
            id: shelfCol
            width: homeFlick.width
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: Theme.spaceXl
            anchors.rightMargin: Theme.spaceXl
            anchors.topMargin: Theme.spaceMd
            spacing: Theme.spaceMd

            Text {
              visible: root.currentShelfId === "jump" && !library.games.length
                  && root.focusZone === "shelf" && root.shelfIndex === 0
              text: "Nothing to jump back into yet — open something from Apps or Library."
              color: Theme.textMute
              font.family: Theme.fontFamily
              font.pixelSize: Theme.fontSize
              Layout.fillWidth: true
              wrapMode: Text.WordWrap
            }

            Repeater {
              id: shelfRepeater
              model: root.homeShelves

              ConsoleShelf {
                id: shelfItem
                required property var modelData
                required property int index
                Layout.fillWidth: true
                title: modelData.title
                items: modelData.items
                chromeStyle: !!modelData.chromeStyle
                allowRemove: !!modelData.allowRemove
                focusScale: true
                cardWidth: modelData.cardWidth
                cardHeight: modelData.cardHeight
                peekScale: 0.72
                shelfActive: root.shelfIndex === index
                    && (root.focusZone === "shelf" || root.focusZone === "hero")
                focusedIndex: root.focusZone === "shelf" && root.shelfIndex === index
                    ? root.cardIndex
                    : -1
                onFocusRequested: i => {
                  root.focusZone = "shelf"
                  root.shelfIndex = index
                  root.cardIndex = i
                }
                onItemActivated: item => root.activateItem(item)
                onRemoveRequested: item => {
                  if (library.removeRecent(item.id))
                    root.clampCardIndex()
                }
              }
            }
          }
        }
      }

      // Library destination
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

        Row {
          spacing: Theme.spaceSm
          Repeater {
            model: root.libSections
            Rectangle {
              required property var modelData
              required property int index
              width: secLbl.implicitWidth + 22
              height: 32
              radius: Theme.radiusPill
              color: root.libSectionId === modelData.id
                  ? Theme.accent
                  : (root.focusZone === "libSection" && root.libSectionIndex === index
                      ? Theme.chromeHover
                      : Theme.elevatedFill)
              border.width: root.focusZone === "libSection" && root.libSectionIndex === index
                  && root.libSectionId !== modelData.id ? 1 : 0
              border.color: Theme.accent
              scale: root.focusZone === "libSection" && root.libSectionIndex === index ? 1.06 : 1
              Behavior on scale {
                NumberAnimation {
                  duration: 180
                  easing.type: Easing.OutCubic
                }
              }
              Text {
                id: secLbl
                anchors.centerIn: parent
                text: modelData.label
                color: root.libSectionId === modelData.id ? "#ffffff" : Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize + 1
                font.weight: root.libSectionId === modelData.id ? Font.DemiBold : Font.Normal
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.libSectionIndex = index
                  root.focusZone = "libSection"
                  root.libraryIndex = 0
                }
              }
            }
          }
        }

        Text {
          visible: !libraryItems.length
          text: root.emptyLibraryCopy
          color: Theme.textMute
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSize + 2
        }

        ConsoleShelf {
          Layout.fillWidth: true
          visible: libraryItems.length > 0
          title: ""
          items: libraryItems
          chromeStyle: true
          focusScale: true
          shelfActive: root.focusZone === "library"
          focusedIndex: root.focusZone === "library" ? root.libraryIndex : -1
          cardWidth: 168
          cardHeight: 112
          peekScale: 1
          onFocusRequested: i => {
            root.focusZone = "library"
            root.libraryIndex = i
          }
          onItemActivated: item => root.activateItem(item)
        }

        Item { Layout.fillHeight: true }
      }

      // Search destination
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
          Layout.preferredHeight: 52
          radius: Theme.radiusLg
          color: Theme.elevatedFill
          border.width: root.focusZone === "search" && !searchItems.length ? 2 : 1
          border.color: root.focusZone === "search" ? Theme.accent : Theme.chromeBorder

          Text {
            anchors.fill: parent
            anchors.margins: Theme.spaceMd
            verticalAlignment: Text.AlignVCenter
            text: root.searchQuery.length ? root.searchQuery : "Type to search apps, settings, and actions…"
            color: root.searchQuery.length ? Theme.text : Theme.textMute
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize + 4
            elide: Text.ElideRight
          }
        }

        Text {
          visible: root.searchQuery.length > 0 && !searchItems.length
          text: "No apps, settings, or actions match."
          color: Theme.textMute
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSize + 2
        }

        ConsoleShelf {
          Layout.fillWidth: true
          visible: searchItems.length > 0
          title: root.searchQuery.length ? "Results" : "Shortcuts"
          items: searchItems
          chromeStyle: true
          focusScale: true
          shelfActive: root.focusZone === "search"
          focusedIndex: root.focusZone === "search" ? root.libraryIndex : -1
          cardWidth: 168
          cardHeight: 112
          peekScale: 1
          onFocusRequested: i => {
            root.focusZone = "search"
            root.libraryIndex = i
          }
          onItemActivated: item => root.activateItem(item)
        }

        Item { Layout.fillHeight: true }
      }
    }

    ConsoleFooter {
      Layout.fillWidth: true
      hint: library.statusHint
      contextLine: root.padHintLine
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
      } else if (focusZone === "shelf" && currentShelfId === "jump") {
        root.removeJumpFocused()
        event.accepted = true
      }
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
