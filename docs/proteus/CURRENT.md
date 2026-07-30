---
doc: current
role: status
audience: contributors, coding agents
last_updated: "2026-07-30"
doc_status: active
scope: Honest inventory of what exists in the repo / guest today
related:
  - POSITIONING.md
  - ARCHITECTURE.md
  - POSTURES.md
  - SETTINGS-IA.md
  - CHROME.md
  - STACK.md
  - COMPOSITOR.md
  - ../../README.md
  - ../../vm/README.md
status_legend:
  shipped: Works in dogfood path
  partial: Present; gaps remain
  planned: Specced; not built
  stub: Placeholder only
---

# Proteus — current status

**Early scaffold.** Desktop spine is the only serious posture. Docs describe
the thesis ahead of code where marked `planned`.

## Document map

| Section | Contents |
|---------|----------|
| [1. Platform](#1-platform) | Arch guest, Hyprland, Quickshell |
| [2. Shell](#2-shell) | Desktop chrome |
| [3. Settings](#3-settings) | Control center |
| [4. Postures](#4-postures) | Loader status |
| [5. Config facts](#5-config-facts) | On-disk paths |
| [6. Harness](#6-harness) | VM / nested |
| [7. Docs locks (ahead of code)](#7-docs-locks-ahead-of-code) | Stack / compositor / chrome |
| [8. Not yet](#8-not-yet) | Explicit gaps |

---

## 1. Platform

| Piece | Status | Notes |
|-------|--------|-------|
| Arch Linux guest | `shipped` | QEMU/KVM via `vm/run.sh` |
| Hyprland session | `shipped` | Backend for desktop posture; greetd / proteus-session |
| Quickshell shell | `shipped` | Chrome runtime; `/mnt/proteus/shell` via 9p |
| Nested Hyprland (host) | `shipped` | `scripts/run-nested.sh` — shell-only quick test |
| Hyprland posture profiles | `partial` — desktop + media/host/home stubs + `proteus-profile.conf`; see [COMPOSITOR.md](./COMPOSITOR.md) |
| QS version pin / respawn policy | `partial` — `proteus-qs` backoff + version recorded in `qs-guest-smoke`; IgnorePkg/ISO pin later |

---

## 2. Shell

Desktop (`shell/surfaces/DesktopShell.qml` + `desktop/`):

| Feature | Status |
|---------|--------|
| Top bar (launcher, workspaces, title, clock, settings) | `partial` — glass menu bar; app title on left; status cluster → Control Center |
| Control Center (notifications + quick settings) | `partial` — DND, volume/mute, network editor, battery; toasts; no Settings pane yet |
| App launcher (`Super+Space` / `Super+D`) | `partial` — Apps / Files / Clipboard modes (Ctrl+1–3); fuzzy + tags + Settings; calc/convert; cliphist clipboard; home-folder file search; no Actions yet |
| Dock (pins, magnify, running dots) | `partial` — floating glass shelf + Mag; closer to macOS Dock |
| Session start (`proteus-session`) | `partial` — `start-hyprland` watchdog; no Ghostty exec-once; stray system apps hidden from launcher |
| Desktop widgets (free place; Customize) | `partial` — long-press empty desktop or `Super+Shift+W`; catalog via `Widgets.qml`; separate from lock |
| Lock screen (`Super+L`, PAM + `WlSessionLock`) | `shipped` — Customize mode, zone layout, applets; cold boot auto-lock; attempt cooldown after 3 misses |
| Global shortcuts (launcher, settings, lock) | `shipped` |
| Hardware probe at session start (`Hardware.qml`) | `shipped` — Wave A |
| Env gate (launcher / Settings / dock) | `shipped` — `EnvGate.qml` (+ `env/apps` manifests); app icon resolve + Proteus brand marks |
| Chrome design lock (`CHROME.md`) | `shipped` — principles + token tables + Settings patterns; sibling export `env/chrome/` `shipped` |
| Theme tokens | `shipped` — space/radius scale + accent/font from Config; company lock [CHROME.md](./CHROME.md) |
| Shared package layout (flat + helpers) | `shipped` — Config/Background ownership split; Settings `kit/`; guest dogfood OK |
| Smoke suite (`scripts/*-smoke.sh`) | `shipped` — layout · config-schema · app-manifest · chrome-tokens · hw-probe · install; optional qs-guest |

---

## 3. Settings

App: `apps/proteus-settings/` · launcher `proteus-settings` · `Super+,`

| Pane | Status |
|------|--------|
| Appearance → Accent / Background / Lock / Icons / Font (`style`) | `partial` — Kind/color chrome shared via `kit/` (`SettingsKindPicker`, `SettingsColorPresetGroup`, `ColorGraphPicker` with debounced commit); Dark/Light segmented; empty-album honesty + Missing stock thumbs; preview above Kind (Background/Lock); Settings deferred domain hydrate re-entry safe; lock wallpaper/dim in Settings (widgets via lock Customize); daily/slideshow/`proteus-bg`; Font searchable picker (`SettingsFontPicker`) + user-scoped Add/Remove (`userFonts`); Icons per-style squircle compare (`SettingsIconStylePicker`) + Tint graph; settings.json / hypr live apply coalesced mid-drag; mega-page merge Out |
| Desktop → Gaps / Borders / Motion / Dock & menu bar / Launcher (`proteus-general.conf` + sizes + Spotlight tags/recents) | `shipped` |
| Displays (scale / mode / orientation, Identify; layout canvas) | `partial` — drag layout + full-snapshot Revert; multi-monitor dogfood preferred |
| Peripherals → Keyboard (shortcuts) / Mouse (sensitivity, accel) | `shipped` |
| Software → Updates / Repos / AUR / Flathub / AppImages / Orphans (Install\|Installed mode-safe loads; sticky action bar; rich rows; live op command + Cancel + last error; empty Installed honesty; popular browse; leaf UI memory) | `partial` — optional guest: `yay`/`paru`, `flatpak` + Flathub; AppImages need no helper; dep graphs / Snap Out; `./scripts/software-reliability-smoke.sh` + optional `./scripts/software-guest-smoke.sh` |
| Sound → Output / Input / Applications / Latency & buffer (`sound`) | `partial` — category hub; streaming input peak meter, per-app volume, test tone |
| Network (hostname, Wi‑Fi connect, Bluetooth, Tailscale, NM VPN) | `partial` — password Wi‑Fi / pairing / Headscale via system tools |
| Power (battery via UPower; logind idle/lid read-only + conf escape hatch) | `partial` — writing lid/idle needs a privileged helper |
| Date & time (clock, timezone search, NTP, locale, **Location**) | `partial` — timezone/NTP polkit-gated; location is explicit place search (never IP); Open-Meteo weather for that place + desktop/lock weather widget; no forecast view |
| Users (session actions + read-only local users) | `partial` — no add/remove; greeter planned |
| Online accounts (provider seats) | `partial` — coming soon; no OAuth |
| Privacy (permission categories) | `partial` — listed; not enforced |
| About (hardware class / capabilities) | `partial` — session actions → Users |
| Host / VM·container setup | **out of Settings** — separate app later |
| Cold-start (open feel) | `shipped` — async `shell.qml` → `Settings.qml`; `kit/StickyPaneLoader` (active category first, sticky after visit); Keyboard/Keybinds deferred; Settings QS skips live hw-probe (`Hardware.isSettingsApp` → cache only) |

Modular panes: `apps/proteus-settings/panes/*` · form kit: `kit/*` (shell stays in `Settings.qml`).
Shared spine: flat `shell/shared/` + named helpers — [FACTS.md](./FACTS.md).
North-star IA: [SETTINGS-IA.md](./SETTINGS-IA.md).

---

## 4. Postures

Locked product set: [POSTURES.md](./POSTURES.md).

| Posture | Status |
|---------|--------|
| desktop | `partial` — primary |
| media · wearable · xr | `planned` (legacy stubs: `couch` / `watch` / `vr`) |
| vehicle · home · host | `planned` — no shell stub yet |
| phone (loader only) | `stub` — **not** in locked set |

Selection today: `PROTEUS_SURFACE` env (default `desktop`). See POSTURES § Loader map.

---

## 5. Config facts

| Path | Role |
|------|------|
| `~/.config/proteus/settings.json` | Theme/desktop prefs (Config.qml FileView); wallpaper keys; `lockWidgets[]`, `desktopWidgets[]`, `notificationsDnd` — behaviour in Background / Widgets / Audio / … |
| `~/.config/proteus/keybinds.json` | Shortcut overrides |
| `~/.config/proteus/hw-probe.json` | Cached Wave A hardware probe |
| `~/.config/hypr/proteus-keybinds.conf` | Generated Hyprland binds (sourced) |
| `~/.config/hypr/proteus-general.conf` | Gaps, borders, rounding, animations (sourced) |
| `~/.config/hypr/proteus-monitors.conf` | Displays live `monitor =` lines (sourced) |
| `~/.config/hypr/proteus-profile.conf` | Active posture profile pointer → `profiles/*.conf` |
| `~/.config/hypr/profiles/*.conf` | Posture fragments (desktop shipped; media/host/home stubs) |
| `~/.config/hypr/hyprland.conf` | Guest/session compositor config |
| `env/hypr/hyprland.conf` | Nested template (sources general / monitors / keybinds / profile) |
| `env/hypr/proteus-keybinds.conf` | Default binds template |
| `env/hypr/proteus-general.conf` | Default desktop fragment |
| `env/hypr/proteus-monitors.conf` | Default monitors stub |
| `env/hypr/proteus-profile.conf` | Default active-profile pointer |
| `env/hypr/profiles/*.conf` | Posture profile seeds |

---

## 6. Harness

| Command | Role |
|---------|------|
| `./vm/run.sh` | Boot installed guest (disk under `PROTEUS_VM_CACHE`, default `~/.cache/proteus-vm`) |
| `./vm/run.sh snapshot\|restore` | qcow2 snapshots (`hyprland-base`, …) |
| `./vm/download-iso.sh` / `create-disk.sh` | Fetch ISO / create disk in cache |
| `./vm/provision.sh` | Prepare ISO/disk hints + SSH overlay (`bootstrap.sh`) |
| `./vm/bootstrap.sh` | SSH guest → light overlay (`vm/install/bootstrap.sh`) |
| `bash /mnt/proteus/vm/install/bootstrap.sh` | On guest: staged overlay (skip/resume/only knobs; keep base packages thin) |
| `./vm/install/check.sh` | Host tree/`bash -n` gate for overlay stages |
| `bash /mnt/proteus/vm/guest/install-settings-app.sh` | Install Settings + keybinds + desktop/displays conf |
| `bash /mnt/proteus/vm/guest/install-keybinds.sh` | Keybinds file + hypr source (user home) |
| `bash /mnt/proteus/vm/guest/install-desktop-conf.sh` | `proteus-general.conf` + `proteus-monitors.conf` + sources |
| `bash /mnt/proteus/vm/guest/install-lock-pam.sh` | `/etc/pam.d/proteus-lock` (falls back to `login` if absent) |
| `./scripts/run-nested.sh` | Nested Hyprland on host |
| `./scripts/smoke-all.sh` | Host smokes (layout · config · hw-probe · install); guest QS if SSH or `PROTEUS_GUEST=1` |
| `./scripts/layout-smoke.sh` | Flat `shell/shared/` + Settings `kit/` structure |
| `./scripts/config-schema-smoke.sh` | Config FileView keys ↔ `tests/fixtures/settings.minimal.json` |
| `./scripts/install-smoke.sh` | Overlay installer tree check |
| `./scripts/software-reliability-smoke.sh` | Host static checks for Software mode-safe loads + op narrative |
| `./scripts/software-guest-smoke.sh` | Guest Software dogfood (browse/inventory + Flatpak install/remove; pacman mutator if passwordless sudo) |
| `./scripts/qs-guest-smoke.sh` | Guest cold-start `SHELL_OK` / `SETTINGS_OK` + record `quickshell` version |

SSH default: `ssh -p 2222 andrew@127.0.0.1`

---

## 7. Docs locks (ahead of code)

| Lock | Doc | Code status |
|------|-----|-------------|
| Stack split (QML / Tauri / Rust) | [STACK.md](./STACK.md) | Settings+shell = QML; no Tauri apps yet |
| Hyprland as backend + QS limits | [COMPOSITOR.md](./COMPOSITOR.md) | Keybinds + general + posture profile pointer `shipped`; monitors stub `partial`; media/host/home stubs `partial`; wearable/xr/vehicle `planned` |
| Adaptive apps / environment contract | [APPLICATIONS.md](./APPLICATIONS.md) | `partial` — `env/apps` manifests + EnvGate prefer; postures unused |
| Hardware module catalog | [HARDWARE.md](./HARDWARE.md) | Wave A probe + `Hardware.qml` session load |
| Capability / posture resolver | [POSTURES.md](./POSTURES.md) | Probe → caps in shell; posture still stub |
| Chrome language (company reference) | [CHROME.md](./CHROME.md) | `Theme.qml` + Settings `kit/` + `env/chrome/` export `shipped`; Rowena retarget `partial` |
| Facts / Config schema | [FACTS.md](./FACTS.md) · [CONFIG-SCHEMA.md](./CONFIG-SCHEMA.md) | Layout + docs `shipped` |

---

## 8. Not yet

- Snap / dependency graphs in Software  
- Remaining posture hypr profiles beyond stubs (wearable / xr / vehicle; media/host/home chrome)  
- Displays **Revert** edge cases on fragile VM hotplug (full-snapshot Revert shipped; re-verify after sleep/hotplug)
- systemd/user-unit QS supervisor; pacman IgnorePkg / ISO QS version pin  
- Host posture chrome or workload panes  
- Second personal posture beyond stub  
- First-party Tauri app under `apps/`  
- More Rust helper CLIs under `services/` (Wave A probe is Python; `proteus-pkg` mutator shipped)  
- Posture / prefers / device_classes enforcement on manifests (schema only today)  
- ISO / installer productization (dogfood overlay in `vm/install/` is enough for now)  
- Settings UI for posture profile picker (CLI `set-hypr-profile.sh` only)  
- Rowena (and other sibling) CSS retarget onto `--proteus-*` export  

When shipping a feature, update this file in the same change.
