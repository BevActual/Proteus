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
  width: parent ? parent.width : implicitWidth
  spacing: Theme.spaceMd

  Component.onCompleted: Config.scanSystemFonts()
  onVisibleChanged: {
    if (visible)
      Config.scanSystemFonts()
  }

  SettingsGroup {
    title: Config.fontsScanning ? "Scanning…" : "Typeface"
    SettingsFontPicker {
      model: Config.fonts
      selectedId: Config.fontFamily
      scanning: Config.fontsScanning
      onActivated: id => {
        Config.fontFamily = id
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
