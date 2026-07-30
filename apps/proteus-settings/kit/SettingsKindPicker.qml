import Quickshell
import QtQuick
import QtQuick.Layouts
import "../shared"

// Shared Appearance Kind list + optional browse-vs-applied banner.
ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: Theme.spaceSm

  property string title: "Kind"
  property var model: []
  property string browseKind: ""
  property string appliedKind: ""
  // When set, banner is hidden while browsing this kind (Lock "match").
  property string hideBannerForKind: ""
  property string bannerText: ""
  // function(id) -> hint string
  property var hintForId: function (id) {
    return ""
  }

  signal activated(string id)

  readonly property bool showBanner: {
    if (!root.bannerText.length)
      return false
    if (root.browseKind === root.appliedKind)
      return false
    if (root.hideBannerForKind.length && root.browseKind === root.hideBannerForKind)
      return false
    return true
  }

  SettingsGroup {
    title: root.title
    Repeater {
      model: root.model
      SettingsFormRow {
        required property var modelData
        required property int index
        label: modelData.label
        hint: root.hintForId(modelData.id)
        interactive: true
        showSeparator: index < root.model.length - 1
        onActivated: root.activated(modelData.id)
        Text {
          visible: root.browseKind === modelData.id
          text: "✓"
          color: Theme.accent
          font.pixelSize: 14
        }
      }
    }
  }

  Text {
    visible: root.showBanner
    Layout.fillWidth: true
    Layout.maximumWidth: 480
    text: root.bannerText
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 11
    wrapMode: Text.WordWrap
  }
}
