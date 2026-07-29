import QtQuick
import QtQuick.Layouts

// Creates source / sourceComponent only when want becomes true; keeps instance after first load.
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

  onLoaded: {
    if (sticky)
      kept = true
    if (item)
      item.width = Qt.binding(function () { return loader.width })
  }
}
