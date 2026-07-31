import Quickshell
import QtQuick
import QtQuick.Layouts
import "../shared"
import "../kit"

// Online accounts: locked connector catalog + Google Connect when configured.
// Tokens via proteus-accounts vault — never settings.json. Mail/Contacts apps Out.
ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: Theme.spaceMd

  property bool active: false

  onActiveChanged: {
    if (active)
      Accounts.refresh()
  }

  Text {
    Layout.fillWidth: true
    Layout.maximumWidth: 520
    text: "Provider seats for future adaptive apps. Proteus does not invent mail, contacts, or cloud apps here — Connect only stores identity seats."
    color: Theme.textDim
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSizeSm
    wrapMode: Text.WordWrap
  }

  Text {
    visible: Accounts.error.length > 0
    Layout.fillWidth: true
    Layout.maximumWidth: 520
    text: Accounts.error
    color: Theme.danger
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSizeSm
    wrapMode: Text.WordWrap
  }

  SettingsGroup {
    title: "Providers"

    Repeater {
      model: Accounts.ready ? Accounts.connectors : [
        { id: "google", label: "Google", hint: "Loading…", status: "coming_later", seats: [] },
        { id: "microsoft", label: "Microsoft", hint: "Loading…", status: "coming_later", seats: [] },
        { id: "nextcloud", label: "Nextcloud", hint: "Loading…", status: "coming_later", seats: [] }
      ]

      SettingsFormRow {
        required property var modelData
        required property int index
        label: modelData.label
        hint: {
          if (modelData.status === "connected" && modelData.seats && modelData.seats.length)
            return String(modelData.seats[0].label || modelData.seats[0].email || "Connected")
          return modelData.hint || ""
        }
        showSeparator: index < (Accounts.connectors.length || 3) - 1

        RowLayout {
          spacing: Theme.spaceSm

          Text {
            text: {
              if (modelData.status === "connected")
                return "Connected"
              if (modelData.status === "not_connected")
                return "Not connected"
              return "Coming later"
            }
            color: modelData.status === "connected" ? Theme.accent : Theme.textMute
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
          }

          Rectangle {
            visible: modelData.id === "google" && modelData.status === "not_connected"
            Layout.preferredHeight: 28
            Layout.preferredWidth: connectLabel.implicitWidth + 20
            radius: Theme.radiusPill - 8
            color: Accounts.busy ? Theme.bgHover : Theme.accent
            opacity: Accounts.googleClientConfigured ? 1 : 0.55
            Text {
              id: connectLabel
              anchors.centerIn: parent
              text: Accounts.busy ? "…" : "Connect"
              color: "#ffffff"
              font.family: Theme.fontFamily
              font.pixelSize: Theme.fontSizeSm
              font.weight: Font.Medium
            }
            MouseArea {
              anchors.fill: parent
              enabled: !Accounts.busy
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (!Accounts.googleClientConfigured) {
                  Accounts.error = "Set PROTEUS_GOOGLE_OAUTH_CLIENT_ID or ~/.config/proteus/oauth-google-client-id"
                  return
                }
                Accounts.connectGoogle()
              }
            }
          }

          Rectangle {
            visible: modelData.id === "google" && modelData.status === "connected"
            Layout.preferredHeight: 28
            Layout.preferredWidth: discLabel.implicitWidth + 20
            radius: Theme.radiusPill - 8
            color: Theme.bgHover
            Text {
              id: discLabel
              anchors.centerIn: parent
              text: "Disconnect"
              color: Theme.text
              font.family: Theme.fontFamily
              font.pixelSize: Theme.fontSizeSm
              font.weight: Font.Medium
            }
            MouseArea {
              anchors.fill: parent
              enabled: !Accounts.busy
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                const seats = modelData.seats || []
                if (seats.length)
                  Accounts.disconnectSeat(seats[0].id)
              }
            }
          }
        }
      }
    }
  }

  Text {
    Layout.fillWidth: true
    Layout.maximumWidth: 520
    text: Accounts.googleClientConfigured
      ? "Fact: Google Connect uses system-browser PKCE; tokens stay in the proteus-accounts vault (not settings.json)."
      : "Fact: Create a Google Cloud OAuth client (Desktop app), then put the client id in ~/.config/proteus/oauth-google-client-id (one line). Redirect uses http://127.0.0.1:<port>/callback (loopback)."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 11
    wrapMode: Text.WordWrap
  }
}
