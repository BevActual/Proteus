import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../shared"
import "../kit"

// Leaf UI for DesktopPane — Beacon (system search: tags + recents).
ColumnLayout {
  id: root
  width: parent ? parent.width : implicitWidth
  spacing: Theme.spaceMd

  readonly property var tagList: {
    const _ = Config.launcherTagCatalog
    return Config.launcherTagCatalogList()
  }

  readonly property int recentCount: {
    const _ = Config.launcherRecents
    return Config.launcherRecentList().length
  }

  readonly property int fileRecentCount: {
    const _ = Config.launcherFileRecents
    return Config.launcherFileRecentList().length
  }

  function appCountForTag(tag) {
    const _m = Config.launcherAppTags
    const map = Config.parseLauncherAppTagMap()
    let n = 0
    const ids = Object.keys(map)
    for (let i = 0; i < ids.length; i++) {
      if (map[ids[i]].indexOf(tag) >= 0)
        n++
    }
    return n
  }

  SettingsGroup {
    title: "Beacon"

    Text {
      Layout.fillWidth: true
      Layout.leftMargin: Theme.spaceMd
      Layout.rightMargin: Theme.spaceMd
      Layout.topMargin: Theme.spaceSm
      Layout.bottomMargin: Theme.spaceSm
      text: "Universal search for apps, Settings, Actions, running Windows, and Privacy In-use / grants. Modes: Tab cycles · Ctrl+1 Apps · Ctrl+2 Files (beacon-file-index) · Ctrl+3 Clipboard (paste via wtype when available) · Ctrl+4 Actions. Tag an app with Ctrl+T or # · filter with #tag. Math and unit conversions work in the search field."
      color: Theme.textMute
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSizeSm
      wrapMode: Text.WordWrap
    }

    SettingsFormRow {
      label: "Recent apps"
      hint: root.recentCount === 0 ? "None yet"
          : (root.recentCount === 1 ? "1 app" : root.recentCount + " apps")
      showSeparator: true
      Text {
        visible: root.recentCount > 0
        text: "Clear"
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: 13
        MouseArea {
          anchors.fill: parent
          anchors.margins: -8
          cursorShape: Qt.PointingHandCursor
          onClicked: Config.clearLauncherRecents()
        }
      }
    }

    SettingsFormRow {
      label: "Recent files"
      hint: root.fileRecentCount === 0 ? "None yet"
          : (root.fileRecentCount === 1 ? "1 path" : root.fileRecentCount + " paths")
      showSeparator: false
      Text {
        visible: root.fileRecentCount > 0
        text: "Clear"
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: 13
        MouseArea {
          anchors.fill: parent
          anchors.margins: -8
          cursorShape: Qt.PointingHandCursor
          onClicked: Config.clearLauncherFileRecents()
        }
      }
    }
  }

  SettingsGroup {
    title: "App tags"

    Text {
      Layout.fillWidth: true
      Layout.leftMargin: Theme.spaceMd
      Layout.rightMargin: Theme.spaceMd
      Layout.topMargin: Theme.spaceSm
      text: "Optional labels to group apps in Beacon Apps mode."
      color: Theme.textMute
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSizeSm
      wrapMode: Text.WordWrap
    }

    SettingsFormRow {
      label: "Add tag"
      hint: "Letters, numbers, hyphens"
      showSeparator: root.tagList.length > 0
      TextField {
        id: newTagField
        Layout.preferredWidth: 140
        placeholderText: "work"
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
      Text {
        text: "Add"
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: 13
        MouseArea {
          anchors.fill: parent
          anchors.margins: -8
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (Config.ensureLauncherTag(newTagField.text))
              newTagField.text = ""
          }
        }
      }
    }

    Repeater {
      model: root.tagList

      delegate: SettingsFormRow {
        required property string modelData
        label: "#" + modelData
        hint: {
          const n = root.appCountForTag(modelData)
          return n === 1 ? "1 app" : (n + " apps")
        }
        showSeparator: true
        Text {
          text: "Remove"
          color: Theme.textMute
          font.family: Theme.fontFamily
          font.pixelSize: 13
          MouseArea {
            anchors.fill: parent
            anchors.margins: -8
            cursorShape: Qt.PointingHandCursor
            onClicked: Config.removeLauncherTag(modelData)
          }
        }
      }
    }

    Text {
      visible: root.tagList.length === 0
      Layout.fillWidth: true
      Layout.leftMargin: Theme.spaceMd
      Layout.rightMargin: Theme.spaceMd
      Layout.bottomMargin: Theme.spaceMd
      text: "No tags yet — add one above, or create while tagging an app in Beacon."
      color: Theme.textMute
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSizeSm
      wrapMode: Text.WordWrap
    }
  }
}
