---
doc: facts
role: reference
audience: coding agents, contributors
last_updated: "2026-07-30"
doc_status: active
scope: On-disk truth paths; QML façade vs services mutators
related:
  - CONFIG-SCHEMA.md
  - ARCHITECTURE.md
  - STACK.md
  - CURRENT.md
---

# Proteus — system facts

Truth lives on **disk / CLI**. QML singletons are façades. Prefer this map
before inventing a second store.

## Paths

| Path | Owner (write) | Readers |
|------|---------------|---------|
| `~/.config/proteus/settings.json` | `Config.qml` FileView | Background, Widgets, Theme, Audio prefs, … |
| `~/.config/proteus/keybinds.json` | `Keybinds.qml` | Hyprland bind generator |
| `~/.config/proteus/hw-probe.json` | `proteus-hw-probe` / `Hardware.qml` cache | EnvGate, Settings About |
| `~/.config/hypr/proteus-general.conf` | `Config` / `ConfigHypr` | Hyprland `source =` |
| `~/.config/hypr/proteus-keybinds.conf` | `Keybinds.qml` | Hyprland |
| `~/.config/hypr/proteus-monitors.conf` | `Displays.qml` | Hyprland |
| `~/.config/hypr/proteus-profile.conf` | `set-hypr-profile.sh` / `HyprProfile.qml` / seed | Hyprland `source =` → `profiles/*.conf` |
| `~/.config/hypr/profiles/*.conf` | seed / manual / Settings soft picker | Active soft profile via pointer |
| `~/.local/share/proteus/backgrounds/` | Background daily/album flows | `proteus-bg` / wallpaper runner |
| `~/.config/systemd/user/proteus-qs.service` | `install-proteus-qs-user-unit.sh` (opt-in) | `systemctl --user` · alternative to hypr `exec-once` |

Seed templates for nested/host sessions: [`env/`](../../env/) — see
[`env/README.md`](../../env/README.md). Guest installers that **place** those
facts: [`vm/guest/`](../../vm/guest/).

## Ownership (hard)

| Module | Owns | Must not |
|--------|------|----------|
| **Config** | One `settings.json` FileView + adapter keys; Hypr/chrome apply via `ConfigHypr` | `property alias` to Background/Widgets |
| **Background** | Wallpaper/lock backdrop catalogs, derived paths, setters, fetch/apply | Persisting keys (read/write `Config.*` fields) |
| **Widgets** | Applet catalog + lock/desktop CRUD | Own FileView |
| **Theme** | Chrome tokens from Config accent/font/mode | System facts |
| **SystemInfo** | Read-only OS/kernel/QS/Hypr strings + About copy summary | Privileged writes; hostname edit |
| **Accounts** | Online accounts catalog + seat status via `proteus-accounts` | OAuth secrets in `settings.json`; inventing mail/contacts apps |

**Why flat `shell/shared/`:** Quickshell directory imports + `property alias`
across singletons in *subdirectories* (or via `qmldir`) hit load-order cycles.
Keep **pragma Singleton** files and their helpers in the **same package
directory**. Name helpers clearly (`BackgroundDaily.qml`, `ConfigHypr.qml`, …).

## QML façade vs services

| Kind | Stack | Rule |
|------|-------|------|
| Preference / chrome state | QML (`shell/shared/…`) | One Config schema; façades mutate via FileView or thin helpers |
| Read-only discovery | Python OK (`services/proteus-hw-probe`) | JSON out; no privileged write |
| Privileged mutation | Rust CLI (`services/proteus-pkg`, `services/proteus-logind`, …) + polkit | Settings proposes → confirm → helper |
| Online accounts seats | Rust CLI `services/proteus-accounts` (user vault; no polkit) | Tokens outside `settings.json`; PKCE browser connect |
| Hot-path read (mixer) | Rust resident `proteus-audio-mix serve` (+ Python fallback) | Dump+peaks while Apps/Mixer open |
| Power mode (PPD) | `powerprofilesctl` / `power-profiles-daemon` (session polkit) | Eco = `power-saver`; no Proteus helper |

**Do not** add silent Python helpers for privileged mutation. **Do not** grow a
second `settings-*.json` per posture.

## Shared package layout

Public API: `import "../../shared"` (Settings: `shared` → `../../shell/shared`).

```
shell/shared/
  Theme.qml Config.qml ConfigHypr.qml
  Background.qml BackgroundCatalog.qml BackgroundDaily.qml BackgroundApply.qml
  Widgets.qml WidgetsLock.qml WidgetsDesktop.qml
  Audio.qml Brightness.qml Hud.qml Power.qml DateTime.qml Weather.qml Displays.qml …
  ShellState.qml Hardware.qml EnvGate.qml Keybinds.qml Notifications.qml LockLayoutZones.qml
apps/proteus-settings/
  kit/     # SettingsFormRow · Group · HubList · Segmented · StickyPaneLoader
  panes/   # product panes
```

Schema key groups: [CONFIG-SCHEMA.md](./CONFIG-SCHEMA.md).
