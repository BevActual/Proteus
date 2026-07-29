import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../shared"
import "../kit"

// Desktop category: list of sub-settings → leaf. Navigation via page + requestGo.
ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: 12

  property string page: "desktop"
  signal requestGo(string id)

  readonly property bool active: page === "desktop" || page.startsWith("desktop-")

  readonly property var sections: [
    {
      key: "desktop-gaps",
      label: "Gaps"
    },
    {
      key: "desktop-chrome",
      label: "Borders & rounding"
    },
    {
      key: "desktop-motion",
      label: "Motion"
    },
    {
      key: "desktop-dock",
      label: "Dock & menu bar"
    },
    {
      key: "desktop-launcher",
      label: "Launcher"
    }
  ]

  // —— Category list ——
  SettingsHubList {
    visible: root.page === "desktop"
    items: root.sections
    onActivated: key => root.requestGo(key)
  }

  // —— Gaps ——
  ColumnLayout {
    visible: root.page === "desktop-gaps"
    Layout.fillWidth: true
    spacing: 14

    Text {
      text: "Window gaps (inside)"
      color: Theme.textDim
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSizeSm
    }
    RowLayout {
      Layout.fillWidth: true
      Slider {
        Layout.fillWidth: true
        from: 0
        to: 32
        stepSize: 1
        value: Config.gapsIn
        onMoved: Config.gapsIn = Math.round(value)
      }
      Text {
        text: Config.gapsIn
        color: Theme.text
        font.family: Theme.fontFamily
        Layout.preferredWidth: 28
      }
    }

    Text {
      text: "Outer gaps"
      color: Theme.textDim
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSizeSm
    }
    RowLayout {
      Layout.fillWidth: true
      Slider {
        Layout.fillWidth: true
        from: 0
        to: 48
        stepSize: 1
        value: Config.gapsOut
        onMoved: Config.gapsOut = Math.round(value)
      }
      Text {
        text: Config.gapsOut
        color: Theme.text
        font.family: Theme.fontFamily
        Layout.preferredWidth: 28
      }
    }
  }

  // —— Borders & rounding ——
  ColumnLayout {
    visible: root.page === "desktop-chrome"
    Layout.fillWidth: true
    spacing: 14

    Text {
      text: "Border size"
      color: Theme.textDim
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSizeSm
    }
    RowLayout {
      Layout.fillWidth: true
      Slider {
        Layout.fillWidth: true
        from: 0
        to: 8
        stepSize: 1
        value: Config.borderSize
        onMoved: Config.borderSize = Math.round(value)
      }
      Text {
        text: Config.borderSize
        color: Theme.text
        font.family: Theme.fontFamily
        Layout.preferredWidth: 28
      }
    }

    Text {
      text: "Window rounding"
      color: Theme.textDim
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSizeSm
    }
    RowLayout {
      Layout.fillWidth: true
      Slider {
        Layout.fillWidth: true
        from: 0
        to: 24
        stepSize: 1
        value: Config.rounding
        onMoved: Config.rounding = Math.round(value)
      }
      Text {
        text: Config.rounding
        color: Theme.text
        font.family: Theme.fontFamily
        Layout.preferredWidth: 28
      }
    }
  }

  // —— Motion ——
  ColumnLayout {
    visible: root.page === "desktop-motion"
    Layout.fillWidth: true
    spacing: Theme.spaceMd

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 48
      radius: Theme.radiusMd
      color: Theme.bgPanel
      border.width: 1
      border.color: Theme.border
      RowLayout {
        anchors.fill: parent
        anchors.margins: Theme.spaceMd
        Text {
          Layout.fillWidth: true
          text: "Window animations"
          color: Theme.text
          font.family: Theme.fontFamily
        }
        Switch {
          checked: Config.animationsEnabled
          onToggled: Config.animationsEnabled = checked
        }
      }
    }
  }

  // —— Dock & menu bar ——
  ColumnLayout {
    id: dockLeaf
    visible: root.page === "desktop-dock"
    Layout.fillWidth: true
    spacing: Theme.spaceMd

    readonly property var screenOpts: {
      const _n = Quickshell.screens.length
      return Config.chromeScreenOptions()
    }

    function screenIndex(sel) {
      const opts = screenOpts
      for (let i = 0; i < opts.length; i++) {
        if (opts[i].id === sel)
          return i
      }
      return 0
    }

    SettingsGroup {
      title: "Dock"

      SettingsFormRow {
        label: "Show dock"
        showSeparator: true
        Switch {
          checked: Config.dockEnabled
          onToggled: Config.dockEnabled = checked
        }
      }

      SettingsFormRow {
        label: "Automatically hide"
        hint: "Reveal at the bottom edge"
        showSeparator: true
        Switch {
          checked: Config.dockAutoHide
          enabled: Config.dockEnabled
          onToggled: Config.dockAutoHide = checked
        }
      }

      SettingsFormRow {
        label: "Show on"
        hint: Config.dockMonitor === "all" ? "Every display" : Config.dockMonitor
        showSeparator: true
        ComboBox {
          id: dockMonBox
          Layout.preferredWidth: 168
          enabled: Config.dockEnabled
          textRole: "label"
          valueRole: "id"
          model: root.page === "desktop-dock" ? dockLeaf.screenOpts : []
          Component.onCompleted: currentIndex = dockLeaf.screenIndex(Config.dockMonitor)
          onActivated: Config.dockMonitor = String(currentValue || "all")
        }
      }

      SettingsFormRow {
        label: "Icon size"
        hint: Config.dockIconSize + " px"
        showSeparator: false
        Slider {
          Layout.preferredWidth: 140
          from: 36
          to: 72
          stepSize: 2
          value: Config.dockIconSize
          onMoved: Config.dockIconSize = Math.round(value)
        }
      }
    }

    SettingsGroup {
      title: "Menu bar"

      SettingsFormRow {
        label: "Automatically hide"
        hint: "Reveal at the top edge"
        showSeparator: true
        Switch {
          checked: Config.barAutoHide
          onToggled: Config.barAutoHide = checked
        }
      }

      SettingsFormRow {
        label: "Show on"
        hint: Config.barMonitor === "all" ? "Every display" : Config.barMonitor
        showSeparator: true
        ComboBox {
          Layout.preferredWidth: 168
          textRole: "label"
          valueRole: "id"
          model: root.page === "desktop-dock" ? dockLeaf.screenOpts : []
          Component.onCompleted: currentIndex = dockLeaf.screenIndex(Config.barMonitor)
          onActivated: Config.barMonitor = String(currentValue || "all")
        }
      }

      SettingsFormRow {
        label: "Height"
        hint: Config.barHeight + " px"
        showSeparator: false
        Slider {
          Layout.preferredWidth: 140
          from: 28
          to: 48
          stepSize: 1
          value: Config.barHeight
          onMoved: Config.barHeight = Math.round(value)
        }
      }
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.maximumWidth: 480
      Layout.preferredHeight: 40
      Layout.topMargin: 4
      radius: Theme.radiusMd
      color: Theme.bgPanel
      border.width: 1
      border.color: Theme.border
      Text {
        anchors.centerIn: parent
        text: "Edit compositor config…"
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: 12
      }
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: Config.openGeneralConfInEditor()
      }
    }
  }

  // —— Launcher (Spotlight tags) ——
  ColumnLayout {
    visible: root.page === "desktop-launcher"
    Layout.fillWidth: true
    spacing: Theme.spaceMd

    SettingsGroup {
      title: "App tags"

      Text {
        Layout.fillWidth: true
        Layout.leftMargin: Theme.spaceSm
        Layout.rightMargin: Theme.spaceSm
        Layout.topMargin: Theme.spaceSm
        text: "Optional labels to group apps in Spotlight Apps mode. Assign with Ctrl+T or # on a result; filter with #tag. Modes: Ctrl+1 Apps · Ctrl+2 Files · Ctrl+3 Clipboard. Type math (e.g. 12*7) or conversions (32 f to c)."
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSm
        wrapMode: Text.WordWrap
      }

      RowLayout {
        Layout.fillWidth: true
        Layout.margins: Theme.spaceSm
        spacing: Theme.spaceSm

        TextField {
          id: newTagField
          Layout.fillWidth: true
          placeholderText: "New tag (e.g. work)"
          color: Theme.text
          placeholderTextColor: Theme.textMute
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSize
          background: Item {}
          onAccepted: {
            if (Config.ensureLauncherTag(text))
              text = ""
          }
        }

        Button {
          text: "Add"
          onClicked: {
            if (Config.ensureLauncherTag(newTagField.text))
              newTagField.text = ""
          }
        }
      }

      Rectangle {
        Layout.fillWidth: true
        height: 1
        color: Theme.separator
        opacity: 0.5
      }

      ColumnLayout {
        Layout.fillWidth: true
        Layout.margins: Theme.spaceSm
        spacing: 6

        Repeater {
          model: {
            const _ = Config.launcherTagCatalog
            return Config.launcherTagCatalogList()
          }

          delegate: RowLayout {
            required property string modelData
            Layout.fillWidth: true
            spacing: Theme.spaceSm

            Text {
              Layout.fillWidth: true
              text: "#" + modelData
              color: Theme.text
              font.family: Theme.fontFamily
              font.pixelSize: Theme.fontSize
            }

            Text {
              text: {
                const _m = Config.launcherAppTags
                const map = Config.parseLauncherAppTagMap()
                let n = 0
                const ids = Object.keys(map)
                for (let i = 0; i < ids.length; i++) {
                  if (map[ids[i]].indexOf(modelData) >= 0)
                    n++
                }
                return n === 1 ? "1 app" : (n + " apps")
              }
              color: Theme.textMute
              font.family: Theme.fontFamily
              font.pixelSize: Theme.fontSizeSm
            }

            Button {
              text: "Remove"
              flat: true
              onClicked: Config.removeLauncherTag(modelData)
            }
          }
        }

        Text {
          visible: {
            const _ = Config.launcherTagCatalog
            return Config.launcherTagCatalogList().length === 0
          }
          Layout.fillWidth: true
          text: "No tags yet — add one above, or create while tagging an app in Spotlight."
          color: Theme.textMute
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSizeSm
          wrapMode: Text.WordWrap
        }
      }
    }
  }
}
