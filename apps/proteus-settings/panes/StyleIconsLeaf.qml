import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import "../shared"
import "../kit"

// Leaf UI for StylePane; `host` is the StylePane root (shared drafts / helpers).
ColumnLayout {
  id: root
  property Item host
  width: parent ? parent.width : implicitWidth
  spacing: Theme.spaceMd

  readonly property url stylePreviewSource: DockApps.brandFileUrl("proteus-settings")

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
    SettingsIconStylePicker {
      selected: Config.iconPlateStyle
      previewSource: root.stylePreviewSource
      previewGlyphScale: Theme.iconGlyphScaleBrand
      onActivated: id => Config.setIconPlateMode(id)
    }

    Rectangle {
      visible: Config.iconPlateStyle === "tinted"
      Layout.fillWidth: true
      Layout.preferredHeight: 1
      color: Theme.separator
      opacity: 0.6
    }

    Text {
      visible: Config.iconPlateStyle === "tinted"
      Layout.fillWidth: true
      Layout.leftMargin: Theme.spaceMd
      Layout.rightMargin: Theme.spaceMd
      Layout.topMargin: Theme.spaceSm
      text: "Tint color — applies to plate and glyph wash"
      color: Theme.textMute
      font.family: Theme.fontFamily
      font.pixelSize: 12
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
    title: "Live preview"
    Item {
      Layout.fillWidth: true
      Layout.preferredHeight: 88
      RowLayout {
        anchors.fill: parent
        anchors.margins: Theme.spaceMd
        spacing: Theme.spaceMd

        SquircleIcon {
          Layout.preferredWidth: 52
          Layout.preferredHeight: 52
          pixelSize: 128
          fillCrop: false
          showBorder: Config.iconPlateStyle === "clear"
          glyphScale: Theme.iconGlyphScaleBrand
          plate: Theme.iconPlateFill
          source: DockApps.brandFileUrl("proteus-launcher")
        }
        SquircleIcon {
          Layout.preferredWidth: 52
          Layout.preferredHeight: 52
          pixelSize: 128
          fillCrop: false
          showBorder: Config.iconPlateStyle === "clear"
          glyphScale: Theme.iconGlyphScaleApp
          plate: Theme.iconPlateFill
          source: host.dockMiddlePins.length
              ? DockApps.iconSource(host.dockMiddlePins[0])
              : DockApps.brandFileUrl("proteus-settings")
        }
        SquircleIcon {
          Layout.preferredWidth: 52
          Layout.preferredHeight: 52
          pixelSize: 128
          fillCrop: false
          showBorder: Config.iconPlateStyle === "clear"
          glyphScale: Theme.iconGlyphScaleBrand
          plate: Theme.iconPlateFill
          source: DockApps.brandFileUrl("proteus-settings")
        }
        ColumnLayout {
          Layout.fillWidth: true
          spacing: 2
          Text {
            text: {
              const m = Config.iconPlateStyle
              if (m === "dark")
                return "Dark"
              if (m === "clear")
                return "Clear"
              if (m === "tinted")
                return "Tinted"
              return "Default"
            }
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
          }
          Text {
            Layout.fillWidth: true
            text: "Dock · Spotlight · brand marks"
            color: Theme.textMute
            font.family: Theme.fontFamily
            font.pixelSize: 11
            wrapMode: Text.WordWrap
          }
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
      text: "Style above restyles every dock and Spotlight icon. Switch replaces one app’s artwork; Keep/Remove apps from the dock or Spotlight."
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
        Layout.preferredHeight: 52

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
            Layout.preferredWidth: 36
            Layout.preferredHeight: 36
            pixelSize: 96
            fillCrop: false
            showBorder: Config.iconPlateStyle === "clear"
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

          Text {
            text: "Switch"
            color: Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: 13
            MouseArea {
              anchors.fill: parent
              anchors.margins: -8
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                host.iconSwitchTargetId = pinRow.pinId
                iconFileDialog.open()
              }
            }
          }
          Text {
            visible: pinRow.hasOverride
            text: "Reset"
            color: Theme.textMute
            font.family: Theme.fontFamily
            font.pixelSize: 13
            MouseArea {
              anchors.fill: parent
              anchors.margins: -8
              cursorShape: Qt.PointingHandCursor
              onClicked: Config.clearIconOverride(pinRow.pinId)
            }
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
