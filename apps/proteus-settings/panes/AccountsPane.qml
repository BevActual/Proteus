import Quickshell
import QtQuick
import QtQuick.Layouts
import "../shared"
import "../kit"

// Online accounts hub → per-provider leaves.
// Page ids: accounts · accounts-google · accounts-microsoft · accounts-exchange ·
// accounts-nextcloud · accounts-imap · accounts-caldav · accounts-carddav ·
// accounts-apple.
// The hub owns the canonical provider list (specs below) and only takes
// status/seats from the proteus-accounts catalog — a stale catalog can't
// inject "Coming later" rows or scope-dump hints.
// Tokens via proteus-accounts vault — never settings.json.
// Calendar + mail + contacts glances In; Mail/Contacts product apps Out.
ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: Theme.spaceMd

  property string page: "accounts"
  signal requestGo(string id)

  readonly property bool active: page === "accounts" || page.startsWith("accounts-")

  // Canonical catalog — labels + one-line blurbs the hub renders. Status and
  // seats merge in from Accounts.connectors by id.
  readonly property var providerSpecs: [
    { id: "google", label: "Google", blurb: "Calendar, mail & contacts glances", oauth: true },
    { id: "microsoft", label: "Microsoft", blurb: "Personal account · calendar + mail glances", oauth: true },
    { id: "exchange", label: "Exchange", blurb: "Microsoft 365 work / school · calendar + mail", oauth: true },
    { id: "nextcloud", label: "Nextcloud", blurb: "Self-hosted · app password", oauth: false },
    { id: "imap", label: "IMAP", blurb: "Any mail provider · mail glance", oauth: false },
    { id: "caldav", label: "CalDAV", blurb: "Any calendar provider · calendar glance", oauth: false },
    { id: "carddav", label: "CardDAV", blurb: "Any contacts provider · contacts glance", oauth: false },
    { id: "apple", label: "Apple", blurb: "iCloud mail, calendar & contacts", oauth: false }
  ]

  function connectorFor(id) {
    const list = Accounts.connectors || []
    for (let i = 0; i < list.length; i++) {
      if (list[i].id === id)
        return list[i]
    }
    return null
  }

  function seatsFor(id) {
    const c = root.connectorFor(id)
    return (c && c.seats) ? c.seats : []
  }

  function isConnected(id) {
    const c = root.connectorFor(id)
    if (c && c.status === "connected")
      return true
    return root.seatsFor(id).length > 0
  }

  function seatSummary(id) {
    const seats = root.seatsFor(id)
    if (!seats.length)
      return "Connected"
    const first = String(seats[0].label || seats[0].email || "Connected")
    if (seats.length > 1)
      return first + " · +" + (seats.length - 1) + " more"
    return first
  }

  readonly property var connectedProviders: {
    const out = []
    for (let i = 0; i < root.providerSpecs.length; i++) {
      if (root.isConnected(root.providerSpecs[i].id))
        out.push(root.providerSpecs[i])
    }
    return out
  }

  readonly property var availableProviders: {
    const out = []
    for (let i = 0; i < root.providerSpecs.length; i++) {
      if (!root.isConnected(root.providerSpecs[i].id))
        out.push(root.providerSpecs[i])
    }
    return out
  }

  function oauthConfigured(id) {
    if (id === "google")
      return Accounts.googleClientConfigured
    if (id === "exchange")
      return Accounts.exchangeConnectable
    if (id === "microsoft")
      return Accounts.microsoftClientConfigured
    return false
  }

  function oauthSetupHint(id) {
    if (id === "google")
      return "Needs setup — ~/.config/proteus/oauth-google-client-id"
    if (id === "exchange")
      return "Needs setup — same oauth-microsoft-client-id (work/school)"
    if (id === "microsoft")
      return "Needs setup — ~/.config/proteus/oauth-microsoft-client-id"
    return ""
  }

  function availableHint(spec) {
    if (!Accounts.ready)
      return "Loading…"
    if (spec.oauth && !root.oauthConfigured(spec.id))
      return root.oauthSetupHint(spec.id)
    return spec.blurb
  }

  function connectOauth(id) {
    if (id === "google") {
      if (!Accounts.googleClientConfigured) {
        Accounts.error = "Set PROTEUS_GOOGLE_OAUTH_CLIENT_ID or ~/.config/proteus/oauth-google-client-id"
        return
      }
      Accounts.connectGoogle()
      return
    }
    if (id === "exchange") {
      if (!Accounts.exchangeConnectable) {
        Accounts.error = "Set PROTEUS_MICROSOFT_OAUTH_CLIENT_ID or ~/.config/proteus/oauth-microsoft-client-id (Exchange uses the same client)"
        return
      }
      Accounts.connectExchange()
      return
    }
    if (id === "microsoft") {
      if (!Accounts.microsoftClientConfigured) {
        Accounts.error = "Set PROTEUS_MICROSOFT_OAUTH_CLIENT_ID or ~/.config/proteus/oauth-microsoft-client-id"
        return
      }
      Accounts.connectMicrosoft()
    }
  }

  onActiveChanged: {
    if (active)
      Accounts.refresh()
  }

  Component.onCompleted: {
    if (active)
      Accounts.refresh()
  }

  // ── Hub ──────────────────────────────────────────────────────────────
  ColumnLayout {
    visible: root.page === "accounts"
    Layout.fillWidth: true
    spacing: Theme.spaceMd

    Text {
      Layout.fillWidth: true
      Layout.maximumWidth: 480
      text: "Accounts power the menu-bar calendar, mail, and contacts glances. Tokens stay in the proteus-accounts vault."
      color: Theme.textDim
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSizeSm
      wrapMode: Text.WordWrap
    }

    Text {
      visible: Accounts.error.length > 0
      Layout.fillWidth: true
      Layout.maximumWidth: 480
      text: Accounts.error
      color: Theme.danger
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSizeSm
      wrapMode: Text.WordWrap
    }

    SettingsGroup {
      title: "Connected"
      visible: root.connectedProviders.length > 0

      Repeater {
        model: root.connectedProviders

        SettingsFormRow {
          required property var modelData
          required property int index
          label: modelData.label
          hint: root.seatSummary(modelData.id)
          showSeparator: index < root.connectedProviders.length - 1
          interactive: true
          onActivated: root.requestGo("accounts-" + modelData.id)

          RowLayout {
            spacing: Theme.spaceSm

            Text {
              text: "Connected"
              color: Theme.accent
              font.family: Theme.fontFamily
              font.pixelSize: Theme.fontSizeSm
            }

            Text {
              text: "›"
              color: Theme.textMute
              font.family: Theme.fontFamily
              font.pixelSize: Theme.fontSize
            }
          }
        }
      }
    }

    SettingsGroup {
      title: root.connectedProviders.length > 0 ? "Add account" : "Providers"
      visible: root.availableProviders.length > 0

      Repeater {
        model: root.availableProviders

        SettingsFormRow {
          required property var modelData
          required property int index
          label: modelData.label
          hint: root.availableHint(modelData)
          showSeparator: index < root.availableProviders.length - 1
          // Row click always drills into the leaf (details / setup); the
          // inline Connect on ready OAuth rows consumes its own click.
          interactive: true
          onActivated: root.requestGo("accounts-" + modelData.id)

          RowLayout {
            spacing: Theme.spaceSm

            // OAuth ready → one-click Connect without leaving the hub
            Text {
              visible: modelData.oauth && root.oauthConfigured(modelData.id)
              text: Accounts.busy ? "…" : "Connect"
              color: Theme.accent
              font.family: Theme.fontFamily
              font.pixelSize: Theme.fontSizeSm
              font.weight: Font.Medium
              opacity: Accounts.busy ? 0.6 : 1

              MouseArea {
                anchors.fill: parent
                enabled: !Accounts.busy
                cursorShape: Qt.PointingHandCursor
                onClicked: root.connectOauth(modelData.id)
              }
            }

            Text {
              text: "›"
              color: Theme.textMute
              font.family: Theme.fontFamily
              font.pixelSize: Theme.fontSize
            }
          }
        }
      }
    }

    Text {
      Layout.fillWidth: true
      Layout.maximumWidth: 480
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
        if (Accounts.exchangeConnectable)
          bits.push("Exchange PKCE ready (same Microsoft client · work/school)")
        else
          bits.push("Exchange: same oauth-microsoft-client-id as Microsoft")
        bits.push("Nextcloud/IMAP/CalDAV/CardDAV/Apple: manual setup in each leaf")
        bits.push("Vault tokens never enter settings.json")
        return "Fact: " + bits.join(" · ")
      }
      color: Theme.textMute
      font.family: Theme.fontFamily
      font.pixelSize: 11
      wrapMode: Text.WordWrap
    }
  }

  // ── Leaves (one generic file, provider id per loader) ─────────────────
  StickyPaneLoader {
    want: root.page === "accounts-google"
    source: "AccountsProviderLeaf.qml"
    onLoaded: {
      item.host = root
      item.provider = "google"
    }
  }

  StickyPaneLoader {
    want: root.page === "accounts-microsoft"
    source: "AccountsProviderLeaf.qml"
    onLoaded: {
      item.host = root
      item.provider = "microsoft"
    }
  }

  StickyPaneLoader {
    want: root.page === "accounts-exchange"
    source: "AccountsProviderLeaf.qml"
    onLoaded: {
      item.host = root
      item.provider = "exchange"
    }
  }

  StickyPaneLoader {
    want: root.page === "accounts-nextcloud"
    source: "AccountsProviderLeaf.qml"
    onLoaded: {
      item.host = root
      item.provider = "nextcloud"
    }
  }

  StickyPaneLoader {
    want: root.page === "accounts-imap"
    source: "AccountsProviderLeaf.qml"
    onLoaded: {
      item.host = root
      item.provider = "imap"
    }
  }

  StickyPaneLoader {
    want: root.page === "accounts-caldav"
    source: "AccountsProviderLeaf.qml"
    onLoaded: {
      item.host = root
      item.provider = "caldav"
    }
  }

  StickyPaneLoader {
    want: root.page === "accounts-carddav"
    source: "AccountsProviderLeaf.qml"
    onLoaded: {
      item.host = root
      item.provider = "carddav"
    }
  }

  StickyPaneLoader {
    want: root.page === "accounts-apple"
    source: "AccountsProviderLeaf.qml"
    onLoaded: {
      item.host = root
      item.provider = "apple"
    }
  }
}
