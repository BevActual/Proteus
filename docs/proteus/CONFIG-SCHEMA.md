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
| Lock/desktop applets | `lockWidgets[]`, `desktopWidgets[]`, `lockShowClock` | Widgets |
| Wallpaper | `wallpaperKind`, `wallpaperId`, `wallpaperMode`, `wallpaperColor`, `wallpaperCustomPath`, `wallpaperFolder`, `wallpaperShuffle`, `wallpaperAlbum*`, `wallpaperSlideshow*`, `wallpaperDaily*`, `wallpaperVideo*`, `wallpaperReactive*` | Background |
| Audio prefs | `audioLatency` | Audio |
| Location / weather | `location*`, `weatherUnits` | Weather / DateTime |
| Font | `fontFamily`, `fontSize`, `fontSizeSm`, `userFonts` (`Family=/path;…`) | Theme / Style pane |
| Launcher | `launcherRecents`, `launcherTagCatalog`, `launcherAppTags` | Spotlight / Launcher |
| Dock pins | `dockPins` (comma desktop ids; `""` defaults; `-` empty) | DockApps |
| Icon plates / overrides | `iconPlateMode` (`default` \| `dark` \| `clear` \| `tinted`), `iconPlateCustom`, `iconOverrides` (`id=path;…`) | Theme + DockApps / EnvGate |
| Notifications | `notificationsDnd` | Notifications |

Arrays (`lockWidgets`, `desktopWidgets`, `wallpaperAlbums`, `wallpaperDailySources`)
are JSON lists; normalizers live on Widgets / Background.

## Not in this file

- Keybind overrides → `keybinds.json`
- Hardware probe cache → `hw-probe.json`
- Monitor lines → `proteus-monitors.conf`
- Generated binds → `proteus-keybinds.conf`
