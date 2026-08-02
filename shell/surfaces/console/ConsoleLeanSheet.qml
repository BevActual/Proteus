import QtQuick
import QtQuick.Layouts
import "../../shared"

// Lean-back modal sheet — Media picker / Hero details (pad: Ⓐ select · Ⓑ close).
Item {
  id: root
  anchors.fill: parent
  visible: open
  z: 25

  property bool open: false
  property string title: ""
  property string subtitle: ""
  property var options: [] // [{ label, hint, id }]
  property int focusedIndex: 0
  property string primaryLabel: "Open"
  property bool showPrimary: false

  signal closed()
  signal optionActivated(var option)
  signal primaryActivated()

  function openSheet() {
    focusedIndex = 0
    open = true
  }

  function closeSheet() {
    open = false
    closed()
  }

  function move(delta) {
    if (!options.length)
      return
    focusedIndex = Math.max(0, Math.min(options.length - 1, focusedIndex + delta))
  }

  function activateFocused() {
    if (showPrimary && focusedIndex < 0) {
      primaryActivated()
      return
    }
    if (!options.length)
      return
    const opt = options[Math.max(0, Math.min(options.length - 1, focusedIndex))]
    optionActivated(opt)
  }

  Rectangle {
    anchors.fill: parent
    color: Theme.scrimFill
    MouseArea {
      anchors.fill: parent
      onClicked: root.closeSheet()
    }
  }

  Rectangle {
    anchors.centerIn: parent
    width: Math.min(parent.width - 64, 480)
    height: sheetCol.implicitHeight + Theme.spaceLg * 2
    radius: Theme.radiusXl
    color: Theme.menuPlateFill
    border.width: 1
    border.color: Theme.chromeBorder

    ColumnLayout {
      id: sheetCol
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Theme.spaceLg
      spacing: Theme.spaceMd

      Text {
        Layout.fillWidth: true
        text: root.title
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize + 4
        font.weight: Font.DemiBold
        wrapMode: Text.WordWrap
      }

      Text {
        Layout.fillWidth: true
        visible: root.subtitle.length > 0
        text: root.subtitle
        color: Theme.textDim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        wrapMode: Text.WordWrap
      }

      Repeater {
        model: root.options
        Rectangle {
          required property var modelData
          required property int index
          Layout.fillWidth: true
          Layout.preferredHeight: 48
          radius: Theme.radiusLg
          color: root.focusedIndex === index ? Theme.chromeAccentSoft : Theme.elevatedFill
          border.width: root.focusedIndex === index ? 2 : 1
          border.color: root.focusedIndex === index ? Theme.accent : Theme.chromeBorder

          ColumnLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.spaceMd
            anchors.rightMargin: Theme.spaceMd
            spacing: 0
            Text {
              text: modelData.label || ""
              color: Theme.text
              font.family: Theme.fontFamily
              font.pixelSize: Theme.fontSize
              font.weight: Font.Medium
            }
            Text {
              visible: !!(modelData.hint && String(modelData.hint).length)
              text: modelData.hint || ""
              color: Theme.textMute
              font.family: Theme.fontFamily
              font.pixelSize: Theme.fontSizeSm
              elide: Text.ElideRight
              Layout.fillWidth: true
            }
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.focusedIndex = index
              root.optionActivated(modelData)
            }
          }
        }
      }

      Rectangle {
        visible: root.showPrimary
        Layout.fillWidth: true
        Layout.preferredHeight: 44
        radius: Theme.radiusLg
        color: Theme.accent
        Text {
          anchors.centerIn: parent
          text: "Ⓐ  " + root.primaryLabel
          color: "#ffffff"
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSize
          font.weight: Font.DemiBold
        }
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.primaryActivated()
        }
      }

      Text {
        Layout.fillWidth: true
        text: "Ⓐ Select   Ⓑ Close"
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSm
        horizontalAlignment: Text.AlignHCenter
      }
    }
  }
}
