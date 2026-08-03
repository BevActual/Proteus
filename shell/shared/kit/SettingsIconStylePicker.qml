import Quickshell
import QtQuick
import QtQuick.Layouts
import ".."

// Compare Default / Dark / Clear / Tinted with live squircle previews.
ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: Theme.spaceSm

  property string selected: "default"
  property url previewSource: ""
  property real previewGlyphScale: Theme.iconGlyphScaleBrand

  signal activated(string id)

  readonly property var styles: [
    {
      id: "default",
      label: "Default",
      hint: "Neutral plate"
    },
    {
      id: "dark",
      label: "Dark",
      hint: "Deep plate"
    },
    {
      id: "clear",
      label: "Clear",
      hint: "Glass wash"
    },
    {
      id: "tinted",
      label: "Tinted",
      hint: "Custom color"
    }
  ]

  function plateFor(mode) {
    if (mode === "clear")
      return Qt.rgba(0, 0, 0, 0)
    if (mode === "dark")
      return Theme.iconPlateDark
    if (mode === "tinted") {
      const h = Config.normalizeAccentHex(Config.iconPlateCustom)
      if (h.length)
        return h
      return Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.88)
    }
    return Theme.iconPlateDefault
  }

  Flow {
    Layout.fillWidth: true
    Layout.leftMargin: Theme.spaceMd
    Layout.rightMargin: Theme.spaceMd
    Layout.topMargin: Theme.spaceSm
    Layout.bottomMargin: Theme.spaceSm
    spacing: Theme.spaceSm

    Repeater {
      model: root.styles
      Rectangle {
        required property var modelData
        width: 112
        height: 108
        radius: Theme.radiusMd
        color: root.selected === modelData.id ? Theme.accentSoft : Theme.bgHover
        border.width: root.selected === modelData.id ? 2 : 0
        border.color: Theme.accent

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: Theme.spaceSm
          spacing: 6

          Item {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 48
            Layout.preferredHeight: 48
            SquircleIcon {
              anchors.fill: parent
              pixelSize: 128
              fillCrop: false
              showBorder: modelData.id === "clear"
              glyphScale: root.previewGlyphScale
              styleModeOverride: modelData.id
              plateOverride: root.plateFor(modelData.id)
              plate: root.plateFor(modelData.id)
              source: root.previewSource
            }
          }

          Text {
            Layout.fillWidth: true
            text: modelData.label
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: 12
            horizontalAlignment: Text.AlignHCenter
          }
          Text {
            Layout.fillWidth: true
            text: modelData.hint
            color: Theme.textMute
            font.family: Theme.fontFamily
            font.pixelSize: 10
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
          }
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.activated(modelData.id)
        }
      }
    }
  }
}
