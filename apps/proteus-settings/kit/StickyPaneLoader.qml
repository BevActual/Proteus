import QtQuick
import QtQuick.Layouts

// Creates source / sourceComponent only when want becomes true; keeps instance after first load.
// Width/kept run on status Ready so consumers can still use onLoaded without clobbering us.
Loader {
  id: loader
  Layout.fillWidth: true

  property bool want: false
  property bool sticky: true
  property bool kept: false
  // Prefer async for heavy panes; set false for the default hub so first paint is immediate.
  property bool asyncLoad: true

  active: want || (sticky && kept)
  visible: want
  asynchronous: asyncLoad

  onStatusChanged: {
    if (status !== Loader.Ready || !item)
      return
    if (sticky)
      kept = true
    item.width = Qt.binding(function () { return loader.width })
  }
}
