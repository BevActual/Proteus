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
    spacing: Theme.spaceLg

    function syncDraft() {
      if (!host)
        return
      host.iconPlateHexDraft = Config.iconPlateCustom
    }
    onHostChanged: syncDraft()
    onVisibleChanged: {
      if (visible)
        syncDraft()
    }

    FileDialog {
      id: iconFileDialog
      title: "Choose icon image"
      nameFilters: ["Images (*.png *.svg *.jpg *.jpeg *.webp *.ico)", "All files (*)"]
      onAccepted: {
        const id = host.iconSwitchTargetId
        if (!id.length)
          return
        Config.setIconOverride(id, host.localPathFromUrl(selectedFile))
        host.iconSwitchTargetId = ""
      }
    }

    SettingsGroup {
      title: "Icon style"

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
              id: "default",
              label: "Default"
            },
            {
              id: "dark",
              label: "Dark"
            },
            {
              id: "clear",
              label: "Clear"
            },
            {
              id: "tinted",
              label: "Tinted"
            }
          ]
          selected: Config.iconPlateStyle
          onActivated: id => Config.setIconPlateMode(id)
        }
      }

      Rectangle {
        visible: Config.iconPlateStyle === "tinted"
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: Theme.separator
        opacity: 0.6
      }

      Item {
        visible: Config.iconPlateStyle === "tinted"
        Layout.fillWidth: true
        Layout.preferredHeight: iconPlateGraph.implicitHeight + Theme.spaceMd
        ColorGraphPicker {
          id: iconPlateGraph
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: Theme.spaceMd
          hex: Config.iconPlateCustom
          onHexEdited: h => {
            host.iconPlateHexDraft = h
            Config.setIconPlateCustom(h)
          }
        }
      }
    }

    SettingsGroup {
      title: "Preview"
      Item {
        Layout.fillWidth: true
        Layout.preferredHeight: 72
        RowLayout {
          anchors.fill: parent
          anchors.margins: Theme.spaceMd
          spacing: Theme.spaceMd

          SquircleIcon {
            Layout.preferredWidth: 48
            Layout.preferredHeight: 48
            pixelSize: 128
            fillCrop: false
            showBorder: false
            glyphScale: Theme.iconGlyphScaleBrand
            plate: Theme.iconPlateFill
            source: DockApps.brandFileUrl("proteus-launcher")
          }
          SquircleIcon {
            Layout.preferredWidth: 48
            Layout.preferredHeight: 48
            pixelSize: 128
            fillCrop: false
            showBorder: false
            glyphScale: Theme.iconGlyphScaleApp
            plate: Theme.iconPlateFill
            source: host.dockMiddlePins.length
                ? DockApps.iconSource(host.dockMiddlePins[0])
                : DockApps.brandFileUrl("proteus-settings")
          }
          SquircleIcon {
            Layout.preferredWidth: 48
            Layout.preferredHeight: 48
            pixelSize: 128
            fillCrop: false
            showBorder: false
            glyphScale: Theme.iconGlyphScaleBrand
            plate: Theme.iconPlateFill
            source: DockApps.brandFileUrl("proteus-settings")
          }
          Item {
            Layout.fillWidth: true
          }
        }
      }
    }

    SettingsGroup {
      title: "Custom icons"

      Text {
        Layout.fillWidth: true
        Layout.leftMargin: Theme.spaceMd
        Layout.rightMargin: Theme.spaceMd
        Layout.topMargin: Theme.spaceSm
        text: "Icon style (Default / Dark / Clear / Tinted) restyles every dock and Spotlight icon. To add or remove apps: open them and right-click the dock — Keep in Dock or Remove from Dock — or use Spotlight. Switch replaces an app’s artwork."
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSm
        wrapMode: Text.WordWrap
      }

      Repeater {
        model: host.dockMiddlePins

        delegate: Item {
          id: pinRow
          required property var modelData
          Layout.fillWidth: true
          Layout.preferredHeight: 56

          readonly property string pinId: String(modelData.desktopId || modelData.id || "")
          readonly property bool hasOverride: {
            const _ = Config.iconOverrides
            return Config.iconOverrideFor(pinRow.pinId).length > 0
          }

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.spaceMd
            anchors.rightMargin: Theme.spaceMd
            spacing: Theme.spaceSm

            SquircleIcon {
              Layout.preferredWidth: 40
              Layout.preferredHeight: 40
              pixelSize: 96
              fillCrop: false
              showBorder: false
              glyphScale: Theme.iconGlyphScaleApp
              plate: Theme.iconPlateFill
              source: DockApps.iconSource(pinRow.modelData)
            }

            ColumnLayout {
              Layout.fillWidth: true
              spacing: 1
              Text {
                Layout.fillWidth: true
                text: modelData.label || pinRow.pinId
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                elide: Text.ElideRight
              }
              Text {
                visible: pinRow.hasOverride
                Layout.fillWidth: true
                text: "Custom icon"
                color: Theme.textMute
                font.family: Theme.fontFamily
                font.pixelSize: 11
                elide: Text.ElideRight
              }
            }

            Button {
              text: "Switch"
              onClicked: {
                host.iconSwitchTargetId = pinRow.pinId
                iconFileDialog.open()
              }
            }
            Button {
              visible: pinRow.hasOverride
              text: "Reset"
              onClicked: Config.clearIconOverride(pinRow.pinId)
            }
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
      }

      SettingsFormRow {
        label: host.addDockOpen ? "Hide app picker" : "Add to Dock…"
        hint: "Same as Keep in Dock"
        interactive: true
        showSeparator: false
        onActivated: {
          host.addDockOpen = !host.addDockOpen
          if (!host.addDockOpen)
            host.addDockFilter = ""
        }
        Text {
          text: host.addDockOpen ? "⌃" : "›"
          color: Theme.textMute
          font.pixelSize: 16
        }
      }
    }

    SettingsGroup {
      visible: host.addDockOpen
      title: "Add app"

      TextField {
        id: addDockSearch
        Layout.fillWidth: true
        Layout.margins: Theme.spaceSm
        placeholderText: "Search apps…"
        color: Theme.text
        placeholderTextColor: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        background: Item {}
        text: host.addDockFilter
        onTextChanged: host.addDockFilter = text
      }

      Repeater {
        model: host.addDockCandidates

        delegate: SettingsFormRow {
          required property var modelData
          label: modelData.name
          hint: modelData.id
          interactive: true
          showSeparator: true
          onActivated: {
            DockApps.pinDesktopId(modelData.id)
            host.addDockFilter = ""
            host.addDockOpen = false
          }
          SquircleIcon {
            Layout.preferredWidth: 28
            Layout.preferredHeight: 28
            pixelSize: 64
            fillCrop: false
            showBorder: false
            glyphScale: Theme.iconGlyphScaleApp
            plate: Theme.iconPlateFill
            source: EnvGate.iconSource(modelData.icon)
          }
        }
      }

      Text {
        visible: host.addDockCandidates.length === 0
        Layout.fillWidth: true
        Layout.margins: Theme.spaceMd
        text: "No matching apps to add."
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSm
      }
    }
  }
