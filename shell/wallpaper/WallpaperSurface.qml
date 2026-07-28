import QtQuick
import QtMultimedia

Item {
  id: root
  anchors.fill: parent

  readonly property string kind: BgConfig.wallpaperKind || "image"
  readonly property bool showStill: kind === "image" || kind === "daily"
  readonly property bool isDaily: kind === "daily" || BgConfig.wallpaperId === "daily"

  Timer {
    interval: Math.max(5, BgConfig.wallpaperSlideshowSecs || 60) * 1000
    repeat: true
    running: root.kind === "image" && BgConfig.wallpaperSlideshow
    onTriggered: BgConfig.advanceSlideshow()
  }

  // Periodic daily feed refresh (fetch script + settings.json; FileView reloads path)
  Timer {
    interval: Math.max(1, BgConfig.wallpaperDailyRefreshHours || 6) * 3600 * 1000
    repeat: true
    running: root.isDaily
    triggeredOnStart: false
    onTriggered: BgConfig.refreshDailyWallpaper()
  }

  Rectangle {
    anchors.fill: parent
    visible: root.kind === "color"
    color: BgConfig.solidColor
  }

  Rectangle {
    anchors.fill: parent
    visible: root.showStill
    color: "#0a0e14"
    Image {
      id: wallImage
      anchors.fill: parent
      // Cache-bust query so built-in / daily swaps always reload.
      source: (root.showStill && BgConfig.activeImagePath && BgConfig.activeImagePath.length)
          ? ("file://" + BgConfig.activeImagePath + "#" + BgConfig.wallpaperId + "," + BgConfig.wallpaperCustomPath + "," + BgConfig.slideshowPath + "," + BgConfig.wallpaperDailyFetchedAt)
          : ""
      fillMode: BgConfig.imageFillMode
      asynchronous: true
      cache: false
    }
  }

  Item {
    anchors.fill: parent
    visible: root.kind === "video"

    Rectangle {
      anchors.fill: parent
      color: "#0a0e14"
    }

    VideoOutput {
      id: videoOut
      anchors.fill: parent
      fillMode: {
        switch (BgConfig.wallpaperMode) {
        case "fit":
          return VideoOutput.PreserveAspectFit
        case "stretch":
          return VideoOutput.Stretch
        default:
          return VideoOutput.PreserveAspectCrop
        }
      }
      visible: root.kind === "video" && BgConfig.wallpaperVideoPath && String(BgConfig.wallpaperVideoPath).length
    }

    MediaPlayer {
      id: player
      videoOutput: videoOut
      audioOutput: AudioOutput {
        muted: true
      }
      source: (root.kind === "video" && BgConfig.wallpaperVideoPath && String(BgConfig.wallpaperVideoPath).length)
          ? ("file://" + BgConfig.wallpaperVideoPath)
          : ""
      loops: MediaPlayer.Infinite
      onSourceChanged: {
        if (root.kind === "video" && source.toString().length)
          play()
        else
          stop()
      }
      onErrorOccurred: (err, errStr) => {
        console.warn("proteus-bg video:", errStr)
      }
    }

    Text {
      anchors.centerIn: parent
      visible: root.kind === "video" && !(BgConfig.wallpaperVideoPath && String(BgConfig.wallpaperVideoPath).length)
      text: "No video selected"
      color: "#8b9bb0"
      font.pixelSize: 14
    }

    Connections {
      target: BgConfig
      function onWallpaperKindChanged() {
        if (root.kind === "video" && player.source.toString().length)
          player.play()
        else
          player.stop()
      }
      function onWallpaperVideoPathChanged() {
        if (root.kind === "video" && player.source.toString().length)
          player.play()
      }
    }
  }

  ReactiveBg {
    anchors.fill: parent
    visible: root.kind === "reactive"
  }
}
