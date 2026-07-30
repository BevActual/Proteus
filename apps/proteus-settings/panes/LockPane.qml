import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import "../shared"
import "../kit"

// Appearance → Lock screen — Kind hub parity with Background + applet gallery.
ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: Theme.spaceMd

  Component.onCompleted: Config.ensureDomainHydrated()

  property string lockBrowseKind: Config.lockBackgroundMode === "match" ? "match" : Config.lockBackgroundMode
  property string lockColorDraft: Config.lockWallpaperColor
  // Widgets are edited on the lock screen (long-press Customize), not here.

  readonly property int wallpaperFillMode: {
    switch (Background.lockEffectiveFillMode) {
    case "fit":
      return Image.PreserveAspectFit
    case "stretch":
      return Image.Stretch
    case "center":
      return Image.Pad
    default:
      return Image.PreserveAspectCrop
    }
  }

  function localPathFromUrl(url) {
    let s = String(url)
    if (s.startsWith("file://"))
      s = s.slice(7)
    try {
      return decodeURIComponent(s)
    } catch (e) {
      return s
    }
  }

  onVisibleChanged: {
    if (visible) {
      root.lockColorDraft = Config.lockWallpaperColor
      root.lockBrowseKind = Config.lockBackgroundMode || "match"
      Config.ensureDailySources()
      Widgets.ensureLockClockWidget()
      Config.ensureWallpaperAlbums()
      if (root.lockBrowseKind === "image")
        Config.scanWallpaperFolder()
    }
  }

  FileDialog {
    id: lockImageFileDialog
    title: "Choose lock screen image"
    nameFilters: ["Images (*.png *.jpg *.jpeg *.webp *.bmp)", "All files (*)"]
    onAccepted: Config.setLockCustomWallpaper(root.localPathFromUrl(selectedFile))
  }

  FileDialog {
    id: lockVideoFileDialog
    title: "Choose lock screen video"
    nameFilters: ["Videos (*.mp4 *.webm *.mkv *.mov)", "All files (*)"]
    onAccepted: Config.setLockWallpaperVideo(root.localPathFromUrl(selectedFile))
  }

  // Wallpaper preview only — widgets live on the lock screen Customize flow.
  Rectangle {
    id: lockPreview
    Layout.fillWidth: true
    Layout.maximumWidth: 480
    Layout.preferredHeight: 200
    radius: Theme.radiusLg
    color: {
      if (root.lockBrowseKind === "color" || (root.lockBrowseKind === "match" && Config.wallpaperKind === "color"))
        return Background.lockBackdropColor
      return Theme.bgPanel
    }
    clip: true

    Image {
      visible: (root.lockBrowseKind === "image" || root.lockBrowseKind === "daily" || root.lockBrowseKind === "match")
          && Background.lockBackdropKind === "image"
      anchors.fill: parent
      source: Background.lockActiveImagePath.length ? ("file://" + Background.lockActiveImagePath) : ""
      fillMode: root.wallpaperFillMode
      asynchronous: true
      cache: false
    }

    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, Background.lockDimClamped)
    }

    Text {
      anchors.centerIn: parent
      visible: root.lockBrowseKind === "video" || root.lockBrowseKind === "reactive"
          || (root.lockBrowseKind === "match" && (Config.wallpaperKind === "video" || Config.wallpaperKind === "reactive"))
      text: root.lockBrowseKind === "reactive" || (root.lockBrowseKind === "match" && Config.wallpaperKind === "reactive")
          ? ("Animated · " + Background.lockBackdropReactiveId)
          : "Video backdrop"
      color: Qt.rgba(1, 1, 1, 0.7)
      font.family: Theme.fontFamily
      font.pixelSize: 13
    }

    Text {
      anchors.left: parent.left
      anchors.bottom: parent.bottom
      anchors.margins: 10
      z: 3
      text: Background.lockBackgroundSummary
      color: Theme.text
      font.family: Theme.fontFamily
      font.pixelSize: 11
      style: Text.Outline
      styleColor: "#80000000"
    }
  }

  Text {
    Layout.fillWidth: true
    Layout.maximumWidth: 480
    text: "Add and arrange widgets on the lock screen: Super+L, then long-press → Customize. Settings only picks the lock wallpaper and dim."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 11
    wrapMode: Text.WordWrap
  }

  SettingsKindPicker {
    model: Background.lockBackgroundModes
    browseKind: root.lockBrowseKind
    appliedKind: Config.lockBackgroundMode
    hideBannerForKind: "match"
    bannerText: "Browsing " + root.lockBrowseKind + " — lock stays on " + Config.lockBackgroundMode + " until you pick one below."
    hintForId: function (id) {
      if (id === "match")
        return "Follow the desktop background"
      if (id === "color")
        return "Solid lock color"
      if (id === "image")
        return "Still images and slideshow"
      if (id === "daily")
        return "Bing, Unsplash, or a custom feed"
      if (id === "video")
        return "Silent looping video"
      return "Built-in animated backgrounds"
    }
    onActivated: id => {
      root.lockBrowseKind = id
      if (id === "match" || id === "color" || id === "daily" || id === "reactive")
        Config.setLockBackgroundMode(id)
      if (id === "image")
        Config.scanWallpaperFolder()
    }
  }

  // —— Color ——
  ColumnLayout {
    visible: root.lockBrowseKind === "color"
    Layout.fillWidth: true
    spacing: Theme.spaceMd
    SettingsColorPresetGroup {
      model: Background.wallpaperColors
      selectedColor: Config.lockWallpaperColor
      selectionActive: Config.lockBackgroundMode === "color"
      graphHex: Config.lockWallpaperColor
      debounceMs: 80
      onPresetClicked: color => {
        root.lockColorDraft = color
        Config.setLockWallpaperColor(color)
        root.lockBrowseKind = "color"
      }
      onCustomHexEdited: h => {
        root.lockColorDraft = h
      }
      onCustomHexCommitted: h => {
        if (Config.setLockWallpaperColor(h))
          root.lockBrowseKind = "color"
      }
    }
  }

  // —— Image ——
  ColumnLayout {
    visible: root.lockBrowseKind === "image"
    Layout.fillWidth: true
    spacing: Theme.spaceMd
    SettingsGroup {
      title: "Built-in"
      Item {
        Layout.fillWidth: true
        Layout.preferredHeight: lockStockFlow.implicitHeight + Theme.spaceMd * 2
        Flow {
          id: lockStockFlow
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: Theme.spaceMd
          spacing: Theme.spaceSm
          Repeater {
            model: Background.wallpapers
            Rectangle {
              required property var modelData
              width: 112
              height: 72
              radius: Theme.radiusMd
              color: Theme.bgHover
              border.width: Config.lockWallpaperId === modelData.id && Config.lockBackgroundMode === "image" ? 2 : 0
              border.color: Theme.accent
              clip: true
              Image {
                id: lockStockImg
                anchors.fill: parent
                anchors.margins: Config.lockWallpaperId === modelData.id ? 2 : 0
                source: "file://" + modelData.path
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
              }
              Rectangle {
                visible: lockStockImg.status === Image.Error || lockStockImg.status === Image.Null
                anchors.fill: parent
                color: Theme.bgElevated
                Text {
                  anchors.centerIn: parent
                  text: "Missing"
                  color: Theme.textMute
                  font.family: Theme.fontFamily
                  font.pixelSize: 10
                }
              }
              Text {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.margins: 6
                text: modelData.label
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 10
                style: Text.Outline
                styleColor: "#80000000"
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  Config.setLockWallpaper(modelData.id)
                  root.lockBrowseKind = "image"
                }
              }
            }
          }
        }
      }
    }
    SettingsGroup {
      title: "Albums"
      Text {
        visible: Background.wallpaperAlbumsList.length === 0
        Layout.fillWidth: true
        Layout.leftMargin: Theme.spaceMd
        Layout.rightMargin: Theme.spaceMd
        Layout.topMargin: Theme.spaceSm
        Layout.bottomMargin: Theme.spaceSm
        text: "No albums yet. Add folders under Appearance → Background."
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: 12
        wrapMode: Text.WordWrap
      }
      Repeater {
        model: Background.wallpaperAlbumsList
        SettingsFormRow {
          required property var modelData
          required property int index
          label: modelData.label || "Album"
          hint: modelData.path || ""
          interactive: true
          showSeparator: index < Background.wallpaperAlbumsList.length - 1
          onActivated: {
            Config.setLockWallpaperAlbum(modelData.id)
            root.lockBrowseKind = "image"
          }
          Text {
            visible: Config.lockWallpaperAlbumId === modelData.id || (!String(Config.lockWallpaperAlbumId || "").length && index === 0)
            text: "✓"
            color: Theme.accent
            font.pixelSize: 14
          }
        }
      }
    }
    SettingsGroup {
      title: "Slideshow"
      SettingsFormRow {
        label: "Slideshow"
        hint: Config.lockWallpaperSlideshow ? (Config.lockWallpaperSlideshowSecs + "s") : "Off"
        Switch {
          checked: Config.lockWallpaperSlideshow
          onToggled: {
            Config.setLockWallpaperSlideshow(checked)
            root.lockBrowseKind = "image"
          }
        }
      }
      SettingsFormRow {
        visible: Config.lockWallpaperSlideshow
        label: "Interval"
        hint: Config.lockWallpaperSlideshowSecs + " seconds"
        Slider {
          from: 5
          to: 300
          stepSize: 5
          value: Config.lockWallpaperSlideshowSecs
          onMoved: Config.setLockWallpaperSlideshowSecs(Math.round(value))
        }
      }
      SettingsFormRow {
        visible: Config.lockWallpaperSlideshow
        label: "Shuffle"
        showSeparator: false
        Switch {
          checked: Config.lockWallpaperShuffle
          onToggled: Config.setLockWallpaperShuffle(checked)
        }
      }
    }
    SettingsGroup {
      title: "Source"
      SettingsFormRow {
        label: "Choose image…"
        interactive: true
        showSeparator: Config.lockWallpaperId === "custom"
        onActivated: lockImageFileDialog.open()
        Text {
          text: "›"
          color: Theme.textMute
          font.pixelSize: 16
        }
      }
      SettingsFormRow {
        visible: Config.lockWallpaperId === "custom"
        label: "Custom"
        hint: Config.lockWallpaperCustomPath
        showSeparator: false
      }
    }
    SettingsGroup {
      title: "Fit"
      Repeater {
        model: [
          { id: "fill", label: "Fill", hint: "Crop to cover" },
          { id: "fit", label: "Fit", hint: "Letterbox" },
          { id: "stretch", label: "Stretch", hint: "Ignore aspect" },
          { id: "center", label: "Center", hint: "No scale" }
        ]
        SettingsFormRow {
          required property var modelData
          required property int index
          label: modelData.label
          hint: modelData.hint
          interactive: true
          showSeparator: index < 3
          onActivated: {
            Config.setLockWallpaperMode(modelData.id)
            root.lockBrowseKind = "image"
          }
          Text {
            visible: Config.lockWallpaperMode === modelData.id
            text: "✓"
            color: Theme.accent
            font.pixelSize: 14
          }
        }
      }
    }
  }

  // —— Daily ——
  ColumnLayout {
    visible: root.lockBrowseKind === "daily"
    Layout.fillWidth: true
    spacing: Theme.spaceMd
    SettingsGroup {
      title: "Daily source"
      Text {
        Layout.fillWidth: true
        Layout.leftMargin: Theme.spaceMd
        Layout.rightMargin: Theme.spaceMd
        Layout.topMargin: Theme.spaceSm
        text: Background.wallpaperDailySourcesList.length
            ? "Uses feeds from Background → Daily. Lock keeps its own cache."
            : "Add a feed under Appearance → Background → Daily first."
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: 11
        wrapMode: Text.WordWrap
      }
      Repeater {
        model: Background.wallpaperDailySourcesList
        SettingsFormRow {
          required property var modelData
          label: modelData.label || modelData.provider || "Source"
          hint: String(modelData.provider || "")
          interactive: true
          showSeparator: true
          onActivated: {
            Config.setLockDailySource(modelData.id)
            root.lockBrowseKind = "daily"
          }
          Text {
            text: (Config.lockDailySourceId === modelData.id
                    || (!String(Config.lockDailySourceId || "").length
                        && Background.lockDailySourceResolved
                        && String(Background.lockDailySourceResolved.id) === String(modelData.id)))
                ? "●" : "○"
            color: Theme.accent
            font.pixelSize: 12
          }
        }
      }
      SettingsFormRow {
        label: Background.lockDailyFetching ? "Fetching…" : "Fetch now"
        hint: Background.lockDailyError.length ? Background.lockDailyError
            : (Config.lockDailyPath.length ? ("Cached · " + Config.lockDailyPath) : "Download into lock daily cache")
        interactive: !Background.lockDailyFetching && Background.wallpaperDailySourcesList.length > 0
        showSeparator: false
        onActivated: {
          Config.refreshLockDailyWallpaper()
          root.lockBrowseKind = "daily"
        }
      }
    }
  }

  // —— Video ——
  ColumnLayout {
    visible: root.lockBrowseKind === "video"
    Layout.fillWidth: true
    spacing: Theme.spaceMd
    SettingsGroup {
      title: "Video"
      SettingsFormRow {
        label: "Choose video…"
        hint: Config.lockWallpaperVideoPath.length ? Config.lockWallpaperVideoPath : "Silent loop on the lock screen"
        interactive: true
        showSeparator: false
        onActivated: lockVideoFileDialog.open()
        Text {
          text: "›"
          color: Theme.textMute
          font.pixelSize: 16
        }
      }
    }
  }

  // —— Animated ——
  ColumnLayout {
    visible: root.lockBrowseKind === "reactive"
    Layout.fillWidth: true
    spacing: Theme.spaceMd
    SettingsGroup {
      title: "Style"
      Repeater {
        model: Background.wallpaperReactives
        SettingsFormRow {
          required property var modelData
          required property int index
          label: modelData.label
          hint: modelData.hint || ""
          interactive: true
          showSeparator: index < Background.wallpaperReactives.length - 1
          onActivated: {
            Config.setLockWallpaperReactive(modelData.id)
            root.lockBrowseKind = "reactive"
          }
          Text {
            visible: Config.lockWallpaperReactiveId === modelData.id && Config.lockBackgroundMode === "reactive"
            text: "✓"
            color: Theme.accent
            font.pixelSize: 14
          }
        }
      }
    }
  }

  SettingsGroup {
    title: "Appearance"
    SettingsFormRow {
      label: "Dim"
      hint: Math.round(Background.lockDimClamped * 100) + "%"
      showSeparator: false
      Slider {
        from: 0
        to: 0.75
        stepSize: 0.05
        value: Background.lockDimClamped
        onMoved: Config.setLockDim(value)
      }
    }
  }

  SettingsGroup {
    title: "Widgets"
    Text {
      Layout.fillWidth: true
      Layout.leftMargin: Theme.spaceMd
      Layout.rightMargin: Theme.spaceMd
      Layout.topMargin: Theme.spaceSm
      Layout.bottomMargin: Theme.spaceMd
      text: "Not configured here. Lock the session (Super+L), long-press the wallpaper, then use Add Widget / drag / Done — same idea as customizing on the lock screen itself."
      color: Theme.textMute
      font.family: Theme.fontFamily
      font.pixelSize: 11
      wrapMode: Text.WordWrap
    }
  }

  SettingsGroup {
    title: "Session"
    SettingsFormRow {
      label: "Lock on session start"
      hint: "Show lock screen after login / cold boot"
      showSeparator: false
      Switch {
        checked: Config.lockOnSessionStart
        onToggled: Config.setLockOnSessionStart(checked)
      }
    }
  }
}
