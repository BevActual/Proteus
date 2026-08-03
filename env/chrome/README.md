# env/chrome/ — sibling chrome token export

Machine-readable **frame** tokens for sibling apps (Rowena chrome, etc.).
Spec: [CHROME.md](../../docs/proteus/CHROME.md) §10 · live binding
[`Theme.qml`](../../shell/shared/Theme.qml).

| File | Role |
|------|------|
| `chrome-tokens.json` | Light/dark surfaces + space/radius + danger |
| `chrome-tokens.css` | CSS custom properties (`--proteus-*`) |

**Not** a Theme substitute inside Quickshell. **Not** canvas/product theming.
`accent` is Config-driven at runtime; JSON lists a default for export only.

Smoke: `./dev/smoke/chrome-tokens-smoke.sh`.
