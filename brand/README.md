# Proteus brand

## Mark

**DNA double helix** — adaptive host OS: one genome, many postures / device
environments. Not a second Tux; Proteus identity.

| File | Use |
|------|-----|
| [`proteus-mark.svg`](./proteus-mark.svg) | App icon / About / greeter (dark plate) |
| [`proteus-mark-clear.svg`](./proteus-mark-clear.svg) | Transparent; light or dark chrome |
| [`proteus-mark.png`](./proteus-mark.png) | Raster preview / surfaces that need PNG |

Colors track chrome defaults: Electric `#3d8bfd` + Teal `#2dd4bf`
([CHROME.md](../docs/proteus/CHROME.md) / `Theme.qml`).

## Later wiring

- Settings → About
- greetd / tuigreet greeting art
- `.desktop` icons / plymouth (when productizing ISO)
- Dock “Proteus” launcher glyph

Keep the SVG as source of truth; rasterize only when a surface requires PNG.
