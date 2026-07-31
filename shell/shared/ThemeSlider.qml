import QtQuick
import QtQuick.Controls

// Theme-tokened Slider — accent fill on a hairline groove, macOS-adjacent knob.
// Drop-in for the stock Controls Slider (same API); used by Settings panes and
// shell chrome so every level control speaks one language (CHROME §9).
Slider {
  id: control

  implicitWidth: 120
  implicitHeight: 22
  opacity: enabled ? 1 : 0.45

  background: Rectangle {
    x: control.leftPadding
    y: control.topPadding + control.availableHeight / 2 - height / 2
    width: control.availableWidth
    height: 4
    radius: 2
    color: Theme.light ? Qt.rgba(0, 0, 0, 0.10) : Qt.rgba(1, 1, 1, 0.14)

    Rectangle {
      width: control.visualPosition * parent.width
      height: parent.height
      radius: 2
      color: Theme.accent
    }
  }

  handle: Rectangle {
    x: control.leftPadding + control.visualPosition * (control.availableWidth - width)
    y: control.topPadding + control.availableHeight / 2 - height / 2
    width: 18
    height: 18
    radius: 9
    color: control.pressed ? (Theme.light ? "#f0f0f2" : "#e6e6ea") : "#ffffff"
    border.width: 1
    border.color: Qt.rgba(0, 0, 0, 0.22)
  }
}
