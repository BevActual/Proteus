---
doc: config-schema
role: reference
audience: coding agents, contributors
last_updated: "2026-07-28"
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
| Chrome | `accentId`, `accentCustom`, `chromeMode`, `chromeOpacity`, `chromeBlur`, `dock*`, `bar*` | Theme + ConfigHypr |
| Lock prefs | `lockOnSessionStart`, `lockDim`, `lockBackgroundMode`, `lockWallpaper*`, `lockDaily*` | Background |
| Lock/desktop applets | `lockWidgets[]`, `desktopWidgets[]`, `lockShowClock` | Widgets |
| Wallpaper | `wallpaperKind`, `wallpaperId`, `wallpaperMode`, `wallpaperColor`, `wallpaperCustomPath`, `wallpaperFolder`, `wallpaperShuffle`, `wallpaperAlbum*`, `wallpaperSlideshow*`, `wallpaperDaily*`, `wallpaperVideo*`, `wallpaperReactive*` | Background |
| Audio prefs | `audioLatency` | Audio |
| Location / weather | `location*`, `weatherUnits` | Weather / DateTime |
| Font | `fontFamily`, `fontSize`, `fontSizeSm` | Theme / Style pane |
| Notifications | `notificationsDnd` | Notifications |

Arrays (`lockWidgets`, `desktopWidgets`, `wallpaperAlbums`, `wallpaperDailySources`)
are JSON lists; normalizers live on Widgets / Background.

## Not in this file

- Keybind overrides → `keybinds.json`
- Hardware probe cache → `hw-probe.json`
- Monitor lines → `proteus-monitors.conf`
- Generated binds → `proteus-keybinds.conf`
