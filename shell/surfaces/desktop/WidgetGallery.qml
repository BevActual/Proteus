import QtQuick
import QtQuick.Layouts
import "../../shared"

// Full-height Add Widget gallery sheet, shared by the lock and desktop
// Customize modes. Replaces LockWidgetGallery/DesktopWidgetGallery, which had
// diverged by 14 lines across 364 — all of it per-surface data, not structure.
//
// Set `scope` to "lock" or "desktop"; everything else derives from that plus
// Config.widgetCatalog.
Rectangle {
  id: root
  anchors.fill: parent
  color: Qt.rgba(0, 0, 0, 0.55)
  visible: false
  z: 50

  // "lock" | "desktop"
  property string scope: "desktop"
  property string pickSize: "md"
  signal closed()

  readonly property bool isLock: root.scope === "lock"
  readonly property var catalog: root.isLock ? Config.lockWidgetCatalog : Config.desktopWidgetCatalog
  readonly property string sizeHint: root.isLock
      ? "Size for new widgets"
      : "Size for new widgets — place freely on the desktop"
  readonly property string addedHint: root.isLock
      ? "Tap to enable or focus"
      : "Already on desktop — tap to focus size"

  function hasType(id) {
    return root.isLock ? Config.lockHasWidgetType(id) : Config.desktopHasWidgetType(id)
  }

  // The lock clock is chrome: pinned, always large, and hidden from the gallery
  // once present. The desktop clock is an ordinary widget.
  function entryVisible(id) {
    if (!root.isLock)
      return true
    return id !== "clock" || !Config.lockHasClockWidget
  }

  function showsAddedHint(id) {
    if (!root.hasType(id))
      return false
    return root.isLock ? id !== "clock" : true
  }

  function addWidget(id) {
    if (root.isLock) {
      if (id === "clock")
        Config.addLockWidget("clock", "lg")
      else
        Config.addLockWidget(id, root.pickSize)
      return
    }
    Config.addDesktopWidget(id, root.pickSize)
  }

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
    width: Math.min(420, parent.width - 32)
    height: Math.min(520, parent.height - 48)
    radius: 22
    color: Qt.rgba(28 / 255, 28 / 255, 30 / 255, 0.96)
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.1)
    clip: true

    MouseArea {
      anchors.fill: parent
      // absorb
    }

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: 16
      spacing: 12

      RowLayout {
        Layout.fillWidth: true
        Text {
          text: "Add Widget"
          color: "#f5f5f7"
          font.family: Theme.fontFamily
          font.pixelSize: 18
          font.weight: Font.Medium
          Layout.fillWidth: true
        }
        Text {
          text: "Close"
          color: Theme.accent
          font.pixelSize: 13
          MouseArea {
            anchors.fill: parent
            anchors.margins: -8
            onClicked: root.close()
          }
        }
      }

      Text {
        text: root.sizeHint
        color: Qt.rgba(1, 1, 1, 0.5)
        font.pixelSize: 11
      }

      RowLayout {
        spacing: 8
        Repeater {
          model: Config.widgetSizes
          Rectangle {
            required property var modelData
            Layout.preferredHeight: 30
            Layout.preferredWidth: 44
            radius: 15
            color: root.pickSize === modelData.id ? Theme.accent : Qt.rgba(1, 1, 1, 0.1)
            Text {
              anchors.centerIn: parent
              text: modelData.label
              color: "#fff"
              font.pixelSize: 12
              font.bold: true
            }
            MouseArea {
              anchors.fill: parent
              onClicked: root.pickSize = modelData.id
            }
          }
        }
      }

      Flickable {
        Layout.fillWidth: true
        Layout.fillHeight: true
        contentHeight: listCol.implicitHeight
        clip: true

        ColumnLayout {
          id: listCol
          width: parent.width
          spacing: 10

          Repeater {
            model: root.catalog
            Rectangle {
              required property var modelData
              Layout.fillWidth: true
              Layout.preferredHeight: 88
              radius: 16
              color: Qt.rgba(1, 1, 1, 0.06)
              border.width: 1
              border.color: Qt.rgba(1, 1, 1, 0.08)
              visible: root.entryVisible(modelData.id)

              RowLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 12

                Rectangle {
                  Layout.preferredWidth: 64
                  Layout.preferredHeight: 64
                  radius: 12
                  color: Qt.rgba(1, 1, 1, 0.08)
                  Text {
                    anchors.centerIn: parent
                    // Glyph comes from the catalog, so a new applet type does
                    // not need a case added here.
                    text: modelData.icon || "▫"
                    font.pixelSize: 26
                  }
                }

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: 2
                  Text {
                    text: modelData.label
                    color: "#f5f5f7"
                    font.family: Theme.fontFamily
                    font.pixelSize: 15
                    font.weight: Font.Medium
                  }
                  Text {
                    text: modelData.hint
                    color: Qt.rgba(1, 1, 1, 0.5)
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                  }
                  Text {
                    visible: root.showsAddedHint(modelData.id)
                    text: root.addedHint
                    color: Theme.accent
                    font.pixelSize: 10
                  }
                }
              }

              MouseArea {
                anchors.fill: parent
                onClicked: {
                  root.addWidget(modelData.id)
                  root.close()
                }
              }
            }
          }
        }
      }
    }
  }
}
