import QtQuick

// Glass context-menu plate — same chrome family as dock / menu bar (CHROME).
// Kit seed for dock (and later surfaces); keep actions as children.
Rectangle {
  id: root
  antialiasing: true
  radius: Math.max(Theme.radiusMd, Math.min(width, height) * Theme.squircleCornerRatio)
  color: Theme.menuPlateFill
  border.width: Theme.chromeClear ? 0 : 1
  border.color: Theme.chromeHairline

  Behavior on color {
    ColorAnimation {
      duration: 180
      easing.type: Easing.OutCubic
    }
  }
  Behavior on border.color {
    ColorAnimation {
      duration: 180
      easing.type: Easing.OutCubic
    }
  }
}
