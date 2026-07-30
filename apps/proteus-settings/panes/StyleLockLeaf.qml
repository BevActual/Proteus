import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import "../shared"
import "../kit"

// Leaf UI for StylePane. LockPane lives in panes/ (not a QML module) — load by URL.
Loader {
  id: root
  property Item host
  width: parent ? parent.width : implicitWidth
  source: Qt.resolvedUrl("LockPane.qml")

  onStatusChanged: {
    if (status !== Loader.Ready || !item)
      return
    item.width = Qt.binding(function () {
      return root.width
    })
  }
}
