import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import "../shared"
import "../kit"

// Appearance category (page id style): list of sub-settings → leaf. Navigation via page + requestGo.
ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: 12

  property string page: "style"
  signal requestGo(string id)

  readonly property bool active: page === "style" || page.startsWith("style-")

  readonly property var sections: [
    {
      key: "style-accent",
      label: "Accent & chrome"
    },
    {
      key: "style-background",
      label: "Background"
    },
    {
      key: "style-lock",
      label: "Lock screen"
    },
    {
      key: "style-font",
      label: "Font"
    }
  ]

  readonly property int wallpaperFillMode: {
    switch (Config.wallpaperMode) {
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

  property string accentHexDraft: Config.accentCustom
  property string wallpaperColorDraft: Config.wallpaperColor
  // Kind list is browse-only — does not apply until a concrete color/image/video/style is chosen
  property string browseKind: Config.wallpaperKind

  function localPathFromUrl(url) {
    let s = String(url)
    if (s.startsWith("file://"))
      s = s.slice(7)
    // URL-decode basic spaces
    try {
      return decodeURIComponent(s)
    } catch (e) {
      return s
    }
  }

  // Keep Kind browse in sync after a concrete background is applied
  Connections {
    target: Config
    function onWallpaperKindChanged() {
      root.browseKind = Config.wallpaperKind
    }
  }

  // —— Category list ——
  SettingsHubList {
    visible: root.page === "style"
    items: root.sections
    secondaryItems: [
      {
        key: "edit-settings-json",
        label: "Edit settings.json"
      }
    ]
    onActivated: key => {
      if (key === "edit-settings-json")
        Config.openSettingsJsonInEditor()
      else
        root.requestGo(key)
    }
  }

  // —— Accent leaf ——
  ColumnLayout {
    visible: root.page === "style-accent"
    Layout.fillWidth: true
    spacing: Theme.spaceLg

    onVisibleChanged: {
      if (visible)
        root.accentHexDraft = Config.accentCustom
    }

    SettingsGroup {
      title: "Chrome"

      Item {
        Layout.fillWidth: true
        Layout.preferredHeight: 48
        SettingsSegmented {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.margins: Theme.spaceSm
          options: [
            {
              id: "dark",
              label: "Dark"
            },
            {
              id: "light",
              label: "Light"
            }
          ]
          selected: Config.chromeMode
          onActivated: id => Config.setChromeMode(id)
        }
        Rectangle {
          anchors.left: parent.left
          anchors.leftMargin: Theme.spaceMd
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: 1
          color: Theme.separator
        }
      }

      SettingsFormRow {
        label: "Transparency"
        hint: Math.round(Config.chromeOpacity * 100) + "%"
        showSeparator: true
        Slider {
          Layout.preferredWidth: 140
          from: 0
          to: 1
          stepSize: 0.01
          value: Config.chromeOpacity
          onMoved: Config.setChromeOpacity(value)
        }
      }

      SettingsFormRow {
        label: "Blur"
        hint: Config.chromeBlur ? "Behind bar, dock, launcher" : "Off"
        showSeparator: false
        Switch {
          checked: Config.chromeBlur
          onToggled: Config.setChromeBlur(checked)
        }
      }
    }

    SettingsGroup {
      title: "Accent"

      Item {
        Layout.fillWidth: true
        Layout.preferredHeight: accentFlow.implicitHeight + Theme.spaceMd * 2
        Flow {
          id: accentFlow
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: Theme.spaceMd
          spacing: Theme.spaceSm
          Repeater {
            model: Config.accents
            Rectangle {
              required property var modelData
              width: 36
              height: 36
              radius: 18
              color: modelData.id === "custom" ? Config.accentColor : modelData.color
              border.width: Config.accentId === modelData.id ? 3 : 1
              border.color: Config.accentId === modelData.id ? Theme.text : Theme.separator
              Text {
                visible: modelData.id === "custom"
                anchors.centerIn: parent
                text: "+"
                color: Theme.text
                font.pixelSize: 14
                font.bold: true
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (modelData.id === "custom") {
                    root.accentHexDraft = Config.accentCustom
                    Config.setAccentCustom(Config.accentCustom)
                  } else {
                    Config.accentId = modelData.id
                  }
                }
              }
            }
          }
        }
      }

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: Theme.separator
        opacity: 0.6
      }

      Item {
        Layout.fillWidth: true
        Layout.preferredHeight: accentGraph.implicitHeight + Theme.spaceMd
        ColorGraphPicker {
          id: accentGraph
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: Theme.spaceMd
          hex: Config.accentId === "custom" ? Config.accentCustom : Config.accentColor
          onHexEdited: h => {
            root.accentHexDraft = h
            Config.setAccentCustom(h)
          }
        }
      }
    }

    SettingsGroup {
      title: "Preview"
      Item {
        Layout.fillWidth: true
        Layout.preferredHeight: 80
        ColumnLayout {
          anchors.fill: parent
          anchors.margins: Theme.spaceSm
          spacing: 6

          Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 28
            radius: Theme.radiusSm
            color: Theme.panelFill
            border.width: Theme.chromeClear ? 0 : 0
            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: 8
              anchors.rightMargin: 8
              spacing: 8
              Text {
                text: "P"
                color: Theme.accent
                font.family: Theme.fontFamily
                font.pixelSize: 12
                font.bold: true
              }
              Text {
                Layout.fillWidth: true
                text: "Top bar"
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: 11
              }
              Text {
                text: "12:00"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 11
              }
            }
          }

          RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 6
            Rectangle {
              Layout.fillWidth: true
              Layout.fillHeight: true
              radius: Theme.radiusSm
              color: Theme.elevatedFill
              Text {
                anchors.centerIn: parent
                text: "Window"
                color: Theme.textMute
                font.family: Theme.fontFamily
                font.pixelSize: 10
              }
            }
            Rectangle {
              Layout.preferredWidth: 72
              Layout.fillHeight: true
              radius: Theme.radiusPill
              color: Theme.panelFill
              Text {
                anchors.centerIn: parent
                text: "Dock"
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: 10
              }
            }
          }
        }
      }
    }
  }

  // —— Background leaf ——
  ColumnLayout {
    id: bgLeaf
    visible: root.page === "style-background"
    Layout.fillWidth: true
    spacing: Theme.spaceLg

    onVisibleChanged: {
      if (visible) {
        root.wallpaperColorDraft = Config.wallpaperColor
        root.browseKind = Config.wallpaperKind
        Config.ensureWallpaperAlbums()
        Config.scanWallpaperFolder()
      }
    }

    FileDialog {
      id: imageFileDialog
      title: "Choose background image"
      nameFilters: ["Images (*.png *.jpg *.jpeg *.webp *.bmp *.gif)", "All files (*)"]
      onAccepted: Config.setCustomWallpaper(root.localPathFromUrl(selectedFile))
    }

    FolderDialog {
      id: folderDialog
      title: "Add album folder"
      onAccepted: Config.addWallpaperAlbum(root.localPathFromUrl(selectedFolder))
    }

    FileDialog {
      id: videoFileDialog
      title: "Choose looping video"
      nameFilters: ["Videos (*.mp4 *.webm *.mkv *.mov)", "All files (*)"]
      onAccepted: Config.setWallpaperVideo(root.localPathFromUrl(selectedFile))
    }

    SettingsGroup {
      title: "Kind"
      Repeater {
        model: Background.wallpaperKinds
        SettingsFormRow {
          required property var modelData
          required property int index
          label: modelData.label
          hint: {
            if (modelData.id === "color")
              return "Solid desktop color"
            if (modelData.id === "image")
              return "Still images and slideshow"
            if (modelData.id === "daily")
              return "Bing, Unsplash, or a custom feed"
            if (modelData.id === "video")
              return "Silent looping video"
            return "Built-in animated backgrounds"
          }
          interactive: true
          showSeparator: index < Background.wallpaperKinds.length - 1
          onActivated: {
            root.browseKind = modelData.id
            if (modelData.id === "image")
              Config.scanWallpaperFolder()
          }
          Text {
            visible: root.browseKind === modelData.id
            text: "✓"
            color: Theme.accent
            font.pixelSize: 14
          }
        }
      }
    }

    Text {
      visible: root.browseKind !== Config.wallpaperKind
      Layout.fillWidth: true
      Layout.maximumWidth: 480
      text: "Browsing " + root.browseKind + " — desktop stays on " + Config.wallpaperKind + " until you pick one below."
      color: Theme.textMute
      font.family: Theme.fontFamily
      font.pixelSize: 11
      wrapMode: Text.WordWrap
    }

    // Preview
    Rectangle {
      Layout.fillWidth: true
      Layout.maximumWidth: 480
      Layout.preferredHeight: 140
      radius: Theme.radiusLg
      color: root.browseKind === "color" ? Config.wallpaperColor : Theme.bgPanel
      clip: true

      Image {
        visible: root.browseKind === "image" || root.browseKind === "daily"
        anchors.fill: parent
        source: {
          if (root.browseKind === "daily" && Config.wallpaperDailyPath.length)
            return "file://" + Config.wallpaperDailyPath
          if (root.browseKind === "image")
            return "file://" + Background.wallpaperPath
          return ""
        }
        fillMode: root.wallpaperFillMode
        asynchronous: true
        cache: false
      }

      Text {
        visible: root.browseKind === "daily" && !Config.wallpaperDailyPath.length
        anchors.centerIn: parent
        text: "Pick a source and fetch"
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: 12
      }

      Rectangle {
        visible: root.browseKind === "video"
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
        visible: root.browseKind === "reactive"
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

    // —— Color body ——
    ColumnLayout {
      visible: root.browseKind === "color"
      Layout.fillWidth: true
      spacing: Theme.spaceLg

      SettingsGroup {
        title: "Color"
        Item {
          Layout.fillWidth: true
          Layout.preferredHeight: colorFlow.implicitHeight + Theme.spaceMd * 2
          Flow {
            id: colorFlow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Theme.spaceMd
            spacing: Theme.spaceSm
            Repeater {
              model: Background.wallpaperColors
              Column {
                required property var modelData
                spacing: 4
                width: 48
                Rectangle {
                  width: 36
                  height: 36
                  radius: 18
                  anchors.horizontalCenter: parent.horizontalCenter
                  color: modelData.color
                  border.width: Config.wallpaperColor === modelData.color && Config.wallpaperKind === "color" ? 3 : 1
                  border.color: Config.wallpaperColor === modelData.color ? Theme.text : Theme.separator
                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      root.wallpaperColorDraft = modelData.color
                      Config.setWallpaperColor(modelData.color)
                    }
                  }
                }
                Text {
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  text: modelData.label
                  color: Theme.textMute
                  font.family: Theme.fontFamily
                  font.pixelSize: 10
                  elide: Text.ElideRight
                }
              }
            }
          }
        }
        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 1
          color: Theme.separator
          opacity: 0.6
        }
        Item {
          Layout.fillWidth: true
          Layout.preferredHeight: bgGraph.implicitHeight + Theme.spaceMd
          ColorGraphPicker {
            id: bgGraph
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Theme.spaceMd
            hex: Config.wallpaperColor
            onHexEdited: h => {
              root.wallpaperColorDraft = h
              bgColorApply.hex = h
              bgColorApply.restart()
            }
          }
          Timer {
            id: bgColorApply
            property string hex: ""
            interval: 80
            onTriggered: {
              if (Config.setWallpaperColor(hex))
                root.wallpaperColorDraft = Config.wallpaperColor
            }
          }
        }
      }
    }

    // —— Daily body ——
    ColumnLayout {
      visible: root.browseKind === "daily"
      Layout.fillWidth: true
      spacing: Theme.spaceLg

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
      visible: root.browseKind === "image"
      Layout.fillWidth: true
      spacing: Theme.spaceLg

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
                  anchors.fill: parent
                  anchors.margins: Config.wallpaperId === modelData.id ? 2 : 0
                  source: "file://" + modelData.path
                  fillMode: Image.PreserveAspectCrop
                  asynchronous: true
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
          hint: Background.wallpaperFolderResolved
          showSeparator: Background.wallpaperFolderEntries.length > 0 || Background.wallpaperFolderScanning
          Text {
            visible: Background.wallpaperFolderScanning
            text: "…"
            color: Theme.textMute
            font.pixelSize: 12
          }
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
                  anchors.fill: parent
                  source: "file://" + modelData.path
                  fillMode: Image.PreserveAspectCrop
                  asynchronous: true
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
      visible: root.browseKind === "video"
      Layout.fillWidth: true
      spacing: Theme.spaceLg

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
      visible: root.browseKind === "reactive"
      Layout.fillWidth: true
      spacing: Theme.spaceLg

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

  LockPane {
    visible: root.page === "style-lock"
    Layout.fillWidth: true
  }

  // —— Font leaf ——
  ColumnLayout {
    visible: root.page === "style-font"
    Layout.fillWidth: true
    spacing: Theme.spaceLg

    onVisibleChanged: {
      if (visible)
        Config.scanSystemFonts()
    }

    SettingsGroup {
      title: Config.fontsScanning ? "Scanning…" : "Typeface"
      Item {
        Layout.fillWidth: true
        Layout.preferredHeight: fontFlow.implicitHeight + Theme.spaceMd * 2
        Flow {
          id: fontFlow
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: Theme.spaceMd
          spacing: Theme.spaceSm
          Repeater {
            model: Config.fonts
            Rectangle {
              required property var modelData
              width: 100
              height: 52
              radius: Theme.radiusMd
              color: Config.fontFamily === modelData.id ? Theme.accentSoft : Theme.bgHover
              Column {
                anchors.centerIn: parent
                spacing: 4
                Text {
                  text: "Aa"
                  color: Theme.text
                  font.family: modelData.id
                  font.pixelSize: 18
                  anchors.horizontalCenter: parent.horizontalCenter
                }
                Text {
                  text: modelData.label
                  color: Theme.textDim
                  font.family: Theme.fontFamily
                  font.pixelSize: 11
                  anchors.horizontalCenter: parent.horizontalCenter
                }
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: Config.fontFamily = modelData.id
              }
            }
          }
        }
      }
    }

    SettingsGroup {
      title: "Size"
      SettingsFormRow {
        label: "UI size"
        hint: Config.fontSize + "px"
        showSeparator: false
        Slider {
          Layout.preferredWidth: 140
          from: 11
          to: 18
          stepSize: 1
          value: Config.fontSize
          onMoved: {
            const v = Math.round(value)
            Config.fontSize = v
            Config.fontSizeSm = Math.max(10, v - 1)
          }
        }
      }
    }

    SettingsGroup {
      title: "Preview"
      Item {
        Layout.fillWidth: true
        Layout.preferredHeight: fontPreviewCol.implicitHeight + Theme.spaceMd * 2
        ColumnLayout {
          id: fontPreviewCol
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: Theme.spaceMd
          spacing: 6

          Text {
            Layout.fillWidth: true
            text: "Proteus"
            color: Theme.text
            font.family: Config.fontFamily
            font.pixelSize: Config.fontSize + 2
            font.bold: true
          }
          Text {
            Layout.fillWidth: true
            text: "The quick brown fox jumps over the lazy dog."
            color: Theme.text
            font.family: Config.fontFamily
            font.pixelSize: Config.fontSize
            wrapMode: Text.WordWrap
          }
          Text {
            Layout.fillWidth: true
            text: "Bar · dock · Settings · " + Config.fontSize + "px"
            color: Theme.textMute
            font.family: Config.fontFamily
            font.pixelSize: Config.fontSizeSm
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }
}
