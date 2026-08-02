import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../shared"
import "../kit"

// Online accounts: Google / Microsoft PKCE + Nextcloud app-password.
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
            visible: (modelData.id === "google" || modelData.id === "microsoft")
                && modelData.status === "not_connected"
            Layout.preferredHeight: 28
            Layout.preferredWidth: connectLabel.implicitWidth + 20
            radius: Theme.radiusPill - 8
            color: Accounts.busy ? Theme.bgHover : Theme.accent
            opacity: {
              if (modelData.id === "google")
                return Accounts.googleClientConfigured ? 1 : 0.55
              return Accounts.microsoftClientConfigured ? 1 : 0.55
            }
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
                if (modelData.id === "google") {
                  if (!Accounts.googleClientConfigured) {
                    Accounts.error = "Set PROTEUS_GOOGLE_OAUTH_CLIENT_ID or ~/.config/proteus/oauth-google-client-id"
                    return
                  }
                  Accounts.connectGoogle()
                } else {
                  if (!Accounts.microsoftClientConfigured) {
                    Accounts.error = "Set PROTEUS_MICROSOFT_OAUTH_CLIENT_ID or ~/.config/proteus/oauth-microsoft-client-id"
                    return
                  }
                  Accounts.connectMicrosoft()
                }
              }
            }
          }

          Rectangle {
            visible: (modelData.id === "google" || modelData.id === "microsoft"
                      || modelData.id === "nextcloud")
                && modelData.status === "connected"
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

  SettingsGroup {
    title: "Nextcloud"
    visible: {
      if (!Accounts.ready)
        return true
      for (let i = 0; i < Accounts.connectors.length; i++) {
        const c = Accounts.connectors[i]
        if (c.id === "nextcloud" && c.status === "connected")
          return false
      }
      return true
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Theme.spaceSm

      Text {
        Layout.fillWidth: true
        Layout.maximumWidth: 520
        text: "Create an app password under Nextcloud → Settings → Security, then connect. Tokens stay in the proteus-accounts vault (not settings.json)."
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: 11
        wrapMode: Text.WordWrap
      }

      TextField {
        Layout.fillWidth: true
        Layout.maximumWidth: 520
        placeholderText: "https://cloud.example"
        text: Accounts.nextcloudUrl
        onTextChanged: Accounts.nextcloudUrl = text
        color: Theme.text
        font.family: Theme.fontFamily
        background: Rectangle {
          radius: Theme.radiusSm
          color: Theme.bgHover
          border.width: 1
          border.color: Theme.chromeBorder
        }
      }

      TextField {
        Layout.fillWidth: true
        Layout.maximumWidth: 520
        placeholderText: "Username"
        text: Accounts.nextcloudUser
        onTextChanged: Accounts.nextcloudUser = text
        color: Theme.text
        font.family: Theme.fontFamily
        background: Rectangle {
          radius: Theme.radiusSm
          color: Theme.bgHover
          border.width: 1
          border.color: Theme.chromeBorder
        }
      }

      TextField {
        Layout.fillWidth: true
        Layout.maximumWidth: 520
        placeholderText: "App password"
        echoMode: TextInput.Password
        text: Accounts.nextcloudAppPassword
        onTextChanged: Accounts.nextcloudAppPassword = text
        color: Theme.text
        font.family: Theme.fontFamily
        background: Rectangle {
          radius: Theme.radiusSm
          color: Theme.bgHover
          border.width: 1
          border.color: Theme.chromeBorder
        }
      }

      Rectangle {
        Layout.preferredHeight: 32
        Layout.preferredWidth: ncConnectLabel.implicitWidth + 24
        radius: Theme.radiusPill - 8
        color: Accounts.busy ? Theme.bgHover : Theme.accent
        Text {
          id: ncConnectLabel
          anchors.centerIn: parent
          text: Accounts.busy ? "…" : "Connect Nextcloud"
          color: "#ffffff"
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSizeSm
          font.weight: Font.Medium
        }
        MouseArea {
          anchors.fill: parent
          enabled: !Accounts.busy
          cursorShape: Qt.PointingHandCursor
          onClicked: Accounts.connectNextcloud()
        }
      }
    }
  }

  Text {
    Layout.fillWidth: true
    Layout.maximumWidth: 520
    text: {
      const bits = []
      if (Accounts.googleClientConfigured)
        bits.push("Google PKCE ready")
      else
        bits.push("Google: set ~/.config/proteus/oauth-google-client-id")
      if (Accounts.microsoftClientConfigured)
        bits.push("Microsoft PKCE ready")
      else
        bits.push("Microsoft: set ~/.config/proteus/oauth-microsoft-client-id (public client · loopback redirect)")
      bits.push("Nextcloud: app password + instance URL")
      bits.push("Vault tokens never enter settings.json")
      return "Fact: " + bits.join(" · ")
    }
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 11
    wrapMode: Text.WordWrap
  }
}
