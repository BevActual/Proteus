import Quickshell
import QtQuick

Item {
  id: root

  // Optional overrides for lock screen; desktop proteus-bg leaves these unset.
  property string effectId: ""
  property bool customAccent: false
  property color accentColor: "#3d8bfd"

  readonly property string effect: (root.effectId && root.effectId.length)
      ? root.effectId
      : (BgConfig.wallpaperReactiveId || "drift")
  readonly property color accent: root.customAccent ? root.accentColor : BgConfig.accentColor
  property real pulseLevel: 0.15

  // Only the pulse effect needs a live level; everything else is pure animation.
  // Subscribing (rather than polling) keeps the reader off entirely otherwise.
  readonly property bool wantsPeaks: root.effect === "pulse" && root.visible
  property bool _peaksHeld: false

  function _syncPeakSubscription() {
    if (root.wantsPeaks === root._peaksHeld)
      return
    root._peaksHeld = root.wantsPeaks
    if (root.wantsPeaks)
      BgConfig.subscribePeaks()
    else
      BgConfig.unsubscribePeaks()
  }

  onWantsPeaksChanged: root._syncPeakSubscription()
  Component.onCompleted: root._syncPeakSubscription()
  Component.onDestruction: {
    if (root._peaksHeld) {
      root._peaksHeld = false
      BgConfig.unsubscribePeaks()
    }
  }

  // Fast attack, slow release. This ticks on its own rather than off
  // lastPeakChanged so a run of identical values (silence reads 0 forever)
  // still decays the level instead of freezing it mid-fade. Pure arithmetic —
  // no process work, unlike the sampler this replaced.
  Timer {
    interval: 100
    repeat: true
    running: root.wantsPeaks
    onTriggered: {
      const n = Math.max(0, Math.min(1, BgConfig.lastPeak / 100))
      if (n >= root.pulseLevel)
        root.pulseLevel = n
      else
        root.pulseLevel = root.pulseLevel * 0.72 + n * 0.28
    }
  }

  Rectangle {
    anchors.fill: parent
    color: "#0f1419"
  }

  Item {
    visible: root.effect === "drift"
    anchors.fill: parent

    Rectangle {
      width: parent.width * 1.4
      height: parent.height * 1.4
      radius: width
      color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.22)
      x: -parent.width * 0.2
      y: -parent.height * 0.25

      SequentialAnimation on x {
        loops: Animation.Infinite
        NumberAnimation {
          to: parent.width * 0.15
          duration: 18000
          easing.type: Easing.InOutSine
        }
        NumberAnimation {
          to: -parent.width * 0.2
          duration: 18000
          easing.type: Easing.InOutSine
        }
      }
      SequentialAnimation on y {
        loops: Animation.Infinite
        NumberAnimation {
          to: parent.height * 0.1
          duration: 22000
          easing.type: Easing.InOutSine
        }
        NumberAnimation {
          to: -parent.height * 0.25
          duration: 22000
          easing.type: Easing.InOutSine
        }
      }
    }

    Rectangle {
      width: parent.width * 1.2
      height: parent.height * 1.2
      radius: width
      color: Qt.rgba(0.2, 0.35, 0.55, 0.18)
      x: parent.width * 0.4
      y: parent.height * 0.35

      SequentialAnimation on x {
        loops: Animation.Infinite
        NumberAnimation {
          to: parent.width * 0.15
          duration: 20000
          easing.type: Easing.InOutSine
        }
        NumberAnimation {
          to: parent.width * 0.4
          duration: 20000
          easing.type: Easing.InOutSine
        }
      }
    }
  }

  Item {
    visible: root.effect === "pulse"
    anchors.fill: parent

    Rectangle {
      anchors.centerIn: parent
      width: parent.width * (0.55 + root.pulseLevel * 0.7)
      height: parent.height * (0.55 + root.pulseLevel * 0.7)
      radius: width
      color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.12 + root.pulseLevel * 0.35)
    }

    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.04 + root.pulseLevel * 0.12)
    }
  }

  Item {
    visible: root.effect === "orbit"
    anchors.fill: parent

    Rectangle {
      id: orb
      width: Math.min(parent.width, parent.height) * 0.55
      height: width
      radius: width / 2
      color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.28)
      property real ox: 0
      property real oy: 0
      x: (parent.width - width) / 2 + ox
      y: (parent.height - height) / 2 + oy

      SequentialAnimation on ox {
        loops: Animation.Infinite
        NumberAnimation {
          to: 180
          duration: 9000
          easing.type: Easing.InOutSine
        }
        NumberAnimation {
          to: -180
          duration: 9000
          easing.type: Easing.InOutSine
        }
        NumberAnimation {
          to: 0
          duration: 9000
          easing.type: Easing.InOutSine
        }
      }
      SequentialAnimation on oy {
        loops: Animation.Infinite
        NumberAnimation {
          to: -120
          duration: 11000
          easing.type: Easing.InOutSine
        }
        NumberAnimation {
          to: 120
          duration: 11000
          easing.type: Easing.InOutSine
        }
        NumberAnimation {
          to: 0
          duration: 11000
          easing.type: Easing.InOutSine
        }
      }
    }

    Rectangle {
      anchors.fill: parent
      gradient: Gradient {
        GradientStop {
          position: 0.0
          color: "#00000000"
        }
        GradientStop {
          position: 1.0
          color: Qt.rgba(0.05, 0.08, 0.12, 0.55)
        }
      }
    }
  }

  // —— Aurora ——
  Item {
    visible: root.effect === "aurora"
    anchors.fill: parent

    Rectangle {
      width: parent.width * 1.5
      height: parent.height * 0.45
      radius: height
      color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.28)
      y: parent.height * 0.15
      x: -parent.width * 0.2
      SequentialAnimation on x {
        loops: Animation.Infinite
        NumberAnimation {
          to: parent.width * 0.1
          duration: 14000
          easing.type: Easing.InOutSine
        }
        NumberAnimation {
          to: -parent.width * 0.2
          duration: 14000
          easing.type: Easing.InOutSine
        }
      }
    }
    Rectangle {
      width: parent.width * 1.4
      height: parent.height * 0.4
      radius: height
      color: Qt.rgba(0.2, 0.7, 0.75, 0.18)
      y: parent.height * 0.4
      x: parent.width * 0.1
      SequentialAnimation on x {
        loops: Animation.Infinite
        NumberAnimation {
          to: -parent.width * 0.15
          duration: 17000
          easing.type: Easing.InOutSine
        }
        NumberAnimation {
          to: parent.width * 0.1
          duration: 17000
          easing.type: Easing.InOutSine
        }
      }
    }
    Rectangle {
      width: parent.width * 1.3
      height: parent.height * 0.35
      radius: height
      color: Qt.rgba(0.55, 0.35, 0.9, 0.16)
      y: parent.height * 0.55
      x: -parent.width * 0.1
      SequentialAnimation on y {
        loops: Animation.Infinite
        NumberAnimation {
          to: parent.height * 0.45
          duration: 16000
          easing.type: Easing.InOutSine
        }
        NumberAnimation {
          to: parent.height * 0.55
          duration: 16000
          easing.type: Easing.InOutSine
        }
      }
    }
  }

  // —— Beacon ——
  Item {
    visible: root.effect === "beacon"
    anchors.fill: parent

    Rectangle {
      id: beacon
      anchors.centerIn: parent
      width: Math.min(parent.width, parent.height) * 0.35
      height: width
      radius: width / 2
      color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.32)
      property real scaleFactor: 1
      scale: scaleFactor

      SequentialAnimation on scaleFactor {
        loops: Animation.Infinite
        NumberAnimation {
          to: 1.55
          duration: 2400
          easing.type: Easing.InOutSine
        }
        NumberAnimation {
          to: 1.0
          duration: 2400
          easing.type: Easing.InOutSine
        }
      }
      SequentialAnimation on opacity {
        loops: Animation.Infinite
        NumberAnimation {
          to: 0.35
          duration: 2400
          easing.type: Easing.InOutSine
        }
        NumberAnimation {
          to: 0.9
          duration: 2400
          easing.type: Easing.InOutSine
        }
      }
    }

    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.06)
    }
  }
}
