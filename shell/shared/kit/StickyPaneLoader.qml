import QtQuick
import QtQuick.Layouts

// Creates source / sourceComponent only when want becomes true; keeps instance after first load.
// Width/height sync via Binding so fillHeight can turn on after the first Ready (e.g. Mixer).
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
    if (status === Loader.Ready && sticky && item)
      kept = true
  }

  Binding {
    target: loader.item
    property: "width"
    value: loader.width
    when: loader.status === Loader.Ready && loader.item
  }

  Binding {
    target: loader.item
    property: "height"
    value: loader.height
    when: loader.status === Loader.Ready && loader.item && loader.Layout.fillHeight
  }
}
