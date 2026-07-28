import QtQuick
import QtQuick.Layouts
import "../../shared"

Rectangle {
  id: root
  anchors.fill: parent
  color: Qt.rgba(0, 0, 0, 0.55)
  visible: false
  z: 50

  signal closed()

  function open() {
    visible = true
  }
  function close() {
    visible = false
    closed()
  }

  MouseArea {
    anchors.fill: parent
    onClicked: root.close()
  }

  Rectangle {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.verticalCenter: parent.verticalCenter
    width: Math.min(400, parent.width - 32)
    height: Math.min(460, parent.height - 48)
    radius: 22
    color: Qt.rgba(28 / 255, 28 / 255, 30 / 255, 0.96)
    clip: true

    MouseArea {
      anchors.fill: parent
    }

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: 16
      spacing: 8

      Text {
        text: "Lock wallpaper"
        color: "#f5f5f7"
        font.family: Theme.fontFamily
        font.pixelSize: 18
        font.weight: Font.Medium
      }

      Flickable {
        Layout.fillWidth: true
        Layout.fillHeight: true
        contentHeight: kinds.implicitHeight
        clip: true

        ColumnLayout {
          id: kinds
          width: parent.width
          spacing: 4

          Repeater {
            model: Background.lockBackgroundModes
            Rectangle {
              required property var modelData
              Layout.fillWidth: true
              Layout.preferredHeight: 48
              radius: 12
              color: Config.lockBackgroundMode === modelData.id ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35) : Qt.rgba(1, 1, 1, 0.06)
              RowLayout {
                anchors.fill: parent
                anchors.margins: 12
                Text {
                  text: modelData.label
                  color: "#f5f5f7"
                  font.pixelSize: 14
                  Layout.fillWidth: true
                }
                Text {
                  visible: Config.lockBackgroundMode === modelData.id
                  text: "✓"
                  color: Theme.accent
                }
              }
              MouseArea {
                anchors.fill: parent
                onClicked: {
                  if (modelData.id === "image") {
                    Config.setLockBackgroundMode("image")
                  } else if (modelData.id === "video") {
                    // Keep mode; user picks file in Settings — still switch mode if path exists
                    if (Config.lockWallpaperVideoPath && String(Config.lockWallpaperVideoPath).length)
                      Config.setLockBackgroundMode("video")
                    else
                      Config.setLockBackgroundMode("video")
                  } else if (modelData.id === "reactive") {
                    Config.setLockWallpaperReactive(Config.lockWallpaperReactiveId || "drift")
                  } else {
                    Config.setLockBackgroundMode(modelData.id)
                  }
                  root.close()
                }
              }
            }
          }
        }
      }

      Text {
        text: "For image / video files, use Settings → Lock for full pickers."
        color: Qt.rgba(1, 1, 1, 0.45)
        font.pixelSize: 11
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
      }
    }
  }
}
