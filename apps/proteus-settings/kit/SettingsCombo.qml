import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../shared"

// Trailing popup picker — System Settings density on Theme tokens (not Fusion ComboBox).
Item {
  id: root
  Layout.preferredWidth: preferredWidth
  Layout.preferredHeight: 28
  implicitWidth: preferredWidth
  implicitHeight: 28

  property int preferredWidth: 168
  property var model: []
  property string currentValue: ""
  property bool enabled: true
  signal activated(string id)

  readonly property string currentLabel: {
    const list = root.model || []
    for (let i = 0; i < list.length; i++) {
      if (String(list[i].id) === String(root.currentValue))
        return String(list[i].label || list[i].id)
    }
    if (root.currentValue.length)
      return root.currentValue
    return "—"
  }

  function pick(id) {
    const v = String(id)
    popup.close()
    if (v === String(root.currentValue))
      return
    root.activated(v)
  }

  Rectangle {
    id: chip
    anchors.fill: parent
    radius: Theme.radiusSm
    color: !root.enabled ? "transparent"
        : (popup.visible || ma.containsMouse ? Theme.bgHover : Theme.bgHover)
    opacity: root.enabled ? 1 : 0.45
    border.width: 1
    border.color: popup.visible ? Theme.border : (Theme.light ? Theme.separator : Theme.border)

    Behavior on border.color {
      ColorAnimation { duration: 120; easing.type: Easing.OutCubic }
    }

    RowLayout {
      anchors.fill: parent
      anchors.leftMargin: Theme.spaceSm
      anchors.rightMargin: Theme.spaceSm
      spacing: Theme.spaceXs

      Text {
        Layout.fillWidth: true
        text: root.currentLabel
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: 12
        elide: Text.ElideRight
        verticalAlignment: Text.AlignVCenter
      }

      Text {
        text: "▾"
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: 10
        Layout.alignment: Qt.AlignVCenter
      }
    }

    MouseArea {
      id: ma
      anchors.fill: parent
      enabled: root.enabled
      hoverEnabled: true
      cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: {
        if (popup.visible)
          popup.close()
        else
          popup.open()
      }
    }
  }

  Popup {
    id: popup
    // Estimated final height (32px rows · 1px spacing · 4px padding) — known
    // before the content item instantiates, so the flip decision is stable.
    readonly property int estHeight: {
      const n = Math.max((root.model || []).length, 1)
      return Math.min(n * 32 + (n - 1) * 1, 280) + 8
    }
    // Flip above the chip when the list would clip at the window bottom
    // (popups cannot render outside the window).
    property bool openUp: false
    y: openUp ? -(estHeight + 4) : chip.height + 4
    x: Math.min(0, root.width - width)
    width: Math.max(root.width, 168)
    padding: 4
    // Non-negative margins let Qt push the popup back inside the window if
    // neither direction fully fits (small windows).
    margins: 4
    // Parent includes the chip — CloseOnPressOutside would flash-close on chip press.
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
    modal: false

    onAboutToShow: {
      const win = root.Window.window
      if (!win) {
        openUp = false
        return
      }
      const pos = root.mapToItem(null, 0, 0)
      const fitsBelow = pos.y + chip.height + 4 + estHeight <= win.height - 4
      const fitsAbove = pos.y - 4 - estHeight >= 4
      openUp = !fitsBelow && fitsAbove
    }

    background: Rectangle {
      radius: Theme.radiusMd
      color: Theme.bgElevated
      border.width: 1
      border.color: Theme.border
    }

    contentItem: ListView {
      id: list
      clip: true
      implicitHeight: Math.min(contentHeight, 280)
      model: root.model
      spacing: 1
      boundsBehavior: Flickable.StopAtBounds

      delegate: Rectangle {
        required property var modelData
        width: list.width
        height: 32
        radius: Theme.radiusSm
        color: {
          if (String(modelData.id) === String(root.currentValue))
            return Theme.accentSoft
          if (rowMa.containsMouse)
            return Theme.bgHover
          return "transparent"
        }

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: Theme.spaceSm
          anchors.rightMargin: Theme.spaceSm
          spacing: Theme.spaceSm

          Text {
            Layout.fillWidth: true
            text: String(modelData.label || modelData.id)
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: 12
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
          }

          Text {
            visible: String(modelData.id) === String(root.currentValue)
            text: "✓"
            color: Theme.accent
            font.pixelSize: 13
          }
        }

        MouseArea {
          id: rowMa
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.pick(modelData.id)
        }
      }
    }
  }
}
