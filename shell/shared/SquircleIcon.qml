import QtQuick
import QtQuick.Effects

// macOS-style squircle — plate + Default/Dark/Clear/Tinted glyph treatment
Item {
  id: root

  property alias source: img.source
  property int pixelSize: 128
  property real cornerRatio: Theme.squircleCornerRatio
  property bool fillCrop: false
  property real glyphScale: 0.72
  property bool showBorder: false
  property color plate: Theme.iconPlateFill
  property color borderColor: Qt.rgba(1, 1, 1, 0.14)
  // When false, skip Dark/Clear/Tinted effects (raw artwork)
  property bool styleEnabled: true
  // Optional overrides for style comparison previews (Settings Icons leaf).
  property string styleModeOverride: ""
  property color plateOverride: "transparent"
  property color tintOverride: "transparent"

  readonly property string styleMode: {
    if (root.styleModeOverride.length)
      return root.styleModeOverride
    return root.styleEnabled ? Config.iconPlateStyle : "default"
  }
  readonly property bool styled: styleMode === "dark" || styleMode === "clear" || styleMode === "tinted"
  readonly property color tintColor: {
    if (root.tintOverride.a > 0)
      return root.tintOverride
    const h = Config.normalizeAccentHex(Config.iconPlateCustom)
    if (h.length)
      return h
    return Theme.accent
  }
  readonly property color plateColor: root.plateOverride.a > 0 ? root.plateOverride : root.plate

  width: 48
  height: width

  Rectangle {
    id: body
    anchors.fill: parent
    radius: width * root.cornerRatio
    color: root.plateColor
    clip: true
    antialiasing: true
    border.width: root.showBorder ? 1 : 0
    border.color: root.borderColor

    // Clear — soft glass wash over the plate
    Rectangle {
      anchors.fill: parent
      visible: root.styleMode === "clear"
      radius: parent.radius
      color: Theme.light ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.10)
      z: 0
    }

    Item {
      id: glyphBox
      anchors.centerIn: parent
      width: parent.width * (root.fillCrop ? 1.0 : root.glyphScale)
      height: width
      z: 1

      Image {
        id: img
        anchors.fill: parent
        fillMode: root.fillCrop ? Image.PreserveAspectCrop : Image.PreserveAspectFit
        smooth: true
        mipmap: false
        asynchronous: true
        sourceSize.width: root.pixelSize
        sourceSize.height: root.pixelSize
        // Hidden when MultiEffect draws it; kept as texture source
        visible: !root.styled
        opacity: root.styleMode === "clear" ? 0.88 : 1.0
      }

      MultiEffect {
        id: fx
        anchors.fill: parent
        source: img
        visible: root.styled
        autoPaddingEnabled: false
        // Dark / Tinted: grayscale then recolor; Clear: slight lift
        saturation: (root.styleMode === "dark" || root.styleMode === "tinted") ? -1.0 : 0.0
        brightness: root.styleMode === "dark" ? 0.42
            : (root.styleMode === "clear" ? 0.12 : 0.0)
        contrast: root.styleMode === "dark" ? 0.08 : 0.0
        colorization: root.styleMode === "tinted" ? 0.92
            : (root.styleMode === "dark" ? 0.55 : 0.0)
        colorizationColor: root.styleMode === "tinted" ? root.tintColor
            : Qt.rgba(0.92, 0.92, 0.94, 1)
      }
    }
  }
}
