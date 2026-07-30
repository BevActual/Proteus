import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import "../shared"
import "../kit"

// Leaf UI for StylePane; `host` is the StylePane root (shared drafts / helpers).
ColumnLayout {
  property Item host
    id: bgLeaf
    width: parent ? parent.width : implicitWidth
    spacing: Theme.spaceMd

    function syncDraft() {
      if (!host)
        return
      Config.ensureDomainHydrated()
      host.wallpaperColorDraft = Config.wallpaperColor
      host.browseKind = Config.wallpaperKind
      Config.ensureWallpaperAlbums()
      Config.scanWallpaperFolder()
    }
    onHostChanged: syncDraft()
    onVisibleChanged: {
      if (visible)
        syncDraft()
    }

    FileDialog {
      id: imageFileDialog
      title: "Choose background image"
      nameFilters: ["Images (*.png *.jpg *.jpeg *.webp *.bmp *.gif)", "All files (*)"]
      onAccepted: Config.setCustomWallpaper(host.localPathFromUrl(selectedFile))
    }

    FolderDialog {
      id: folderDialog
      title: "Add album folder"
      onAccepted: Config.addWallpaperAlbum(host.localPathFromUrl(selectedFolder))
    }

    FileDialog {
      id: videoFileDialog
      title: "Choose looping video"
      nameFilters: ["Videos (*.mp4 *.webm *.mkv *.mov)", "All files (*)"]
      onAccepted: Config.setWallpaperVideo(host.localPathFromUrl(selectedFile))
    }

    // Preview above Kind — same order as Lock screen.
    Rectangle {
      Layout.fillWidth: true
      Layout.maximumWidth: 480
      Layout.preferredHeight: 200
      radius: Theme.radiusLg
      color: host.browseKind === "color" ? Config.wallpaperColor : Theme.bgPanel
      clip: true

      Image {
        visible: host.browseKind === "image" || host.browseKind === "daily"
        anchors.fill: parent
        source: {
          if (host.browseKind === "daily" && Config.wallpaperDailyPath.length)
            return "file://" + Config.wallpaperDailyPath
          if (host.browseKind === "image")
            return "file://" + Background.wallpaperPath
          return ""
        }
        fillMode: host.wallpaperFillMode
        asynchronous: true
        cache: false
      }

      Text {
        visible: host.browseKind === "daily" && !Config.wallpaperDailyPath.length
        anchors.centerIn: parent
        text: "Pick a source and fetch"
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: 12
      }

      Rectangle {
        visible: host.browseKind === "video"
        anchors.fill: parent
        color: Theme.bgElevated
        Column {
          anchors.centerIn: parent
          spacing: 6
          Text {
            text: "Video loop"
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            anchors.horizontalCenter: parent.horizontalCenter
          }
          Text {
            text: Background.wallpaperVideoBasename.length ? Background.wallpaperVideoBasename : "No file chosen"
            color: Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: 11
            anchors.horizontalCenter: parent.horizontalCenter
          }
        }
      }

      Rectangle {
        visible: host.browseKind === "reactive"
        anchors.fill: parent
        gradient: Gradient {
          GradientStop {
            position: 0.0
            color: Theme.bg
          }
          GradientStop {
            position: 0.55
            color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35)
          }
          GradientStop {
            position: 1.0
            color: Theme.bgElevated
          }
        }
        Text {
          anchors.centerIn: parent
          text: Background.wallpaperReactiveLabel
          color: Theme.text
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSize
        }
      }
    }

    SettingsKindPicker {
      model: Background.wallpaperKinds
      browseKind: host.browseKind
      appliedKind: Config.wallpaperKind
      bannerText: "Browsing " + host.browseKind + " — desktop stays on " + Config.wallpaperKind + " until you pick one below."
      hintForId: function (id) {
        if (id === "color")
          return "Solid desktop color"
        if (id === "image")
          return "Still images and slideshow"
        if (id === "daily")
          return "Bing, Unsplash, or a custom feed"
        if (id === "video")
          return "Silent looping video"
        return "Built-in animated backgrounds"
      }
      onActivated: id => {
        host.browseKind = id
        if (id === "image")
          Config.scanWallpaperFolder()
      }
    }

    // —— Color body ——
    ColumnLayout {
      visible: host.browseKind === "color"
      Layout.fillWidth: true
      spacing: Theme.spaceMd

      SettingsColorPresetGroup {
        model: Background.wallpaperColors
        selectedColor: Config.wallpaperColor
        selectionActive: Config.wallpaperKind === "color"
        graphHex: Config.wallpaperColor
        debounceMs: 80
        onPresetClicked: color => {
          host.wallpaperColorDraft = color
          Config.setWallpaperColor(color)
        }
        onCustomHexEdited: h => {
          host.wallpaperColorDraft = h
        }
        onCustomHexCommitted: h => {
          if (Config.setWallpaperColor(h))
            host.wallpaperColorDraft = Config.wallpaperColor
        }
      }
    }

    // —— Daily body ——
    ColumnLayout {
      visible: host.browseKind === "daily"
      Layout.fillWidth: true
      spacing: Theme.spaceMd

      Connections {
        target: Config
        function onSettingsReadyChanged() {
          if (Config.settingsReady)
            Config.ensureDailySources()
        }
      }

      Component.onCompleted: {
        if (Config.settingsReady)
          Config.ensureDailySources()
      }

      Connections {
        target: Config
        function onWallpaperDailySourceIdChanged() {
          const src = Background.activeDailySource
          dailyNameInput.text = src ? (src.label || "") : ""
          dailyUrlInput.text = src ? (src.url || "") : ""
          dailyKeyInput.text = src ? (src.apiKey || "") : ""
        }
        function onWallpaperDailySourcesChanged() {
          const src = Background.activeDailySource
          if (!dailyNameInput.activeFocus)
            dailyNameInput.text = src ? (src.label || "") : ""
          if (!dailyUrlInput.activeFocus)
            dailyUrlInput.text = src ? (src.url || "") : ""
          if (!dailyKeyInput.activeFocus)
            dailyKeyInput.text = src ? (src.apiKey || "") : ""
        }
      }

      SettingsGroup {
        title: "Sources"
        SettingsFormRow {
          label: "Add Bing…"
          hint: "Windows-style daily photo · no API key"
          interactive: true
          showSeparator: true
          onActivated: Config.addDailySource("bing")
        }
        SettingsFormRow {
          label: "Add Unsplash…"
          hint: "Random landscape · needs Access Key"
          interactive: true
          showSeparator: true
          onActivated: Config.addDailySource("unsplash")
        }
        SettingsFormRow {
          label: "Add custom feed…"
          hint: "Your URL · optional API key / auth"
          interactive: true
          showSeparator: Background.wallpaperDailySourcesList.length > 0
          onActivated: Config.addDailySource("custom")
        }
        Repeater {
          model: Background.wallpaperDailySourcesList
          SettingsFormRow {
            required property var modelData
            required property int index
            label: modelData.label || "Source"
            hint: {
              const p = String(modelData.provider || "")
              if (p === "bing")
                return "Bing · " + (modelData.market || "en-US")
              if (p === "unsplash")
                return "Unsplash"
              return "Custom · " + (modelData.url || "no URL")
            }
            interactive: true
            showSeparator: index < Background.wallpaperDailySourcesList.length - 1
            onActivated: Config.setDailySource(modelData.id, true)
            Row {
              spacing: 8
              Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: Config.wallpaperDailySourceId === modelData.id
                    || (Background.activeDailySource && String(Background.activeDailySource.id) === String(modelData.id))
                    || (!String(Config.wallpaperDailySourceId || "").length && index === 0)
                text: "✓"
                color: Theme.accent
                font.pixelSize: 14
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: Background.wallpaperDailySourcesList.length > 1
                text: "Remove"
                color: Theme.danger
                font.family: Theme.fontFamily
                font.pixelSize: 12
                MouseArea {
                  anchors.fill: parent
                  anchors.margins: -4
                  cursorShape: Qt.PointingHandCursor
                  onClicked: Config.removeDailySource(modelData.id)
                }
              }
            }
          }
        }
      }

      SettingsGroup {
        title: "Configure"
        visible: Background.activeDailySource !== null
        SettingsFormRow {
          label: "Name"
          hint: "Shown in the sources list"
          showSeparator: true
        }
        Item {
          Layout.fillWidth: true
          Layout.preferredHeight: 36
          Rectangle {
            anchors.fill: parent
            anchors.leftMargin: Theme.spaceMd
            anchors.rightMargin: Theme.spaceMd
            anchors.topMargin: 2
            anchors.bottomMargin: 2
            radius: Theme.radiusSm
            color: Theme.bgHover
            TextInput {
              id: dailyNameInput
              anchors.fill: parent
              anchors.leftMargin: 10
              anchors.rightMargin: 10
              color: Theme.text
              font.family: Theme.fontFamily
              font.pixelSize: 12
              verticalAlignment: TextInput.AlignVCenter
              clip: true
              Component.onCompleted: text = Background.activeDailySource ? (Background.activeDailySource.label || "") : ""
              onEditingFinished: {
                if (Background.activeDailySource)
                  Config.renameDailySource(Background.activeDailySource.id, text)
              }
            }
          }
        }
        Text {
          Layout.fillWidth: true
          Layout.leftMargin: Theme.spaceMd
          Layout.rightMargin: Theme.spaceMd
          Layout.topMargin: Theme.spaceSm
          text: {
            const p = Background.activeDailySource ? String(Background.activeDailySource.provider || "") : ""
            for (let i = 0; i < Background.wallpaperDailyProviders.length; i++) {
              if (Background.wallpaperDailyProviders[i].id === p)
                return Background.wallpaperDailyProviders[i].hint
            }
            return "Feed type"
          }
          color: Theme.textMute
          font.family: Theme.fontFamily
          font.pixelSize: 11
          wrapMode: Text.WordWrap
        }
        Item {
          Layout.fillWidth: true
          Layout.preferredHeight: 40
          SettingsSegmented {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Theme.spaceMd
            anchors.rightMargin: Theme.spaceMd
            options: Background.wallpaperDailyProviders
            selected: Background.activeDailySource ? String(Background.activeDailySource.provider || "bing") : "bing"
            onActivated: id => Config.setWallpaperDailyProvider(id)
          }
        }
        SettingsFormRow {
          visible: Background.activeDailySource && Background.activeDailySource.provider === "bing"
          label: "Market"
          hint: "Bing locale, e.g. en-US · en-GB"
          showSeparator: true
          TextInput {
            Layout.preferredWidth: 88
            Layout.preferredHeight: 28
            text: Background.activeDailySource ? (Background.activeDailySource.market || "en-US") : "en-US"
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: 12
            verticalAlignment: TextInput.AlignVCenter
            clip: true
            onEditingFinished: Config.setWallpaperDailyMarket(text)
          }
        }
        SettingsFormRow {
          visible: Background.activeDailySource
              && (Background.activeDailySource.provider === "custom" || Background.activeDailySource.provider === "unsplash")
          label: "Feed URL"
          hint: Background.activeDailySource && Background.activeDailySource.provider === "unsplash"
              ? "Optional override · {api_key} allowed"
              : "Image URL or JSON feed · {api_key} ok"
          showSeparator: true
        }
        Item {
          visible: Background.activeDailySource
              && (Background.activeDailySource.provider === "custom" || Background.activeDailySource.provider === "unsplash")
          Layout.fillWidth: true
          Layout.preferredHeight: 36
          Rectangle {
            anchors.fill: parent
            anchors.leftMargin: Theme.spaceMd
            anchors.rightMargin: Theme.spaceMd
            anchors.topMargin: 2
            anchors.bottomMargin: 2
            radius: Theme.radiusSm
            color: Theme.bgHover
            TextInput {
              id: dailyUrlInput
              anchors.fill: parent
              anchors.leftMargin: 10
              anchors.rightMargin: 10
              color: Theme.text
              font.family: Theme.fontFamily
              font.pixelSize: 12
              verticalAlignment: TextInput.AlignVCenter
              clip: true
              Component.onCompleted: text = Background.activeDailySource ? (Background.activeDailySource.url || "") : ""
              onEditingFinished: Config.setWallpaperDailyUrl(text)
            }
          }
        }
        SettingsFormRow {
          visible: Background.activeDailySource && Background.activeDailySource.provider === "custom"
          label: "Auth"
          hint: "How the API key is sent"
          showSeparator: true
        }
        Item {
          visible: Background.activeDailySource && Background.activeDailySource.provider === "custom"
          Layout.fillWidth: true
          Layout.preferredHeight: 40
          SettingsSegmented {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Theme.spaceMd
            anchors.rightMargin: Theme.spaceMd
            options: Background.wallpaperDailyAuthModes
            selected: Background.activeDailySource ? String(Background.activeDailySource.auth || "none") : "none"
            onActivated: id => Config.setWallpaperDailyAuth(id)
          }
        }
        SettingsFormRow {
          visible: Background.activeDailySource && Background.activeDailySource.provider !== "bing"
          label: "API key"
          hint: Background.activeDailySource && Background.activeDailySource.provider === "unsplash"
              ? "Unsplash Access Key (required)"
              : "Optional for Custom"
          showSeparator: true
        }
        Item {
          visible: Background.activeDailySource && Background.activeDailySource.provider !== "bing"
          Layout.fillWidth: true
          Layout.preferredHeight: 36
          Rectangle {
            anchors.fill: parent
            anchors.leftMargin: Theme.spaceMd
            anchors.rightMargin: Theme.spaceMd
            anchors.topMargin: 2
            anchors.bottomMargin: 2
            radius: Theme.radiusSm
            color: Theme.bgHover
            TextInput {
              id: dailyKeyInput
              anchors.fill: parent
              anchors.leftMargin: 10
              anchors.rightMargin: 10
              color: Theme.text
              font.family: Theme.fontFamily
              font.pixelSize: 12
              echoMode: TextInput.Password
              verticalAlignment: TextInput.AlignVCenter
              clip: true
              Component.onCompleted: text = Background.activeDailySource ? (Background.activeDailySource.apiKey || "") : ""
              onEditingFinished: Config.setWallpaperDailyApiKey(text)
            }
          }
        }
      }

      SettingsGroup {
        title: "Schedule"
        SettingsFormRow {
          label: "Refresh every"
          hint: Config.wallpaperDailyRefreshHours + " hour"
              + (Config.wallpaperDailyRefreshHours === 1 ? "" : "s")
          showSeparator: true
          Slider {
            Layout.preferredWidth: 120
            from: 1
            to: 24
            stepSize: 1
            value: Config.wallpaperDailyRefreshHours
            onMoved: Config.setWallpaperDailyRefreshHours(Math.round(value))
          }
        }
        SettingsFormRow {
          label: Background.wallpaperDailyFetching ? "Fetching…" : "Apply / fetch now"
          hint: Background.wallpaperDailyError.length
              ? Background.wallpaperDailyError
              : (Config.wallpaperKind === "daily"
                  ? ("Using " + Background.activeDailySourceLabel
                      + (Config.wallpaperDailyFetchedAt.length
                          ? (" · last " + Config.wallpaperDailyFetchedAt)
                          : ""))
                  : ("Fetch “" + Background.activeDailySourceLabel + "” and set desktop"))
          interactive: !Background.wallpaperDailyFetching
          showSeparator: Config.wallpaperDailyCopyright.length > 0 || Config.wallpaperDailyTitle.length > 0
          onActivated: Config.setWallpaperDaily()
          Text {
            visible: Config.wallpaperKind === "daily" && !Background.wallpaperDailyFetching
            text: "✓"
            color: Theme.accent
            font.pixelSize: 14
          }
          Text {
            visible: Background.wallpaperDailyFetching
            text: "…"
            color: Theme.textMute
            font.pixelSize: 12
          }
        }
        SettingsFormRow {
          visible: Config.wallpaperDailyTitle.length > 0 || Config.wallpaperDailyCopyright.length > 0
          label: Config.wallpaperDailyTitle.length ? Config.wallpaperDailyTitle : "Today"
          hint: Config.wallpaperDailyCopyright
          showSeparator: false
        }
      }
    }

    // —— Image body ——
    ColumnLayout {
      visible: host.browseKind === "image"
      Layout.fillWidth: true
      spacing: Theme.spaceMd

      SettingsGroup {
        title: "Built-in"
        Item {
          Layout.fillWidth: true
          Layout.preferredHeight: stockFlow.implicitHeight + Theme.spaceMd * 2
          Flow {
            id: stockFlow
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
                border.width: Config.wallpaperId === modelData.id ? 2 : 0
                border.color: Theme.accent
                clip: true
                Image {
                  id: stockImg
                  anchors.fill: parent
                  anchors.margins: Config.wallpaperId === modelData.id ? 2 : 0
                  source: "file://" + modelData.path
                  fillMode: Image.PreserveAspectCrop
                  asynchronous: true
                }
                Rectangle {
                  visible: stockImg.status === Image.Error || stockImg.status === Image.Null
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
                  onClicked: Config.setWallpaper(modelData.id)
                }
              }
            }
          }
        }
      }

      SettingsGroup {
        title: "Albums"
        SettingsFormRow {
          label: "Add album…"
          hint: "A folder of images (slideshow collection)"
          interactive: true
          showSeparator: Background.wallpaperAlbumsList.length > 0
          onActivated: folderDialog.open()
          Text {
            text: "›"
            color: Theme.textMute
            font.pixelSize: 16
          }
        }
        Text {
          visible: Background.wallpaperAlbumsList.length === 0
          Layout.fillWidth: true
          Layout.leftMargin: Theme.spaceMd
          Layout.rightMargin: Theme.spaceMd
          Layout.topMargin: Theme.spaceSm
          Layout.bottomMargin: Theme.spaceSm
          text: "No albums yet."
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
            hint: modelData.path
            interactive: true
            showSeparator: index < Background.wallpaperAlbumsList.length - 1
            onActivated: Config.setWallpaperAlbum(modelData.id)
            Row {
              spacing: 8
              Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: Config.wallpaperAlbumId === modelData.id
                    || (!Config.wallpaperAlbumId.length && index === 0)
                text: "✓"
                color: Theme.accent
                font.pixelSize: 14
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: Background.wallpaperAlbumsList.length > 1
                text: "Remove"
                color: Theme.danger
                font.family: Theme.fontFamily
                font.pixelSize: 12
                MouseArea {
                  anchors.fill: parent
                  anchors.margins: -4
                  cursorShape: Qt.PointingHandCursor
                  onClicked: Config.removeWallpaperAlbum(modelData.id)
                }
              }
            }
          }
        }
      }

      SettingsGroup {
        title: "Album images"
        SettingsFormRow {
          label: Background.activeAlbumLabel
          hint: Background.wallpaperFolderResolved.length
              ? Background.wallpaperFolderResolved
              : "No folder resolved for this album"
          showSeparator: Background.wallpaperFolderEntries.length > 0 || Background.wallpaperFolderScanning
              || (!Background.wallpaperFolderScanning && Background.wallpaperFolderResolved.length > 0)
          Text {
            visible: Background.wallpaperFolderScanning
            text: "…"
            color: Theme.textMute
            font.pixelSize: 12
          }
        }
        Text {
          visible: !Background.wallpaperFolderScanning
              && !Background.wallpaperFolderResolved.length
              && Background.wallpaperAlbumsList.length === 0
          Layout.fillWidth: true
          Layout.leftMargin: Theme.spaceMd
          Layout.rightMargin: Theme.spaceMd
          Layout.topMargin: Theme.spaceSm
          Layout.bottomMargin: Theme.spaceSm
          text: "No albums yet. Add a folder above to collect slideshow images."
          color: Theme.textMute
          font.family: Theme.fontFamily
          font.pixelSize: 12
          wrapMode: Text.WordWrap
        }
        Item {
          visible: Background.wallpaperFolderEntries.length > 0 || (!Background.wallpaperFolderScanning && Background.wallpaperFolderResolved.length > 0)
          Layout.fillWidth: true
          Layout.preferredHeight: Background.wallpaperFolderEntries.length > 0
              ? folderFlow.implicitHeight + Theme.spaceMd * 2
              : 48
          Text {
            visible: Background.wallpaperFolderEntries.length === 0 && !Background.wallpaperFolderScanning
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Theme.spaceMd
            text: "No images in this album yet. Add files to the folder or pick another album."
            color: Theme.textMute
            font.family: Theme.fontFamily
            font.pixelSize: 12
            wrapMode: Text.WordWrap
          }
          Flow {
            id: folderFlow
            visible: Background.wallpaperFolderEntries.length > 0
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Theme.spaceMd
            spacing: Theme.spaceSm
            Repeater {
              model: Background.wallpaperFolderEntries
              Rectangle {
                required property var modelData
                width: 112
                height: 72
                radius: Theme.radiusMd
                color: Theme.bgHover
                border.width: Config.wallpaperId === "custom" && Config.wallpaperCustomPath === modelData.path ? 2 : 0
                border.color: Theme.accent
                clip: true
                Image {
                  id: folderImg
                  anchors.fill: parent
                  source: "file://" + modelData.path
                  fillMode: Image.PreserveAspectCrop
                  asynchronous: true
                }
                Rectangle {
                  visible: folderImg.status === Image.Error || folderImg.status === Image.Null
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
                  onClicked: Config.setCustomWallpaper(modelData.path)
                }
              }
            }
          }
        }
      }

      SettingsGroup {
        title: "Slideshow"
        SettingsFormRow {
          label: "Slideshow"
          hint: Config.wallpaperSlideshow
              ? (Background.activeAlbumLabel + " · " + Config.wallpaperSlideshowSecs + "s")
              : "Off"
          showSeparator: Config.wallpaperSlideshow
          Switch {
            checked: Config.wallpaperSlideshow
            onToggled: Config.setWallpaperSlideshow(checked)
          }
        }
        SettingsFormRow {
          visible: Config.wallpaperSlideshow
          label: "Uses active album"
          hint: Background.activeAlbumLabel
          showSeparator: true
        }
        SettingsFormRow {
          visible: Config.wallpaperSlideshow
          label: "Interval"
          showSeparator: true
          Slider {
            Layout.preferredWidth: 120
            from: 5
            to: 300
            stepSize: 5
            value: Config.wallpaperSlideshowSecs
            onMoved: Config.setWallpaperSlideshowSecs(Math.round(value))
          }
        }
        SettingsFormRow {
          visible: Config.wallpaperSlideshow
          label: "Shuffle"
          showSeparator: Config.wallpaperSlideshow && Background.wallpaperFolderEntries.length < 2
          Switch {
            checked: Config.wallpaperShuffle
            onToggled: Config.setWallpaperShuffle(checked)
          }
        }
        SettingsFormRow {
          visible: Config.wallpaperSlideshow && Background.wallpaperFolderEntries.length < 2
          label: "Needs two or more images in the album"
          showSeparator: false
        }
      }

      SettingsGroup {
        title: "Source"
        SettingsFormRow {
          label: "Choose image"
          interactive: true
          showSeparator: Config.wallpaperId === "custom"
          onActivated: imageFileDialog.open()
          Text {
            text: "›"
            color: Theme.textMute
            font.pixelSize: 16
          }
        }
        SettingsFormRow {
          visible: Config.wallpaperId === "custom"
          label: "Clear custom"
          hint: Background.wallpaperBasename
          interactive: true
          showSeparator: false
          onActivated: Config.clearCustomWallpaper()
        }
      }

      SettingsGroup {
        title: "Fit"
        Repeater {
          model: [
            {
              id: "fill",
              label: "Fill",
              hint: "Crop to cover"
            },
            {
              id: "fit",
              label: "Fit",
              hint: "Letterbox"
            },
            {
              id: "stretch",
              label: "Stretch",
              hint: "Ignore aspect"
            },
            {
              id: "center",
              label: "Center",
              hint: "No scale"
            }
          ]
          SettingsFormRow {
            required property var modelData
            required property int index
            label: modelData.label
            hint: modelData.hint
            interactive: true
            showSeparator: index < 3
            onActivated: Config.setWallpaperMode(modelData.id)
            Text {
              visible: Config.wallpaperMode === modelData.id
              text: "✓"
              color: Theme.accent
              font.pixelSize: 14
            }
          }
        }
      }
    }

    // —— Video body ——
    ColumnLayout {
      visible: host.browseKind === "video"
      Layout.fillWidth: true
      spacing: Theme.spaceMd

      SettingsGroup {
        title: "Video"
        SettingsFormRow {
          visible: !(Config.wallpaperVideoPath && Config.wallpaperVideoPath.length)
          label: "Use sample loop"
          hint: "Silent desktop loop"
          interactive: true
          showSeparator: true
          onActivated: Config.setWallpaperVideo("/mnt/proteus/shell/assets/sample-loop.mp4")
          Text {
            text: "›"
            color: Theme.textMute
            font.pixelSize: 16
          }
        }
        SettingsFormRow {
          label: "Choose video"
          hint: Background.wallpaperVideoBasename.length ? Background.wallpaperVideoBasename : "No video selected"
          interactive: true
          showSeparator: Config.wallpaperVideoPath.length > 0
          onActivated: videoFileDialog.open()
          Text {
            text: "›"
            color: Theme.textMute
            font.pixelSize: 16
          }
        }
        SettingsFormRow {
          visible: Config.wallpaperVideoPath.length > 0
          label: "Clear"
          interactive: true
          showSeparator: false
          onActivated: Config.clearWallpaperVideo()
        }
      }
    }

    // —— Animated / reactive body ——
    ColumnLayout {
      visible: host.browseKind === "reactive"
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
            hint: modelData.hint
            interactive: true
            showSeparator: index < Background.wallpaperReactives.length - 1
            onActivated: Config.setWallpaperReactive(modelData.id)
            Text {
              visible: Config.wallpaperReactiveId === modelData.id
              text: "✓"
              color: Theme.accent
              font.pixelSize: 14
            }
          }
        }
      }
    }
  }
