import Quickshell
import QtQuick
import QtQuick.Layouts
import "../shared"
import "../kit"

// Leaf — one permission category (global toggle + per-app grants).
ColumnLayout {
  id: root
  width: parent ? parent.width : implicitWidth
  spacing: Theme.spaceMd

  property string categoryId: "microphone"

  readonly property string categoryLabel: Permissions.categoryLabel(categoryId)

  readonly property string categoryHint: {
    const meta = Permissions.categoryMeta || []
    for (let i = 0; i < meta.length; i++) {
      if (meta[i].id === categoryId)
        return String(meta[i].hint || "")
    }
    return ""
  }

  readonly property var appRows: {
    const _r = Permissions.rev
    return Permissions.appsForCategory(categoryId)
  }

  readonly property var grantOpts: [
    {
      id: "allow",
      label: "Allow"
    },
    {
      id: "ask",
      label: "Ask"
    },
    {
      id: "deny",
      label: "Deny"
    }
  ]

  Component.onCompleted: Permissions.refreshActivity()

  SettingsGroup {
    title: root.categoryLabel

    Text {
      Layout.fillWidth: true
      Layout.maximumWidth: 520
      text: {
        let t = root.categoryHint
        if (categoryId === "microphone" || categoryId === "camera")
          t += (t.length ? " · " : "")
              + "Deny syncs portal PermissionStore + best-effort capture enforce (pactl mute / PW video destroy). "
              + "Not a full OS sandbox. Flatpak also uses overrides."
        if (categoryId === "screen")
          t += (t.length ? " · " : "")
              + "Per-app Deny syncs portal screencast table when available; session restore tokens stay portal-side."
        if (categoryId === "location")
          t += " Deny mutes weather fetch; Allow does not auto-unmute."
        if (categoryId === "notifications")
          t += " Deny turns on Do Not Disturb; Allow does not clear DND."
        return t
      }
      color: Theme.textDim
      font.family: Theme.fontFamily
      font.pixelSize: 12
      wrapMode: Text.WordWrap
      Layout.bottomMargin: Theme.spaceXs
    }

    SettingsFormRow {
      label: "For all apps"
      hint: Permissions.categoryState(root.categoryId) === "deny"
          ? "Denied by default"
          : "Allowed by default (per-app can tighten)"
      showSeparator: root.appRows.length > 0
      SettingsSegmented {
        Layout.preferredWidth: 160
        options: [
          {
            id: "allow",
            label: "Allow"
          },
          {
            id: "deny",
            label: "Deny"
          }
        ]
        selected: Permissions.categoryState(root.categoryId)
        onActivated: id => Permissions.setCategory(root.categoryId, id)
      }
    }
  }

  SettingsGroup {
    title: "Apps"
    visible: root.appRows.length > 0

    Repeater {
      model: root.appRows

      SettingsFormRow {
        required property var modelData
        required property int index
        label: modelData.label
        hint: {
          const bits = []
          if (modelData.active)
            bits.push("In use")
          bits.push(String(modelData.grant || "allow"))
          if (String(modelData.id || "").indexOf("bin:") === 0)
            bits.push("no desktop id")
          return bits.join(" · ")
        }
        showSeparator: index < root.appRows.length - 1

        SettingsCombo {
          preferredWidth: 120
          enabled: String(modelData.id || "").indexOf("bin:") !== 0
          model: root.grantOpts
          currentValue: String(modelData.grant || "allow")
          onActivated: id => {
            const app = String(modelData.id || "")
            if (!app.length || app.indexOf("bin:") === 0)
              return
            Permissions.setAppGrant(app, root.categoryId, id)
          }
        }
      }
    }
  }

  Text {
    Layout.fillWidth: true
    Layout.maximumWidth: 520
    visible: root.appRows.length === 0
    text: "No apps recorded for this category yet. Grants appear when an app is in use or you set one from Flatpak."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 12
    wrapMode: Text.WordWrap
  }

  Text {
    Layout.fillWidth: true
    visible: Permissions.error.length > 0
    text: Permissions.error
    color: Theme.accent
    font.family: Theme.fontFamily
    font.pixelSize: 12
    wrapMode: Text.WordWrap
  }
}
