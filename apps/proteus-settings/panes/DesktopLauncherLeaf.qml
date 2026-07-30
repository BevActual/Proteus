import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../shared"
import "../kit"

// Leaf UI for DesktopPane — Launcher (Spotlight tags + recents).
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
    title: "Spotlight"

    Text {
      Layout.fillWidth: true
      Layout.leftMargin: Theme.spaceMd
      Layout.rightMargin: Theme.spaceMd
      Layout.topMargin: Theme.spaceSm
      Layout.bottomMargin: Theme.spaceSm
      text: "Modes: Ctrl+1 Apps · Ctrl+2 Files · Ctrl+3 Clipboard. Tag an app with Ctrl+T or # · filter with #tag. Math and unit conversions work in the search field."
      color: Theme.textMute
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSizeSm
      wrapMode: Text.WordWrap
    }

    SettingsFormRow {
      label: "Recent apps"
      hint: root.recentCount === 0 ? "None yet"
          : (root.recentCount === 1 ? "1 app" : root.recentCount + " apps")
      showSeparator: false
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
  }

  SettingsGroup {
    title: "App tags"

    Text {
      Layout.fillWidth: true
      Layout.leftMargin: Theme.spaceMd
      Layout.rightMargin: Theme.spaceMd
      Layout.topMargin: Theme.spaceSm
      text: "Optional labels to group apps in Spotlight Apps mode."
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
      text: "No tags yet — add one above, or create while tagging an app in Spotlight."
      color: Theme.textMute
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSizeSm
      wrapMode: Text.WordWrap
    }
  }
}
