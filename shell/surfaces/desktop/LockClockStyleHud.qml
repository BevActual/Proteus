import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../shared"

Rectangle {
  id: root
  visible: !!clockWidget
  property var clockWidget: null
  radius: 18
  color: Qt.rgba(28 / 255, 28 / 255, 30 / 255, 0.92)
  border.width: 1
  border.color: Qt.rgba(1, 1, 1, 0.12)
  implicitHeight: col.implicitHeight + 20
  implicitWidth: 320

  ColumnLayout {
    id: col
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: 12
    spacing: 8

    Text {
      text: "Clock style"
      color: "#f5f5f7"
      font.family: Theme.fontFamily
      font.pixelSize: 13
      font.weight: Font.Medium
    }

    RowLayout {
      spacing: 6
      Repeater {
        model: Config.lockClockWeights
        Rectangle {
          required property var modelData
          Layout.preferredHeight: 28
          Layout.preferredWidth: lab.implicitWidth + 16
          radius: 14
          color: root.clockWidget && root.clockWidget.clockWeight === modelData.id ? Theme.accent : Qt.rgba(1, 1, 1, 0.1)
          Text {
            id: lab
            anchors.centerIn: parent
            text: modelData.label
            color: "#fff"
            font.pixelSize: 11
          }
          MouseArea {
            anchors.fill: parent
            onClicked: {
              if (root.clockWidget)
                Config.patchLockWidget(root.clockWidget.id, { clockWeight: modelData.id })
            }
          }
        }
      }
    }

    RowLayout {
      spacing: 8
      Repeater {
        model: ["#f5f5f7", "#ffffff", "#d1d1d6", "#3d8bfd"]
        Rectangle {
          required property var modelData
          width: 28
          height: 28
          radius: 14
          color: modelData
          border.width: root.clockWidget && String(root.clockWidget.clockColor) === String(modelData) ? 2 : 1
          border.color: "#fff"
          MouseArea {
            anchors.fill: parent
            onClicked: {
              if (root.clockWidget)
                Config.patchLockWidget(root.clockWidget.id, { clockColor: String(modelData) })
            }
          }
        }
      }
    }

    RowLayout {
      Text {
        text: "Date"
        color: Qt.rgba(1, 1, 1, 0.7)
        font.pixelSize: 12
        Layout.fillWidth: true
      }
      Switch {
        checked: root.clockWidget ? root.clockWidget.showDate !== false : true
        onToggled: {
          if (root.clockWidget)
            Config.patchLockWidget(root.clockWidget.id, { showDate: checked })
        }
      }
    }

    RowLayout {
      spacing: 6
      visible: root.clockWidget && root.clockWidget.showDate !== false
      Repeater {
        model: Config.lockClockDateStyles
        Rectangle {
          required property var modelData
          Layout.preferredHeight: 28
          Layout.preferredWidth: dlab.implicitWidth + 16
          radius: 14
          color: root.clockWidget && root.clockWidget.dateStyle === modelData.id ? Theme.accent : Qt.rgba(1, 1, 1, 0.1)
          Text {
            id: dlab
            anchors.centerIn: parent
            text: modelData.label
            color: "#fff"
            font.pixelSize: 11
          }
          MouseArea {
            anchors.fill: parent
            onClicked: {
              if (root.clockWidget)
                Config.patchLockWidget(root.clockWidget.id, { dateStyle: modelData.id })
            }
          }
        }
      }
    }

    RowLayout {
      Text {
        text: "Depth"
        color: Qt.rgba(1, 1, 1, 0.7)
        font.pixelSize: 12
        Layout.fillWidth: true
      }
      Switch {
        checked: root.clockWidget ? root.clockWidget.clockDepth !== false : true
        onToggled: {
          if (root.clockWidget)
            Config.patchLockWidget(root.clockWidget.id, { clockDepth: checked })
        }
      }
    }
  }
}
