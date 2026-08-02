# proteus-accounts

User-scoped online-account seats for Proteus Settings.

- Catalog + status JSON for `Accounts.qml`
- Google OAuth2 PKCE (`connect google`) when
  `PROTEUS_GOOGLE_OAUTH_CLIENT_ID` or `~/.config/proteus/oauth-google-client-id` is set
- Microsoft OAuth2 PKCE (`connect microsoft`) when
  `PROTEUS_MICROSOFT_OAUTH_CLIENT_ID` or `~/.config/proteus/oauth-microsoft-client-id` is set
  (public client; loopback `http://127.0.0.1:<port>/callback`)
- Nextcloud app password (`connect nextcloud <base-url> <user> <app-password>`);
  verifies `status.php` + OCS user unless `PROTEUS_ACCOUNTS_SKIP_VERIFY=1`
- Seat metadata: `~/.config/proteus/accounts.json`
- Tokens: `~/.local/share/proteus/accounts/tokens/*.token.json` (0600) — **not** `settings.json`

```bash
cargo build --release
./target/release/proteus-accounts smoke
./scripts/smoke/accounts-smoke.sh
```
