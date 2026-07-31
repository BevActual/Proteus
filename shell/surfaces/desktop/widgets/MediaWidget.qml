import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris
import "../../../shared"

// Now playing card (MPRIS) — shared by the lock and desktop surfaces.
// Added / configured via the surface's Customize mode (see Widgets.widgetCatalog).
Item {
  id: root
  property string size: "md"
  property bool showControls: true
  property bool showWhenIdle: false

  readonly property int cardWidth: {
    if (size === "sm")
      return 220
    if (size === "lg")
      return 360
    return 300
  }
  readonly property int artSize: size === "sm" ? 44 : (size === "lg" ? 64 : 56)

  width: parent ? Math.min(cardWidth, parent.width) : cardWidth
  implicitWidth: width
  implicitHeight: visible ? card.implicitHeight : 0
  height: implicitHeight

  readonly property var player: {
    const vals = Mpris.players.values
    let idle = null
    for (let i = 0; i < vals.length; i++) {
      const p = vals[i]
      if (!p)
        continue
      if (p.isPlaying)
        return p
      if (!idle)
        idle = p
    }
    return idle
  }

  readonly property bool hasTrack: {
    const p = root.player
    if (!p)
      return false
    return !!(p.trackTitle && String(p.trackTitle).length)
        || !!(p.trackArtist && String(p.trackArtist).length)
        || !!(p.trackArtUrl && String(p.trackArtUrl).length)
  }

  visible: {
    if (!root.player)
      return !!root.showWhenIdle
    if (root.player.isPlaying || root.hasTrack)
      return true
    return !!root.showWhenIdle
  }

  Rectangle {
    id: card
    anchors.left: parent.left
    anchors.right: parent.right
    implicitHeight: body.implicitHeight + 24
    radius: 18
    color: Qt.rgba(28 / 255, 28 / 255, 30 / 255, 0.72)
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.1)

    // Absorb clicks so the lock backdrop doesn't steal them for auth reveal.
    MouseArea {
      anchors.fill: parent
      z: -1
      onClicked: {}
    }

    ColumnLayout {
      id: body
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: 12
      spacing: 10

      RowLayout {
        Layout.fillWidth: true
        spacing: 12

        Rectangle {
          Layout.preferredWidth: root.artSize
          Layout.preferredHeight: root.artSize
          radius: 10
          color: Qt.rgba(1, 1, 1, 0.08)
          clip: true

          Image {
            anchors.fill: parent
            visible: root.player && root.player.trackArtUrl && String(root.player.trackArtUrl).length
            source: root.player && root.player.trackArtUrl ? root.player.trackArtUrl : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
          }

          Text {
            anchors.centerIn: parent
            visible: !(root.player && root.player.trackArtUrl && String(root.player.trackArtUrl).length)
            text: "♪"
            color: Qt.rgba(1, 1, 1, 0.45)
            font.pixelSize: 22
          }
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: 2

          Text {
            Layout.fillWidth: true
            text: root.player && root.player.trackTitle && String(root.player.trackTitle).length
                ? root.player.trackTitle
                : (root.player ? "Not playing" : "No media")
            color: "#f5f5f7"
            font.family: Theme.fontFamily
            font.pixelSize: 15
            font.weight: Font.Medium
            elide: Text.ElideRight
          }

          Text {
            Layout.fillWidth: true
            visible: root.player && root.player.trackArtist && String(root.player.trackArtist).length
            text: root.player ? (root.player.trackArtist || "") : ""
            color: Qt.rgba(1, 1, 1, 0.62)
            font.family: Theme.fontFamily
            font.pixelSize: 12
            elide: Text.ElideRight
          }

          Text {
            Layout.fillWidth: true
            visible: root.player && root.player.identity && String(root.player.identity).length
            text: root.player ? String(root.player.identity) : ""
            color: Qt.rgba(1, 1, 1, 0.38)
            font.family: Theme.fontFamily
            font.pixelSize: 11
            elide: Text.ElideRight
          }
        }
      }

      RowLayout {
        visible: root.showControls && !!root.player
        Layout.alignment: Qt.AlignHCenter
        spacing: 18

        Text {
          text: "⏮"
          color: root.player && root.player.canGoPrevious ? "#f5f5f7" : Qt.rgba(1, 1, 1, 0.28)
          font.pixelSize: 18
          MouseArea {
            anchors.fill: parent
            anchors.margins: -8
            enabled: root.player && root.player.canGoPrevious
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              if (root.player)
                root.player.previous()
            }
          }
        }

        Text {
          text: root.player && root.player.isPlaying ? "⏸" : "▶"
          color: root.player && root.player.canTogglePlaying ? "#f5f5f7" : Qt.rgba(1, 1, 1, 0.28)
          font.pixelSize: 20
          MouseArea {
            anchors.fill: parent
            anchors.margins: -8
            enabled: root.player && root.player.canTogglePlaying
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              if (root.player)
                root.player.togglePlaying()
            }
          }
        }

        Text {
          text: "⏭"
          color: root.player && root.player.canGoNext ? "#f5f5f7" : Qt.rgba(1, 1, 1, 0.28)
          font.pixelSize: 18
          MouseArea {
            anchors.fill: parent
            anchors.margins: -8
            enabled: root.player && root.player.canGoNext
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              if (root.player)
                root.player.next()
            }
          }
        }
      }
    }
  }
}
