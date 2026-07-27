import Quickshell
import QtQuick
import QtQuick.Layouts
import "../shared"

// Peripherals category: Keyboard · Mouse (headphones stay under Sound).
ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: 12

  property string page: "peripherals"
  signal requestGo(string id)

  readonly property var sections: [
    {
      key: "peripherals-keyboard",
      label: "Keyboard",
      hint: "Shortcuts and keybinds"
    },
    {
      key: "peripherals-mouse",
      label: "Mouse",
      hint: "Pointer speed and acceleration"
    }
  ]

  function valueFor(key) {
    if (key === "peripherals-keyboard")
      return "Shortcuts"
    if (key === "peripherals-mouse") {
      const sens = Config.mouseSensitivity
      const signed = sens > 0 ? ("+" + sens.toFixed(1)) : sens.toFixed(1)
      return signed + (Config.mouseAccelFlat ? " · flat" : " · adaptive")
    }
    return ""
  }

  ColumnLayout {
    visible: root.page === "peripherals"
    Layout.fillWidth: true
    Layout.maximumWidth: 420
    spacing: 6

    Text {
      Layout.fillWidth: true
      text: "Input devices. Headphones and speakers live under Sound."
      color: Theme.textMute
      font.family: Theme.fontFamily
      font.pixelSize: 12
      wrapMode: Text.WordWrap
      Layout.bottomMargin: 2
    }

    Repeater {
      model: root.sections

      Rectangle {
        required property var modelData
        Layout.fillWidth: true
        Layout.preferredHeight: 44
        radius: Theme.radiusMd
        color: rowMa.containsMouse ? Theme.bgHover : Theme.bgPanel
        border.width: 1
        border.color: Theme.border

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: Theme.spaceMd
          anchors.rightMargin: Theme.spaceMd
          spacing: Theme.spaceSm

          ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
            Text {
              text: modelData.label
              color: Theme.text
              font.family: Theme.fontFamily
              font.pixelSize: Theme.fontSize
            }
            Text {
              text: modelData.hint
              color: Theme.textMute
              font.family: Theme.fontFamily
              font.pixelSize: 11
            }
          }

          Text {
            text: root.valueFor(modelData.key)
            color: Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: 11
            elide: Text.ElideRight
            Layout.maximumWidth: 120
          }

          Text {
            text: "›"
            color: Theme.textDim
            font.pixelSize: 16
          }
        }

        MouseArea {
          id: rowMa
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.requestGo(modelData.key)
        }
      }
    }
  }
}
