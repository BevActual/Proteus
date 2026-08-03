import Quickshell
import QtQuick
import QtQuick.Layouts
import ".."

// Apple-style inset group — optional section title + elevated card.
ColumnLayout {
  id: root
  Layout.fillWidth: true
  Layout.maximumWidth: 480
  spacing: 6

  property string title: ""
  default property alias contentData: body.data

  Text {
    visible: root.title.length > 0
    Layout.fillWidth: true
    Layout.leftMargin: Theme.spaceSm
    text: root.title
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 12
    font.capitalization: Font.AllUppercase
  }

  Rectangle {
    Layout.fillWidth: true
    implicitHeight: body.implicitHeight
    radius: Theme.radiusLg
    color: Theme.bgElevated
    clip: true

    ColumnLayout {
      id: body
      width: parent.width
      spacing: 0
    }
  }
}
