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
| Hyprland posture profiles | `partial` — desktop + media(console alias)/host/home stubs + soft `set-hypr-profile.sh` + Settings About picker (`HyprProfile.qml`); hard switches `planned` — [POSTURES.md](./POSTURES.md) · [COMPOSITOR.md](./COMPOSITOR.md) |
| QS version pin / respawn policy | `partial` — `proteus-qs` flock + `--restart` + orphan reap + backoff; optional systemd `--user` unit; version recorded in `qs-guest-smoke` / `qs-version-smoke`; after QS upgrade re-run guest smoke; IgnorePkg/ISO pin Out |

---

## 2. Shell

Desktop (`shell/surfaces/DesktopShell.qml` + `desktop/`):

| Feature | Status |
|---------|--------|
| Top bar (launcher, workspaces, title, clock, settings) | `partial` — wallpaper-first glass menu bar (`menuBarAlpha` clearer than dock; soft text outline when thin); app title on left; status cluster → Control Center (unread badge · DND · Awake labels) |
| Control Center (notifications + quick settings) | `shipped` — list empty/Dismiss honesty; toast/`showToast` SoT (DND · CC-open suppress); **unified Sound plate** (master on plate · Listen ▾ · Sources ▾ with per-source volume · Mixer ›); elevated tiles; **Keep Awake** · **LocalSend** · **Power** profile menus; footer deep Sound/Network/Power → Settings; Settings/NM escapes; no Settings Notifications pane |
| Status HUD (volume · brightness) | `shipped` — top-right elevated glass chip (`Hud` / `StatusHud`, toast plate language); XF86 + IPC; suppressed while Control Center open; brightness honest-skip without `/sys/class/backlight` |
| App launcher (`Super+Space` / `Super+D`) | `partial` — Apps / Files / Clipboard / Actions (Ctrl+1–4; active mode pill labels); empty Apps = calm **Recents** hierarchy (or honest empty); empty Files = **Recents** + **Places** (or honest empty); Files search = Folders then Files (depth ≤5 · 40-cap · capped hint); `launcherFileRecents` on open; fuzzy + tags + Settings; EnvGate unavailable honesty (badge · reasons); calc/convert + near-miss hint; cliphist missing-vs-empty; allowlisted Actions (lock/logout/settings/CC/DND/Keep Awake/LocalSend/power) |
| Dock (pins, magnify, running dots) | `shipped` — continuous frosted glass shelf (`glassAlpha` frost floor + curve-following edge glow; no straight specular); smooth magnify; running disc vs active accent pill; long-press edit (−/+ · Done); press-drag reorder / drag-off remove; glass Keep/Remove (`ChromeMenuPlate`) |
| Session start (`proteus-session`) | `partial` — prefers `start-hyprland` (known paths; fail-closed to Hyprland); hypr seed `exec-once` = qs/bg/cliphist only (install strips terminal autostart); `hide-system-apps` via apps + post-install (Settings-covered tools + Quickshell; Calculator stays); host `session-smoke` + `install-smoke` |
| Desktop widgets (free place; Customize) | `partial` — long-press empty desktop or `Super+Shift+W`; free-place + optional Snap to Grid (center graph · no overlap); catalog via `Widgets.qml`; separate from lock |
| Lock screen (`Super+L`, PAM + `WlSessionLock`) | `shipped` — Customize mode, zone layout, applets; cold boot auto-lock; attempt cooldown after 3 misses |
| Global shortcuts (launcher, settings, lock) | `shipped` |
| Hardware probe at session start (`Hardware.qml`) | `shipped` — Wave A |
| Env gate (launcher / Settings / dock) | `shipped` — `EnvGate.qml` (+ `env/apps` manifests); app icon resolve + Proteus brand marks |
| Chrome design lock (`CHROME.md`) | `shipped` — principles + token tables + Settings patterns; sibling export `env/chrome/` `shipped` |
| Theme tokens | `shipped` — space/radius scale + accent/font from Config; company lock [CHROME.md](./CHROME.md) |
| Shared package layout (flat + helpers) | `shipped` — Config/Background ownership split; Settings `kit/`; guest dogfood OK |
| Smoke suite (`scripts/*-smoke.sh`) | `shipped` — layout · config-schema · app-manifest · chrome-tokens · software-reliability · power-logind · audio-mix-serve · hw-probe · install · session · qs-version; optional `qs-guest` + `software-guest` via `smoke-all` / `PROTEUS_GUEST=1` |

---

## 3. Settings

App: `apps/proteus-settings/` · launcher `proteus-settings` · `Super+,`

| Pane | Status |
|------|--------|
| Appearance → Accent / Background / Lock / Icons / Font (`style`) | `shipped` — hub + five `Style*Leaf` StickyPaneLoaders; Kind/color chrome via `kit/` (`SettingsKindPicker`, `SettingsColorPresetGroup`, `ColorGraphPicker` debounced); Dark/Light; empty-album honesty; preview above Kind; lock wallpaper/dim in Settings (widgets via lock Customize); daily/slideshow/`proteus-bg`; Font picker + userFonts Add/Remove; Icons squircle compare + Tint; hypr live apply coalesced; mega-page merge Out |
| Desktop → Gaps / Borders / Motion / Dock & menu bar / Launcher | `shipped` — Appearance-style hub + `Desktop*Leaf` StickyPaneLoaders; Gaps/Borders/Motion `SettingsFormRow` + live hints; Dock disable honesty + Advanced conf escape; Launcher Spotlight blurb (Ctrl+1–4 modes), Clear recent apps + recent files, tag FormRows; live hypr + `proteus-general.conf` / `settings.json` |
| Displays (scale / mode / orientation, Identify; layout canvas) | `shipped` — drag layout + full-snapshot Revert; Refresh/re-entry clears Revert; post-Apply topology drift + Hyprland monitor events cancel Revert; list merge by connector name; clearer Apply/Revert status + conf escape |
| Peripherals → Keyboard (shortcuts) / Mouse (sensitivity, accel) | `shipped` |
| Software → Updates / Repos / AUR / Flathub / AppImages / Orphans (`packages`) | `shipped` — hub + `Packages*Pane` StickyPaneLoaders; Install\|Installed mode-safe loads + leafUi; sticky action bar; live `$` op + Cancel + last error; empty Installed / orphans / AppImages honesty; hub Needs yay/paru · flatpak; AppImages user-only (no polkit); `software-reliability-smoke` (all six leaves) + `software-guest-smoke` in `smoke-all` (yay **or** paru); dep graphs / Snap Out |
| Sound → Output / Input / Applications / Mixer / Latency (`sound`) | `shipped` — Desktop-style hub + `Sound*Leaf` StickyPaneLoaders; **Mixer** Wave Link–style grid (channels/inputs × mixes; Speakers/mix listen; rename; peaks; drag-reorder via `dragSnapshot` + `mixDragging`); resident `proteus-audio-mix serve` for dump+peaks (Python `audio-mix.py` mutations + fallback); Output/Input/Apps/Latency FormRows; pactl + `pw-metadata` |
| Network → This machine / Devices / Wi‑Fi / Bluetooth / LocalSend / Tailscale / VPN (`network`) | `shipped` — Desktop-style hub + `Network*Leaf` StickyPaneLoaders; hostname Apply; device/Wi‑Fi FormRow honesty; LocalSend (`LocalSend.qml` · `NetworkLocalSendLeaf` · :53317 · CC tile menu · install honesty); BT/TS/VPN status + escape hatches; password Wi‑Fi / pairing / Headscale stay system tools |
| Power (PPD mode + battery + idle/lid) | `shipped` — Performance/Balanced/Eco via `powerprofilesctl`; battery via UPower; `pkexec proteus-logind` drop-in + reload (not restart); CC Power tile; charge thresholds / TLP Out |
| Date & time (clock, timezone search, NTP, locale, **Location**) | `shipped` — timezone/NTP/`localectl set-locale` polkit-gated; searchable locale picker + locale.conf escape; Location explicit place search (never IP); Open-Meteo current + **5-day forecast** + Conditions H/L/sunrise; Match time zone to place when TZ differs; desktop/lock weather widget; manual time / RTC writers Out |
| Users (session actions + read-only local users · greetd status) | `shipped` — Session FormRow honesty (Lock/Logout/Reboot/Shutdown); current/other users + Refresh; greetd active/autologin status + read-only conf escape; no add/remove; Settings does not write greeter prefs |
| Online accounts (provider seats) | `partial` — coming soon; no OAuth |
| Privacy (permission categories) | `partial` — listed; not enforced |
| About (hardware class / capabilities) | `partial` — hw-probe class/caps; soft Hyprland profile picker (`HyprProfile` · console≡media); session actions → Users; hard posture switch Out |
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
| desktop | `partial` — primary focus spine |
| console | `planned` — hard switch (game-scoped compositor + sparse shell); code stub `couch`; hypr stub `media.conf` |
| host | `planned` — hard switch (lean/ops; UI on demand); hypr stub `host.conf` |
| home · wearable · xr · vehicle | `parked` — thesis only; not in proof order |

Focus set + hard switches: [POSTURES.md](./POSTURES.md). Selection today:
`PROTEUS_SURFACE` env (default `desktop`). Soft hypr helper:
`set-hypr-profile.sh` (`media` / `console` → console alias) + Settings → About
picker (`HyprProfile.qml`) — soft reload only, not a hard posture switch.

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
| `~/.config/hypr/profiles/*.conf` | Posture fragments (desktop shipped; media=console alias / host / home stubs) |
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
| `./scripts/smoke-all.sh` | Host smokes (layout · config · hw-probe · install · session · qs-version); guest QS if SSH or `PROTEUS_GUEST=1` |
| `./scripts/layout-smoke.sh` | Flat `shell/shared/` + Settings `kit/` structure |
| `./scripts/config-schema-smoke.sh` | Config FileView keys ↔ `tests/fixtures/settings.minimal.json` |
| `./scripts/install-smoke.sh` | Overlay installer tree check |
| `./scripts/session-smoke.sh` | Host gate for `proteus-session` contract + `proteus.desktop` |
| `./scripts/qs-version-smoke.sh` | Record QS version policy (no IgnorePkg); checks `qs-guest-smoke` upgrade path |
| `./scripts/software-reliability-smoke.sh` | Host static checks — all six Software leaves + hub helper honesty + op narrative / leafUi |
| `./scripts/power-logind-smoke.sh` | Host static checks for `proteus-logind` + Power.qml wiring |
| `./scripts/audio-mix-serve-smoke.sh` | Host checks for `proteus-audio-mix` dump/serve + Audio.qml wiring |
| `./scripts/software-guest-smoke.sh` | Guest Software dogfood (browse/inventory + Flatpak install/remove; yay\|paru; pacman mutator if passwordless sudo); in `smoke-all` (SKIP unless SSH / `PROTEUS_GUEST=1`) |
| `./scripts/qs-guest-smoke.sh` | Guest cold-start `SHELL_OK` / `SETTINGS_OK` + record `quickshell` version |

SSH default: `ssh -p 2222 andrew@127.0.0.1`

---

## 7. Docs locks (ahead of code)

| Lock | Doc | Code status |
|------|-----|-------------|
| Stack split (QML / Tauri / Rust) | [STACK.md](./STACK.md) | Settings+shell = QML; no Tauri apps yet |
| Hyprland as backend + QS limits | [COMPOSITOR.md](./COMPOSITOR.md) | Desktop Hyprland `shipped`; console/host hard switches `planned`; media.conf = console alias stub; home parked |
| Adaptive apps / environment contract | [APPLICATIONS.md](./APPLICATIONS.md) | `partial` — `env/apps` manifests + EnvGate prefer; postures unused |
| Hardware module catalog | [HARDWARE.md](./HARDWARE.md) | Wave A probe + `Hardware.qml` session load |
| Capability / posture resolver | [POSTURES.md](./POSTURES.md) | Probe → caps in shell; posture still stub |
| Chrome language (company reference) | [CHROME.md](./CHROME.md) | `Theme.qml` + Settings `kit/` + `env/chrome/` export `shipped`; Rowena retarget `partial` |
| Facts / Config schema | [FACTS.md](./FACTS.md) · [CONFIG-SCHEMA.md](./CONFIG-SCHEMA.md) | Layout + docs `shipped` |

---

## 8. Not yet

- Remaining focus hard switches (**console**, **host**) — game-scoped compositor + sparse shell; lean ops session  
- Soft hypr profile reload sold as posture (use hard switches)  
- Parked postures (home / wearable / xr / vehicle) before focus three are proven  
- Snap / dependency graphs in Software  
- pacman IgnorePkg / ISO QS version pin (record + smoke only today)  
- Host posture chrome or workload panes  
- First-party Tauri app under `apps/`  
- More Rust helper CLIs under `services/` (Wave A probe is Python; `proteus-pkg` + `proteus-logind` mutators + `proteus-audio-mix` resident dump/peaks shipped; mixer mutations still Python)  
- Posture / prefers / device_classes enforcement on manifests (schema only today)  
- ISO / installer productization (dogfood overlay in `vm/install/` is enough for now)  
- Settings UI for posture **hard-switch** picker (soft Hyprland profile picker shipped in About)  
- Rowena (and other sibling) CSS retarget onto `--proteus-*` export  

When shipping a feature, update this file in the same change.
