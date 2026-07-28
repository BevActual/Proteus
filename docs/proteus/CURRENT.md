---
doc: current
role: status
audience: contributors, coding agents
last_updated: "2026-07-27"
doc_status: active
scope: Honest inventory of what exists in the repo / guest today
related:
  - POSITIONING.md
  - ARCHITECTURE.md
  - POSTURES.md
  - SETTINGS-IA.md
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
| [7. Docs locks (ahead of code)](#7-docs-locks-ahead-of-code) | Stack / compositor |
| [8. Not yet](#8-not-yet) | Explicit gaps |

---

## 1. Platform

| Piece | Status | Notes |
|-------|--------|-------|
| Arch Linux guest | `shipped` | QEMU/KVM via `vm/run.sh` |
| Hyprland session | `shipped` | Backend for desktop posture; greetd / proteus-session |
| Quickshell shell | `shipped` | Chrome runtime; `/mnt/proteus/shell` via 9p |
| Nested Hyprland (host) | `shipped` | `scripts/run-nested.sh` — shell-only quick test |
| Hyprland posture profiles | `planned` | See [COMPOSITOR.md](./COMPOSITOR.md) |
| QS version pin / respawn policy | `planned` | Hotplug fragility awareness |

---

## 2. Shell

Desktop (`shell/surfaces/DesktopShell.qml` + `desktop/`):

| Feature | Status |
|---------|--------|
| Top bar (launcher, workspaces, title, clock, settings) | `partial` — status cluster opens Control Center (notifications + quick settings) |
| Control Center (notifications + quick settings) | `partial` — DND, volume/mute, network editor, battery; toasts; no Settings pane yet |
| App launcher (`Super+Space` / `Super+D`) | `shipped` |
| Dock (pins, magnify, running dots) | `shipped` |
| Desktop widgets (free place; Customize) | `partial` — long-press empty desktop or `Super+Shift+W`; catalog clock/media/battery; separate from lock |
| Lock screen (`Super+L`, PAM + `WlSessionLock`) | `shipped` — Customize mode, zone layout, applets; cold boot auto-lock; attempt cooldown after 3 misses |
| Global shortcuts (launcher, settings, lock) | `shipped` |
| Hardware probe at session start (`Hardware.qml`) | `shipped` — Wave A |
| Env gate (launcher / Settings / dock) | `shipped` — `EnvGate.qml` |
| Theme tokens | `shipped` — space/radius scale + accent/font from Config |

---

## 3. Settings

App: `apps/proteus-settings/` · launcher `proteus-settings` · `Super+,`

| Pane | Status |
|------|--------|
| Appearance → Accent / Background / Lock / Font (`style`) | `partial` — lock wallpaper/dim in Settings; widgets via lock Customize (long-press); Kind parity, daily, slideshow, fonts, `proteus-bg` |
| Desktop → Gaps / Borders / Motion / Dock & menu bar (`proteus-general.conf` + sizes) | `shipped` |
| Displays (scale / mode / orientation, Identify; Revert parked) | `partial` |
| Peripherals → Keyboard (shortcuts) / Mouse (sensitivity, accel) | `shipped` |
| Software → Updates / Search (propose → confirm → `pkexec proteus-pkg`) | `partial` |
| Sound (output + input, peak meter, per-app volume, latency/buffer, test tone) | `partial` |
| Network (status + open editor; Bluetooth / VPN later) | `partial` |
| About (session power + hardware class / capabilities) | `partial` |
| Power · Users · Online accounts · Date & time · Privacy | `stub` — sidebar + roadmap checklist |
| Host / VM·container setup | **out of Settings** — separate app later |

Modular panes: `apps/proteus-settings/panes/*` (shell stays in `Settings.qml`).
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
| `~/.config/proteus/settings.json` | Theme/desktop prefs (Config.qml); `lockWidgets[]`, `desktopWidgets[]`, `notificationsDnd` |
| `~/.config/proteus/keybinds.json` | Shortcut overrides |
| `~/.config/proteus/hw-probe.json` | Cached Wave A hardware probe |
| `~/.config/hypr/proteus-keybinds.conf` | Generated Hyprland binds (sourced) |
| `~/.config/hypr/proteus-general.conf` | Gaps, borders, rounding, animations (sourced) |
| `~/.config/hypr/proteus-monitors.conf` | Displays live `monitor =` lines (sourced) |
| `~/.config/hypr/hyprland.conf` | Guest/session compositor config |
| `env/hyprland.conf` | Nested template (sources general / monitors / keybinds) |
| `env/proteus-keybinds.conf` | Default binds template |
| `env/proteus-general.conf` | Default desktop fragment |
| `env/proteus-monitors.conf` | Default monitors stub |

---

## 6. Harness

| Command | Role |
|---------|------|
| `./vm/run.sh` | Boot installed guest |
| `./vm/run.sh snapshot\|restore` | qcow2 snapshots (`hyprland-base`, …) |
| `bash /mnt/proteus/vm/guest/install-settings-app.sh` | Install Settings + keybinds + desktop/displays conf |
| `bash /mnt/proteus/vm/guest/install-keybinds.sh` | Keybinds file + hypr source (user home) |
| `bash /mnt/proteus/vm/guest/install-desktop-conf.sh` | `proteus-general.conf` + `proteus-monitors.conf` + sources |
| `bash /mnt/proteus/vm/guest/install-lock-pam.sh` | `/etc/pam.d/proteus-lock` (falls back to `login` if absent) |
| `./scripts/run-nested.sh` | Nested Hyprland on host |

SSH default: `ssh -p 2222 andrew@127.0.0.1`

---

## 7. Docs locks (ahead of code)

| Lock | Doc | Code status |
|------|-----|-------------|
| Stack split (QML / Tauri / Rust) | [STACK.md](./STACK.md) | Settings+shell = QML; no Tauri apps yet |
| Hyprland as backend + QS limits | [COMPOSITOR.md](./COMPOSITOR.md) | Keybinds + general fragments `shipped`; monitors stub `partial`; profiles `planned` |
| Adaptive apps / environment contract | [APPLICATIONS.md](./APPLICATIONS.md) | `planned` — launcher is DesktopEntries only |
| Hardware module catalog | [HARDWARE.md](./HARDWARE.md) | Wave A probe + `Hardware.qml` session load |
| Capability / posture resolver | [POSTURES.md](./POSTURES.md) | Probe → caps in shell; posture still stub |

---

## 8. Not yet

- Per-posture Hyprland profiles  
- Full Displays drag-layout editor (scale/mode Apply shipped)
- Displays **Revert** button (Apply works; Revert unreliable in VM — parked)  
- Quickshell respawn policy + version pin in guest/ISO  
- Host posture chrome or workload panes  
- Second personal posture beyond stub  
- First-party Tauri app under `apps/`  
- More Rust helper CLIs under `services/` (Wave A probe is Python; `proteus-pkg` mutator shipped)  
- Smoke script suite (Meridian-style `*-smoke.sh`) beyond hw-probe  
- Adaptive app manifests (declarative) + richer launcher filtering  
- ISO / installer productization  

When shipping a feature, update this file in the same change.
