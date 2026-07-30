import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../shared"
import "../kit"

// Leaf UI for DesktopPane — Launcher (Spotlight tags).
ColumnLayout {
  id: root
  width: parent ? parent.width : implicitWidth
  spacing: Theme.spaceMd

  SettingsGroup {
    title: "App tags"

    Text {
      Layout.fillWidth: true
      Layout.leftMargin: Theme.spaceMd
      Layout.rightMargin: Theme.spaceMd
      Layout.topMargin: Theme.spaceSm
      text: "Optional labels to group apps in Spotlight Apps mode. Assign with Ctrl+T or # on a result; filter with #tag. Modes: Ctrl+1 Apps · Ctrl+2 Files · Ctrl+3 Clipboard. Type math (e.g. 12*7) or conversions (32 f to c)."
      color: Theme.textMute
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSizeSm
      wrapMode: Text.WordWrap
    }

    RowLayout {
      Layout.fillWidth: true
      Layout.leftMargin: Theme.spaceMd
      Layout.rightMargin: Theme.spaceMd
      Layout.topMargin: Theme.spaceSm
      Layout.bottomMargin: Theme.spaceSm
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
      Layout.preferredHeight: 1
      color: Theme.separator
      opacity: 0.5
    }

    ColumnLayout {
      Layout.fillWidth: true
      Layout.leftMargin: Theme.spaceMd
      Layout.rightMargin: Theme.spaceMd
      Layout.topMargin: Theme.spaceSm
      Layout.bottomMargin: Theme.spaceMd
      spacing: Theme.spaceSm

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
