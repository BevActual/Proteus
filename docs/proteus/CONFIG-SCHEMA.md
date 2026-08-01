---
doc: config-schema
role: reference
audience: coding agents, contributors
last_updated: "2026-07-29"
doc_status: active
scope: settings.json key groups (documentation of existing FileView — not a new format)
related:
  - FACTS.md
  - ARCHITECTURE.md
  - CURRENT.md
---

# Proteus — Config schema (settings.json)

Honest inventory of keys owned by `Config.qml` → `~/.config/proteus/settings.json`.
One schema for all postures; panes enable/disable by capability.

## Groups

| Group | Keys (representative) | Behaviour façade |
|-------|----------------------|------------------|
| Desktop / Hypr | `gapsIn`, `gapsOut`, `borderSize`, `rounding`, `animationsEnabled`, `mouse*` | `Config` / `ConfigHypr` → `proteus-general.conf` |
| Chrome | `accentId`, `accentCustom`, `chromeMode`, `chromeOpacity`, `chromeBlur`, `dock*`, `bar*`, `iconPlateMode`, `iconPlateCustom`, `iconOverrides` | Theme + ConfigHypr + DockApps |
| Lock prefs | `lockOnSessionStart`, `lockDim`, `lockBackgroundMode`, `lockWallpaper*`, `lockDaily*` | Background |
| Lock/desktop applets | `lockWidgets[]`, `desktopWidgets[]`, `desktopWidgetsSnapToGrid`, `lockShowClock` | Widgets |
| Wallpaper | `wallpaperKind`, `wallpaperId`, `wallpaperMode`, `wallpaperColor`, `wallpaperCustomPath`, `wallpaperFolder`, `wallpaperShuffle`, `wallpaperAlbum*`, `wallpaperSlideshow*`, `wallpaperDaily*`, `wallpaperVideo*`, `wallpaperReactive*` | Background |
| Audio prefs | `audioLatency` | Audio |
| Location / weather | `location*`, `weatherUnits`, `weatherEnabled` | Weather / Date, time & weather / Privacy & security |
| Tailscale | `tailscaleLoginServer` | Network Tailscale leaf |
| Font | `fontFamily`, `fontSize`, `fontSizeSm`, `userFonts` (`Family=/path;…`) | Theme / Style pane |
| Beacon | `launcherRecents`, `launcherFileRecents`, `launcherTagCatalog`, `launcherAppTags` | Beacon (system search; keys keep the legacy `launcher` prefix — persisted) |
| Dock pins | `dockPins` (comma desktop ids; `""` defaults; `-` empty) | DockApps |
| Icon plates / overrides | `iconPlateMode` (`default` \| `dark` \| `clear` \| `tinted`), `iconPlateCustom`, `iconOverrides` (`id=path;…`) | Theme + DockApps / EnvGate |
| Notifications | `notificationsDnd` | Notifications |

**Not account secrets:** OAuth tokens live under
`~/.local/share/proteus/accounts/tokens/` (0600) via `proteus-accounts`; public
seat metadata in `~/.config/proteus/accounts.json`. Never in `settings.json`.

Arrays (`lockWidgets`, `desktopWidgets`, `wallpaperAlbums`, `wallpaperDailySources`)
are JSON lists; normalizers live on Widgets / Background. Widget instances carry
per-type option fields (clock `clockWeight`/`clockColor`/`showDate`/`dateStyle`/
`clockDepth`, media `showControls`/`showWhenIdle`, note `noteText`, world clock
`tzId`/`tzLabel`). Catalog types are one-per-surface unless the entry sets
`unique: false` (world clock — one instance per city).

## Not in this file

- Keybind overrides → `keybinds.json`
- Hardware probe cache → `hw-probe.json`
- Monitor lines → `proteus-monitors.conf`
- Generated binds → `proteus-keybinds.conf`
