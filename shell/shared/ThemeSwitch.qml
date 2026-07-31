import QtQuick
import QtQuick.Controls

// Theme-tokened Switch — accent track, white thumb (System Settings posture).
// Drop-in for the stock Controls Switch (same API); accent = state, not wash.
Switch {
  id: control

  implicitWidth: 44 + leftPadding + rightPadding
  implicitHeight: 26
  opacity: enabled ? 1 : 0.45

  indicator: Rectangle {
    implicitWidth: 44
    implicitHeight: 26
    x: control.leftPadding
    y: control.topPadding + (control.availableHeight - height) / 2
    radius: height / 2
    color: control.checked
        ? Theme.accent
        : (Theme.light ? Qt.rgba(0, 0, 0, 0.14) : Qt.rgba(1, 1, 1, 0.20))
    border.width: control.checked ? 0 : 1
    border.color: Theme.light ? Qt.rgba(0, 0, 0, 0.06) : Qt.rgba(1, 1, 1, 0.08)

    Behavior on color {
      ColorAnimation {
        duration: 140
        easing.type: Easing.OutCubic
      }
    }

    Rectangle {
      x: control.checked ? parent.width - width - 3 : 3
      anchors.verticalCenter: parent.verticalCenter
      width: 20
      height: 20
      radius: 10
      color: "#ffffff"
      border.width: 1
      border.color: Qt.rgba(0, 0, 0, 0.10)

      Behavior on x {
        NumberAnimation {
          duration: 140
          easing.type: Easing.OutCubic
        }
      }
    }
  }
}
