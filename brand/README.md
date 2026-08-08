# Proteus brand

## Mark

**DNA double helix** — adaptive host OS: one genome, many postures / device
environments. Not a second Tux; Proteus identity.

| File | Use |
|------|-----|
| [`proteus-mark.svg`](./proteus-mark.svg) | App icon / About / greeter (dark plate) |
| [`proteus-mark-clear.svg`](./proteus-mark-clear.svg) | Transparent; light or dark chrome |
| [`proteus-mark.png`](./proteus-mark.png) | Raster preview / hicolor PNG fallbacks |
| [`proteus-settings.svg`](./proteus-settings.svg) | Settings (gear) |
| [`proteus-launcher.svg`](./proteus-launcher.svg) | Beacon (system search) dock icon (search + sparkle) |

Colors track chrome defaults: Electric `#3d8bfd` + Teal `#2dd4bf`
([CHROME.md](../docs/proteus/CHROME.md) / `proteus-ui` tokens).

## Wiring

| Surface | How |
|---------|-----|
| Icon theme | `install/machine/install-icons.sh` → `hicolor` names `proteus`, `proteus-settings`, `proteus-launcher` |
| Settings `.desktop` | `Icon=proteus-settings` |
| Session `.desktop` | `Icon=proteus` |
| Dock launcher / Settings | Brand SVG via shell icon resolve (works before icon-cache install) |
| About pane | Brand SVG |
| Beacon / launcher apps | `shell/src/icons.rs` `resolve_app_icon` (`.desktop` Icon=, id fallbacks) |

Install on guest: `sudo bash /mnt/proteus/install/machine/install-icons.sh`  
(also runs from `install-settings-app.sh` / greeter apply).

Keep the SVG as source of truth; PNG is a fallback for toolkits that skip SVG.

## Licensing

The marks in this directory are **not** covered by the project's GPL-3.0-only
[LICENSE](../LICENSE). They are excluded from the grant.

Forks are free — that is what the GPL is for — but a fork must replace these
files and must not present itself as Proteus. See the trademark section at the
top of [LICENSE](../LICENSE).
