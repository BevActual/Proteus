import Quickshell
import QtQuick
import QtQuick.Layouts
import "../shared"
import "../kit"

// Per-provider Online accounts leaf — form / OAuth connect / seat + disconnect.
// Host is AccountsPane; provider is set by the StickyPaneLoader (google, …).
ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: Theme.spaceMd

  property Item host: null
  property string provider: ""

  readonly property var specs: ({
    google: {
      label: "Google",
      oauth: true,
      description: "Google PKCE powers calendar, mail, and contacts glances + thin write. Needs calendar + mail + contacts scopes — reconnect older seats. Tokens stay in the proteus-accounts vault (not settings.json).",
      setupHint: "Set PROTEUS_GOOGLE_OAUTH_CLIENT_ID or ~/.config/proteus/oauth-google-client-id, then Connect."
    },
    microsoft: {
      label: "Microsoft",
      oauth: true,
      description: "Microsoft personal PKCE (same Graph client as Exchange work/school). Powers calendar + mail + contacts glances and thin write. Reconnect if seat predates Contacts.ReadWrite. Tokens stay in the proteus-accounts vault (not settings.json).",
      setupHint: "Set PROTEUS_MICROSOFT_OAUTH_CLIENT_ID or ~/.config/proteus/oauth-microsoft-client-id (public client · loopback redirect)."
    },
    exchange: {
      label: "Exchange",
      oauth: true,
      description: "Work/school Microsoft 365 via the same PKCE client as Microsoft (not EWS). Powers calendar + mail + contacts glances and thin write. Reconnect if seat predates Contacts.ReadWrite. Tokens stay in the proteus-accounts vault (not settings.json).",
      setupHint: "Set PROTEUS_MICROSOFT_OAUTH_CLIENT_ID or ~/.config/proteus/oauth-microsoft-client-id (Exchange uses the same client)."
    },
    nextcloud: {
      label: "Nextcloud",
      oauth: false,
      description: "Create an app password under Nextcloud → Settings → Security, then connect. Powers calendar glances. Tokens stay in the proteus-accounts vault (not settings.json).",
      fields: [
        { key: "url", label: "Instance URL", placeholder: "https://cloud.example", password: false, bind: "nextcloudUrl" },
        { key: "user", label: "Username", placeholder: "Username", password: false, bind: "nextcloudUser" },
        { key: "pass", label: "App password", placeholder: "App password", password: true, bind: "nextcloudAppPassword" }
      ],
      connectLabel: "Connect Nextcloud"
    },
    imap: {
      label: "IMAP",
      oauth: false,
      description: "Generic IMAP inbox for the menu-bar mail glance (TLS on the port you set; default 993). Password stays in the proteus-accounts vault.",
      fields: [
        { key: "host", label: "Host", placeholder: "imap.example.com", password: false, bind: "imapHost" },
        { key: "port", label: "Port", placeholder: "993", password: false, bind: "imapPort", narrow: true },
        { key: "user", label: "Username", placeholder: "Username / email", password: false, bind: "imapUser" },
        { key: "pass", label: "Password", placeholder: "Password or app password", password: true, bind: "imapPassword" }
      ],
      connectLabel: "Connect IMAP"
    },
    caldav: {
      label: "CalDAV",
      oauth: false,
      description: "Generic CalDAV calendar home for the menu-bar calendar glance. Use the calendar-home URL from your provider (not a single .ics). Password stays in the proteus-accounts vault.",
      fields: [
        { key: "url", label: "Calendar home URL", placeholder: "https://cal.example/dav/calendars/user/", password: false, bind: "caldavUrl" },
        { key: "user", label: "Username", placeholder: "Username", password: false, bind: "caldavUser" },
        { key: "pass", label: "Password", placeholder: "Password or app password", password: true, bind: "caldavPassword" }
      ],
      connectLabel: "Connect CalDAV"
    },
    carddav: {
      label: "CardDAV",
      oauth: false,
      description: "Generic CardDAV address-book home for the menu-bar contacts glance. Use the addressbook-home URL from your provider. Password stays in the proteus-accounts vault.",
      fields: [
        { key: "url", label: "Address-book home URL", placeholder: "https://card.example/dav/addressbooks/user/", password: false, bind: "carddavUrl" },
        { key: "user", label: "Username", placeholder: "Username", password: false, bind: "carddavUser" },
        { key: "pass", label: "Password", placeholder: "Password or app password", password: true, bind: "carddavPassword" }
      ],
      connectLabel: "Connect CardDAV"
    },
    apple: {
      label: "Apple",
      oauth: false,
      description: "Create an app-specific password at appleid.apple.com (Sign-In and Security → App-Specific Passwords). Connects IMAP + CalDAV + CardDAV glances. Not Sign in with Apple OAuth. Tokens stay in the proteus-accounts vault (not settings.json).",
      fields: [
        { key: "user", label: "Apple ID", placeholder: "Apple ID email", password: false, bind: "appleId" },
        { key: "pass", label: "App-specific password", placeholder: "App-specific password", password: true, bind: "appleAppPassword" }
      ],
      connectLabel: "Connect Apple"
    }
  })

  readonly property var spec: root.specs[root.provider] || null
  readonly property bool isOauth: !!(spec && spec.oauth)

  readonly property var connector: {
    const id = root.provider
    if (!id.length || !Accounts.ready)
      return null
    const list = Accounts.connectors || []
    for (let i = 0; i < list.length; i++) {
      if (list[i].id === id)
        return list[i]
    }
    return null
  }

  readonly property var seats: (connector && connector.seats) ? connector.seats : []
  readonly property bool connected: !!(connector && connector.status === "connected") || seats.length > 0

  readonly property bool oauthReady: {
    if (provider === "google")
      return Accounts.googleClientConfigured
    if (provider === "exchange")
      return Accounts.exchangeConnectable
    if (provider === "microsoft")
      return Accounts.microsoftClientConfigured
    return false
  }

  function fieldValue(bind) {
    return String(Accounts[bind] || "")
  }

  function setFieldValue(bind, value) {
    Accounts[bind] = value
  }

  readonly property bool formValid: {
    if (!spec || isOauth || connected)
      return false
    const fields = spec.fields || []
    for (let i = 0; i < fields.length; i++) {
      const f = fields[i]
      // Port has a default; treat empty as ok (connectImap defaults to 993).
      if (f.bind === "imapPort")
        continue
      if (!String(Accounts[f.bind] || "").trim().length)
        return false
    }
    return true
  }

  function runConnect() {
    if (!spec)
      return
    if (provider === "google")
      Accounts.connectGoogle()
    else if (provider === "microsoft")
      Accounts.connectMicrosoft()
    else if (provider === "exchange")
      Accounts.connectExchange()
    else if (provider === "nextcloud")
      Accounts.connectNextcloud()
    else if (provider === "imap")
      Accounts.connectImap()
    else if (provider === "caldav")
      Accounts.connectCaldav()
    else if (provider === "carddav")
      Accounts.connectCarddav()
    else if (provider === "apple")
      Accounts.connectApple()
  }

  function disconnectSeat(seatId) {
    if (seatId)
      Accounts.disconnectSeat(seatId)
  }

  Text {
    Layout.fillWidth: true
    Layout.maximumWidth: 520
    visible: !!spec
    text: spec ? spec.description : ""
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

  // ── Connected seats ──────────────────────────────────────────────────
  SettingsGroup {
    title: spec ? spec.label : "Account"
    visible: root.connected

    Repeater {
      model: root.seats

      SettingsFormRow {
        required property var modelData
        required property int index
        label: String(modelData.label || modelData.email || "Connected")
        hint: modelData.email && modelData.label && modelData.label !== modelData.email
            ? String(modelData.email) : "Seat in proteus-accounts vault"
        showSeparator: root.isOauth || index < root.seats.length - 1

        Text {
          text: Accounts.busy ? "…" : "Disconnect"
          color: Theme.danger
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSizeSm
          font.weight: Font.Medium

          MouseArea {
            anchors.fill: parent
            enabled: !Accounts.busy
            cursorShape: Qt.PointingHandCursor
            onClicked: root.disconnectSeat(modelData.id)
          }
        }
      }
    }

    // OAuth seats age out of new scopes (calendar + mail) — re-run PKCE.
    // Same client-id readiness as Connect (#1597).
    SettingsFormRow {
      visible: root.isOauth
      label: Accounts.busy ? "Reconnecting…" : "Reconnect"
      hint: root.oauthReady
          ? "Re-run sign-in to refresh scopes"
          : (spec ? spec.setupHint : "OAuth client id required")
      showSeparator: false
      interactive: !Accounts.busy && root.oauthReady
      onActivated: root.runConnect()
      Text {
        text: {
          if (Accounts.busy)
            return "…"
          if (!root.oauthReady)
            return "Set up"
          return "Reconnect"
        }
        color: root.oauthReady ? Theme.accent : Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSm
        font.weight: Font.Medium
      }
    }
  }

  // ── OAuth not connected ──────────────────────────────────────────────
  SettingsGroup {
    title: spec ? spec.label : "Account"
    visible: !!spec && root.isOauth && !root.connected

    SettingsFormRow {
      visible: !root.oauthReady
      label: "Client ID"
      hint: spec ? spec.setupHint : ""
      showSeparator: true
      Text {
        text: "Needed"
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSm
      }
    }

    SettingsFormRow {
      label: Accounts.busy ? "Connecting…" : "Connect"
      hint: root.oauthReady
          ? "Opens the browser for PKCE sign-in"
          : (spec ? spec.setupHint : "")
      showSeparator: false
      interactive: !Accounts.busy && root.oauthReady
      onActivated: root.runConnect()
      Text {
        text: {
          if (Accounts.busy)
            return "…"
          if (!root.oauthReady)
            return "Set up"
          return "Connect"
        }
        color: root.oauthReady ? Theme.accent : Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSm
        font.weight: Font.Medium
      }
    }
  }

  // ── Manual form ──────────────────────────────────────────────────────
  SettingsGroup {
    title: spec ? spec.label : "Account"
    visible: !!spec && !root.isOauth && !root.connected

    Repeater {
      model: (spec && spec.fields) ? spec.fields : []

      ColumnLayout {
        required property var modelData
        required property int index
        Layout.fillWidth: true
        spacing: 0

        SettingsFormRow {
          label: modelData.label
          // Never mirror password binds into hint — secrets stay in the
          // Password TextInput only (review #1596).
          hint: modelData.password
              ? (modelData.placeholder || "")
              : (root.fieldValue(modelData.bind).length
                  ? root.fieldValue(modelData.bind)
                  : (modelData.placeholder || ""))
          showSeparator: true
        }

        Item {
          Layout.fillWidth: true
          Layout.preferredHeight: 44
          Layout.maximumWidth: modelData.narrow ? 160 : 100000

          Rectangle {
            anchors.fill: parent
            anchors.leftMargin: Theme.spaceMd
            anchors.rightMargin: Theme.spaceMd
            anchors.topMargin: Theme.spaceXs
            anchors.bottomMargin: Theme.spaceSm
            radius: Theme.radiusMd
            color: Theme.bgHover
            border.width: 1
            border.color: fieldInput.activeFocus ? Theme.accent : Theme.border

            TextInput {
              id: fieldInput
              anchors.fill: parent
              anchors.leftMargin: 10
              anchors.rightMargin: 10
              color: Theme.text
              font.family: Theme.fontFamily
              font.pixelSize: 13
              echoMode: modelData.password ? TextInput.Password : TextInput.Normal
              text: root.fieldValue(modelData.bind)
              onTextChanged: root.setFieldValue(modelData.bind, text)
              Keys.onReturnPressed: {
                if (root.formValid && !Accounts.busy)
                  root.runConnect()
              }
              Keys.onEnterPressed: {
                if (root.formValid && !Accounts.busy)
                  root.runConnect()
              }
            }
          }
        }
      }
    }

    SettingsFormRow {
      label: Accounts.busy ? "Connecting…" : (spec ? (spec.connectLabel || "Connect") : "Connect")
      hint: root.formValid ? "Save seat to proteus-accounts vault" : "Fill required fields"
      showSeparator: false
      interactive: !Accounts.busy && root.formValid
      onActivated: root.runConnect()
      Text {
        text: Accounts.busy ? "…" : "Connect"
        color: root.formValid ? Theme.accent : Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSm
        font.weight: Font.Medium
      }
    }
  }

  Text {
    Layout.fillWidth: true
    Layout.maximumWidth: 520
    text: "Fact: vault tokens never enter settings.json · proteus-accounts CLI"
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 11
    wrapMode: Text.WordWrap
  }
}
