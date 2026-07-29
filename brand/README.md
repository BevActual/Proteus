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
| [`proteus-launcher.svg`](./proteus-launcher.svg) | Spotlight / dock launcher (search + sparkle) |

Colors track chrome defaults: Electric `#3d8bfd` + Teal `#2dd4bf`
([CHROME.md](../docs/proteus/CHROME.md) / `Theme.qml`).

## Wiring

| Surface | How |
|---------|-----|
| Icon theme | `vm/guest/install-icons.sh` → `hicolor` names `proteus`, `proteus-settings`, `proteus-launcher` |
| Settings `.desktop` | `Icon=proteus-settings` |
| Session `.desktop` | `Icon=proteus` |
| Dock launcher / Settings | Brand SVG via `DockApps.iconSource` (works before icon-cache install) |
| About pane | Brand SVG |
| Spotlight / launcher apps | `EnvGate.resolveAppIcon` (`.desktop` Icon=, id fallbacks) |

Install on guest: `sudo bash /mnt/proteus/vm/guest/install-icons.sh`  
(also runs from `install-settings-app.sh` / greeter apply).

Keep the SVG as source of truth; PNG is a fallback for toolkits that skip SVG.
