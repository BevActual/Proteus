# proteus-accounts

User-scoped online-account seats for Proteus Settings.

- Catalog + status JSON for `Accounts.qml`
- Google OAuth2 PKCE (`connect google`) when
  `PROTEUS_GOOGLE_OAUTH_CLIENT_ID` or `~/.config/proteus/oauth-google-client-id` is set
- Seat metadata: `~/.config/proteus/accounts.json`
- Tokens: `~/.local/share/proteus/accounts/tokens/*.token.json` (0600) — **not** `settings.json`

```bash
cargo build --release
./target/release/proteus-accounts smoke
./scripts/accounts-smoke.sh
```
