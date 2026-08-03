# proteus-accounts

User-scoped online-account seats for Proteus Settings.

- Catalog + status JSON for `Accounts.qml`
- Google OAuth2 PKCE (`connect google`) when
  `PROTEUS_GOOGLE_OAUTH_CLIENT_ID` or `~/.config/proteus/oauth-google-client-id` is set
- Microsoft OAuth2 PKCE (`connect microsoft`) when
  `PROTEUS_MICROSOFT_OAUTH_CLIENT_ID` or `~/.config/proteus/oauth-microsoft-client-id` is set
  (public client; loopback `http://127.0.0.1:<port>/callback`)
- Exchange / work·school (`connect exchange`) — same Microsoft PKCE client + Graph
  scopes; separate `exchange` seat (not EWS/NTLM)
- Nextcloud app password (`connect nextcloud <base-url> <user> <app-password>`);
  verifies `status.php` + OCS user unless `PROTEUS_ACCOUNTS_SKIP_VERIFY=1`
- IMAP (`connect imap <host> <port> <user> <password>`); TLS via python3
  `imaplib` unless `PROTEUS_ACCOUNTS_SKIP_VERIFY=1`
- CalDAV (`connect caldav <calendar-home-url> <user> <password>`); PROPFIND
  Depth 0 unless `PROTEUS_ACCOUNTS_SKIP_VERIFY=1`
- CardDAV (`connect carddav <addressbook-home-url> <user> <password>`); PROPFIND
  Depth 0 unless `PROTEUS_ACCOUNTS_SKIP_VERIFY=1`
- Apple / iCloud (`connect apple <apple-id> <app-specific-password>`); verifies
  IMAP + CalDAV + CardDAV defaults unless `PROTEUS_ACCOUNTS_SKIP_VERIFY=1`
  (not Sign in with Apple OAuth)
- Seat metadata: `~/.config/proteus/accounts.json`
- Tokens: `~/.local/share/proteus/accounts/tokens/*.token.json` (0600) — **not** `settings.json`
- `token <seat|provider>` — access token JSON with refresh (Google/MS calendar + mail scopes);
  Nextcloud/IMAP/CalDAV/CardDAV return vault password as `accessToken` + `baseUrl`/`username`;
  Apple also emits `caldavUrl` / `carddavUrl` / `imapHost` / `imapPort`
- Consumers: calendar / mail / contacts glances (`proteus-*-glance.py` / calendar-events)

```bash
cargo build --release
./target/release/proteus-accounts smoke
./target/release/proteus-accounts token nextcloud   # after connect
./dev/smoke/accounts-smoke.sh
```
