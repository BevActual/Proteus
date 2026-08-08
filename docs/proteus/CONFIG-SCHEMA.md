---
doc: config-schema
role: reference
audience: coding agents, contributors
last_updated: "2026-08-08"
doc_status: active
scope: settings.json key groups (shell-core / iced Settings — not a new format)
related:
  - FACTS.md
  - ARCHITECTURE.md
  - CURRENT.md
---

# Proteus — Config schema (settings.json)

Honest inventory of keys in `~/.config/proteus/settings.json` (shell-core schema
SoT; iced Settings writes). One schema for all postures; panes enable/disable by
capability.

## Groups

| Group | Keys (representative) | Behaviour façade |
|-------|----------------------|------------------|
| Desktop / compositor | `gapsIn`, `gapsOut`, `borderSize`, `rounding`, `animationsEnabled`, `mouse*`, `workspaceMode` (`synced` \| `perDisplay`), `workspaceNames` (string[10] labels for logical Spaces 1–10; `""` = number), `workspaceOrder` (int[10] strip visual perm of 1–10; empty = identity; Super+N stays logical), `specialWorkspaces` (string[] custom `special:*` slugs; max 8; reserved `scratch`/`minimized` excluded), `specialWorkspaceChords` (`{ slug: { mods, key } }` optional toggle chords), `specialWorkspaceMoveChords` (same shape) | `proteus-settings-apply` / compositorctl · Spaces helpers · keybinds Fact |
| Touchpad / tablet | `touchpadNaturalScroll`, `touchpadTapToClick`, `touchpadDisableWhileTyping`, `touchpadClickfinger`, `touchpadScrollFactor`, `tabletRelativeInput`, `tabletLeftHanded`, `tabletOutput`, `tabletTransform`, `tabletActiveAreaPosX`, `tabletActiveAreaPosY`, `tabletActiveAreaSizeX`, `tabletActiveAreaSizeY` (mm; size `0 0` = unset), `tabletPressureMin`, `tabletPressureMax` (`-1` = driver default · global linear remap), `tabletEraserButtonMode` (`0` hardware · `1` button event), `tabletEraserButtonOverride` (linux button code · `0` default), `tabletRegionPosX`, `tabletRegionPosY`, `tabletRegionSizeX`, `tabletRegionSizeY` (px; size `0 0` = unset), `tabletRegionAbsolute` | Settings → Peripherals → Touchpad / Tablet · `input:touchpad:*` / `input:tablet:*` / `input:tablettool:*` (bezier per-tool curves / gestures Out) |
| Per-device input | `inputDeviceOverrides` (`[{ name, sensitivity, accelFlat }]`, max 16) | Settings → Peripherals → Mouse · compositor `input-reload` (per-device overrides still thin / Out for full matrix) |
| Gamepads | `gamepadsGuideSingle`, `gamepadsGuideDouble` (`nav` \| `cc` \| `off`) | Settings → Peripherals → Gamepads · `proteus-guide` |
| Console | `consoleRecents`, `consoleLastMediaPath` | Recents Fact (secondary; list IA is primary) · Media lean sheet resume path |
| Chrome | `accentId`, `accentCustom`, `chromeMode`, `chromeOpacity`, `chromeBlur`, `dock*`, `bar*`, `iconPlateMode`, `iconPlateCustom`, `iconOverrides` | `proteus-ui` tokens + shell dock/bar |
| Lock prefs | `lockOnSessionStart`, `lockDim`, `lockBackgroundMode`, `lockWallpaper*`, `lockDaily*` | Background |
| Lock/desktop applets | `lockWidgets[]`, `desktopWidgets[]`, `desktopWidgetsSnapToGrid`, `lockShowClock` | Widgets |
| Wallpaper | `wallpaperKind`, `wallpaperId`, `wallpaperMode`, `wallpaperColor`, `wallpaperCustomPath`, `wallpaperFolder`, `wallpaperShuffle`, `wallpaperAlbum*`, `wallpaperSlideshow*`, `wallpaperDaily*`, `wallpaperVideo*`, `wallpaperReactive*` | Background |
| Audio prefs | `audioLatency` | Audio |
| Location / weather | `location*`, `weatherUnits`, `weatherEnabled` | Weather / Date, time & weather / Privacy & security |
| Tailscale | `tailscaleLoginServer` | Network Tailscale leaf |
| Headscale admin | `headscaleAdminUrl` | Network Headscale leaf (API key in vault, not settings.json) |
| Font | `fontFamily`, `fontSize`, `fontSizeSm`, `userFonts` (`Family=/path;…`) | Theme / Style pane |
| Beacon | `launcherRecents`, `launcherFileRecents`, `launcherTagCatalog`, `launcherAppTags` | Beacon (system search; keys keep the legacy `launcher` prefix — persisted) |
| Dock pins | `dockPins` (comma desktop ids; `""` defaults; `-` empty) | DockApps |
| Icon plates / overrides | `iconPlateMode` (`default` \| `dark` \| `clear` \| `tinted`), `iconPlateCustom`, `iconOverrides` (`id=path;…`) | tokens + dock / shell-core icon resolve |
| Notifications | `notificationsDnd` | Notifications (hard quiet) |
| Focus Mode | `focusAllowedApps`, `focusBreakCritical`, `focusProfiles`, `focusActiveProfileId` | Focus — soft quiet + allowlist / keywords / schedules (not a posture). Profile objects: `{ id, name, allowedApps[], breakCritical, keywordAllow[], keywordDeny[], schedule? }` — entity CRUD via Settings → Desktop → Focus |
| Control Center layout | `controlCenterLayout` | ControlCenterLayout — `{ version, columns, plates, tiles[{id,visible,span,size}] }` Customize foundation |

**Not account secrets:** OAuth tokens live under
`~/.local/share/proteus/accounts/tokens/` (0600) via `proteus-accounts`; public
seat metadata in `~/.config/proteus/accounts.json`. Lock-screen unlock PIN hash
lives under `~/.local/share/proteus/auth/pin` (0600) via `proteus-pin.py` /
`check-unlock.py` — never in `settings.json`. Headscale admin API key lives under
`~/.local/share/proteus/headscale/api-key` (0600) via `proteus-headscale.py` —
only `headscaleAdminUrl` is in `settings.json`.

**Not permission grants:** App permission categories + per-app Allow/Ask/Deny live
in `~/.config/proteus/permissions.json` (0600) via `proteus-permissions.py` /
`proteus-permissions.py` / shell-core — never in `settings.json` (parallel to `keybinds.json`).

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
