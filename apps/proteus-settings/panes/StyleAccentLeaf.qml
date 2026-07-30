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

    function syncDraft() {
      if (!host)
        return
      host.accentHexDraft = Config.accentCustom
    }
    onHostChanged: syncDraft()
    onVisibleChanged: {
      if (visible)
        syncDraft()
    }

    SettingsGroup {
      title: "Chrome"

      SettingsSegmented {
        Layout.fillWidth: true
        Layout.leftMargin: Theme.spaceSm
        Layout.rightMargin: Theme.spaceSm
        Layout.topMargin: Theme.spaceSm
        Layout.bottomMargin: Theme.spaceSm
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
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: Theme.separator
        opacity: 0.6
      }

      SettingsFormRow {
        label: "Opacity"
        hint: Config.chromeOpacity < 0.01 ? "Clear"
            : (Math.round(Config.chromeOpacity * 100) + "% solid"
                + (Config.chromeBlur ? " · glass" : ""))
        showSeparator: true
        Slider {
          Layout.preferredWidth: 160
          from: 0
          to: 1
          stepSize: 0.01
          value: Config.chromeOpacity
          // Live Theme update — Hypr blur retune is debounced inside setChromeOpacity
          onMoved: Config.setChromeOpacity(value)
        }
      }

      SettingsFormRow {
        label: "Blur"
        hint: Config.chromeBlur
            ? "Frosted bar, dock, launcher"
            : "Off — plate only"
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
                    host.accentHexDraft = Config.accentCustom
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
            host.accentHexDraft = h
            Config.setAccentCustom(h)
          }
          onHexCommitted: h => {
            host.accentHexDraft = h
            Config.setAccentCustom(h)
            Config.flushSettings()
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
