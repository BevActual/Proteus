---
doc: current
role: status
audience: contributors, coding agents
last_updated: "2026-08-01"
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

Desktop spine is dogfoodable (shell + Settings largely shipped). Console and
console hard switch is `partial` (layered session + proteus-posture); host hard
switch remains planned; parked postures are thesis only. Docs
describe the thesis ahead of code where marked `planned`.

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
| Hyprland posture profiles | `partial` — desktop + console (fullscreen rules) / host / home stubs + soft `set-hypr-profile.sh` + Settings About picker; console hard switch via `proteus-posture` — [POSTURES.md](./POSTURES.md) · [COMPOSITOR.md](./COMPOSITOR.md) |
| QS version pin / respawn policy | `shipped` — `proteus-qs` flock + `--restart` + orphan reap + backoff; optional systemd `--user` unit; version **recorded** in `qs-guest-smoke` / `qs-version-smoke` (not IgnorePkg); after QS upgrade re-run guest smoke; IgnorePkg/ISO pin Out |

---

## 2. Shell

Desktop (`shell/surfaces/DesktopShell.qml` + `desktop/`):

| Feature | Status |
|---------|--------|
| Top bar (workspaces, title, clock+weather center, CC icon) | `shipped` — wallpaper-first glass menu bar (`menuBarAlpha` clearer than dock; soft text outline when thin, including DND/Awake chips); **left**: **traffic-light window controls** for the focused toplevel (Hyprland draws no decorations — bar owns ✕ close · − minimize to `special:minimized` · + maximize `fullscreen 1`; symbols on hover; hidden with no focused window) + app name (desktop-entry lookup via `ActiveWindow.barText`) + dynamic workspace strip (logical Spaces 1–10 via `proteus-workspace`; per-monitor ID bands; default **synced** multi-display switch, Settings → Desktop → Spaces for per-display; Super+Ctrl+N always this display; pills min 4 / cap 10; occupied dots = has toplevels on the logical slot; wheel cycles; "+" jumps to next); **center**: date · time · weather cluster (date dim + time demi · weather glyph/temp; accent soft while calendar open; date drops then cluster fades when left/right chrome crowds the mid band; `…`/`—` while loading/error when location is set) → date/time opens **calendar popover**; weather chip opens **weather glance** (`WeatherPanel` · Open-Meteo conditions/forecast; **Open Weather** → `gnome-weather`); CalendarPanel weather row jumps to weather glance; `chrome calendar` / `chrome weather` IPC); **right**: **app tray** (StatusNotifier — 1Password etc.) · **privacy dots** (mic orange · camera green · screen purple; click → Privacy) · **system services** (network · Bluetooth · volume scroll · battery) + **tiling toggle** (COSMIC-adjacent — grid glyph = tiled, accent overlapping panes = floating; click `togglefloating` on the focused window; floating windows resize by grabbing any edge/corner — hypr `resize_on_border` + 12px grab area — and move with **⌘+drag anywhere on the window** (`bindm` mouse binds emitted with the generated keybinds; ⌘+right-drag resizes); the **accent focus ring** follows hover/keyboard focus: `col.active_border` accent, inactive fully transparent) + status cluster (unread badge · DND · Awake · battery) + **Control Center glyph** (three mini sliders with staggered knobs — ThemeSlider language; knobs slide + accent while open); Beacon button removed from the bar (dock pin + `Super+Space` own it); battery % only with a real battery (`Power.hasBattery` — VM/desktop shows none, not 0%) |
| Spaces (multi-display) | `partial` — Settings configures `workspaceMode` synced \| perDisplay (`proteus-workspace` bands); Super+N / strip / wheel; Super+Ctrl+N local; **multi-head dogfood still thin in single-head VM** (mode is shipped; runtime depth stays partial) |
| Control Center (notifications + quick settings) | `shipped` — notifications (grouped by app) + Focus Mode (profiles · allowlist · critical · schedules) · Privacy In-use strip · Sound (Listen/Sources/**Output**) · Display · layout-driven tiles (`ControlCenterLayout` / `controlCenterLayout`) · Appearance Dark/Light · Wi‑Fi SSID list · BT devices · Power/Awake/LocalSend/posture · Screenshot Region/Screen · Edit tiles › Settings · multi-monitor host via `controlCenterMonitor`; soft Focus ≠ posture |
| Status HUD (volume · brightness) | `shipped` — top-right elevated glass chip (`Hud` / `StatusHud`, toast plate language); XF86 + IPC; suppressed while Control Center open; brightness honest-skip without `/sys/class/backlight` |
| **Beacon** — system search (`Super+Space` / `Super+D`; `Beacon.qml`, internal ids stay `launcher*`) | `shipped` — **universal Apps surface**: apps + Settings + Actions + calc + running **Windows** (focus) + Privacy **In use** / per-app grant search; empty Apps = Recents + Pinned + Windows; Files via **beacon-file-index** (fd/walk cache); file rows show default app; Clipboard paste via **wtype**; Actions: calendar/weather/screenshot; privacy-blocked Enter → Privacy leaf; `chrome beacon` / `beaconState` IPC |
| Dock (pins, magnify, running dots) | `shipped` — continuous frosted glass shelf (`glassAlpha` frost floor + curve-following edge glow **looping the full plate** — plate lifts 1px so the bottom band isn't clipped at the surface edge; no straight specular); smooth magnify; running disc vs active accent pill; hairline divider pins ‖ transients; launch bounce until first window; **window management**: click minimizes the focused app (parks on `special:minimized`; click restores — multi-window focused apps cycle instead), **hover-dwell preview popup** (glass plate, live `ScreencopyView` thumbnail per window · click focuses/restores · ✕ closes · "Hidden" badge on parked; popup band is a **fixed surface reserve + input mask** — resizing the layer on hover made Hyprland clip the dock bottom, and the mask keeps the transparent band click-through); **Settings pin** title-matches `Proteus Settings` (not shared `quickshell` class) — click toggles minimize/restore, never spawns a second instance; Beacon + desktop entry also route through `openSettings` single-instance; long-press edit (−/+ · Done); press-drag reorder / drag-off remove (`beginDrag` uses `cellLefts` so the separator doesn't skew the ghost); glass Keep/Remove/Quit (`ChromeMenuPlate`) |
| Session start (`proteus-session`) | `shipped` — prefers `start-hyprland` (known paths; fail-closed to Hyprland); hypr seed `exec-once` = qs/bg/cliphist/polkit agent (install strips terminal autostart); Settings tiles like any app window (legacy float+center rule removed; config.sh migrates old installs); `hide-system-apps` via apps + post-install (Settings-covered tools + Quickshell; Calculator stays); host `session-smoke` + `install-smoke` |
| Desktop widgets (free place; Customize) | `shipped` — long-press (empty desktop or a widget) or `Super+Shift+W` (probe: `chrome customizeDesktop` IPC); free-place + optional Snap to Grid (16px edge lattice · no overlap); **tight packing** (frame width/height tables match the drawn cards — no invisible slack; `overlapGap: 0`; collision resolve caches neighbors, prefers flush seats + min-penetration separate, capped spiral — avoids free-drag freezes); **alignment guides** while dragging free or snap (accent hairlines magnetize edges/centers to neighbors + surface center, 10px threshold; snap mode keeps magnetized axes off the lattice so stacks stay flush; dropped if collision resolution moves the frame); **arrow keys nudge the selected widget** (8px · Shift 40px · one pitch when snapping; Customize grabs the keyboard so Esc/arrows land); **widgets are click-interactive outside Customize** (clock/calendar → calendar popover · weather → popover or Settings → Date, time & weather when no location · system → Mission Center/Software · battery → Settings → Power · note → edit in place · world clock → city picker) — the old per-widget hold timer armed on an unaccepted press and fired customize after normal clicks (phantom Customize); long-press now lives on the surface (with press hit-test select) + interactive areas' own `onPressAndHold`; **Add Widget gallery renders live scaled previews** (real widget instances, non-interactive; catalog glyph while loading); catalog via `Widgets.qml` — clock · media · battery · weather · **calendar** (today tile at S, month grid + today disc at M/L, midnight rollover) · **system glance** (CPU/mem bars + uptime via `SystemLoad` retain/release refcount; storage at L) · **note** (sticky — click to write in place, debounced save to `noteText`, widget layer raises + grabs keyboard while editing via `ShellState.desktopNoteEditing`; read-only on lock) · **world clock** (first multi-instance type, `unique: false` — one per city; `TZ=<zone> date` owns the tz math; in-widget city picker persists `tzId`/`tzLabel`); separate from lock; **not** in Settings; widget store Out |
| Lock screen (`Super+L`, PAM + `WlSessionLock`) | `shipped` — Customize mode, zone layout, applets; cold boot auto-lock **with no desktop peek** (bar/dock/widgets **and** Beacon/CC/calendar/toasts/HUD gate on `sessionStartLockPending`; overlay toggles blocked while pending; held until first unlock — only the wallpaper maps beneath the lock); wake-up keystroke is kept for password mode (PIN digits already were); attempt cooldown after 3 misses; optional **unlock PIN** (numpad + keyboard digits, auto-submit; password still works) — PIN pad vertically centered above applets, strip widgets hide while PIN is up, layout reserve keeps tiles out of the auth band; via `check-unlock.py` + hashed `~/.local/share/proteus/auth/pin`; **console** reuses the same `LockSurface` / PAM+PIN path (`ConsoleShell` hosts `WlSessionLock`) |
| Global shortcuts (Beacon, settings, lock) | `shipped` |
| Hardware probe at session start (`Hardware.qml`) | `shipped` — Wave A |
| Env gate (Beacon / Settings / dock) | `shipped` — `EnvGate.qml` (+ `env/apps` manifests); app icon resolve + Proteus brand marks |
| Chrome design lock (`CHROME.md`) | `shipped` — principles + token tables + Settings patterns; sibling export `env/chrome/` `shipped` |
| Theme tokens | `shipped` — space/radius scale + accent/font from Config; company lock [CHROME.md](./CHROME.md) |
| Themed controls (`ThemeSlider` / `ThemeSwitch`) | `shipped` — shared accent Slider/Switch wrappers (`shell/shared/`) used by all Settings panes, Control Center Sound plate, and lock clock HUD; stock Controls variants smoke-banned (`chrome-tokens-smoke`) |
| Shared package layout (flat + helpers) | `shipped` — Config/Background ownership split; Settings `kit/`; guest dogfood OK |
| Smoke suite (`scripts/smoke/*-smoke.sh`) | `shipped` — layout · widget-layout-resolve · ipc-contract · config-schema · config-roundtrip · app-manifest · chrome-tokens · software-reliability · power-logind · accounts · lock-pin · permissions · desktop · beacon · audio-mix-serve · hw-probe · install · session · posture-hard · console · qs-version; optional `qs-guest` (incl. Customize + widgets IPC + Desktop nav) + `software-guest` via `smoke-all` / `PROTEUS_GUEST=1` |

---

## 3. Settings

App: `apps/proteus-settings/` · launcher `proteus-settings` · `Super+,`

| Pane | Status |
|------|--------|
| Appearance → Accent / Background / Lock / Icons / Font (`style`) | `shipped` — hub + five `Style*Leaf` StickyPaneLoaders; Kind/color chrome via `kit/` (`SettingsKindPicker`, `SettingsColorPresetGroup`, `ColorGraphPicker` debounced); Dark/Light; empty-album honesty; preview above Kind; lock wallpaper/dim in Settings (widgets via lock Customize); daily/slideshow/`proteus-bg`; **bg runtime hardened** (installed wrapper is a crash-respawn loop — clean exit/TERM/KILL stop it; shell watchdog re-spawns a dead runner ~15s, only after seeing it alive; `applyBackground` detection matches legacy `exec -a` cmdline **and excludes its own pgrep self-match** — both bugs stacked/blocked wallpaper instances until reboot); Font picker + userFonts Add/Remove; Icons squircle compare + Tint; hypr live apply coalesced; mega-page merge Out |
| Desktop → Gaps / Borders / Motion / Dock & menu bar / Spaces / Default apps / Focus / Control Center / Beacon | `shipped` — Appearance-style hub + `Desktop*Leaf` StickyPaneLoaders; Gaps/Borders/Motion `SettingsFormRow` + live hints; Dock disable honesty + Advanced conf escape; Spaces `workspaceMode`; **Default apps** (`proteus-defaults.py` + xdg-mime / mimeapps.list); Beacon blurb (universal search; Tab / Ctrl+1–4 modes), Clear recent apps + recent files, tag FormRows; live hypr + `proteus-general.conf` / `settings.json` |
| Displays (scale / mode / orientation, Identify; layout canvas) | `shipped` — drag layout + full-snapshot Revert; Refresh/re-entry clears Revert; post-Apply topology drift + Hyprland monitor events cancel Revert; list merge by connector name; clearer Apply/Revert status + conf escape |
| Peripherals → Keyboard (shortcuts) / Mouse (sensitivity, accel) | `shipped` |
| Software → Updates / Repos / AUR / Flathub / AppImages / Web apps / Orphans (`packages`) | `shipped` — hub + `Packages*Pane` StickyPaneLoaders; Install\|Installed mode-safe loads + leafUi; sticky action bar; live `$` op + Cancel + last error; empty Installed / orphans / AppImages honesty; **Web apps** (`proteus-webapp` → user `.desktop`, no polkit); hub Needs yay/paru · flatpak; AppImages user-only; escape **Install…** → seeded Software leaf; `software-reliability-smoke` + `software-guest-smoke` in `smoke-all` (yay **or** paru); dep graphs / Snap Out |
| Sound → Output / Input / Applications / Mixer / Latency (`sound`) | `shipped` — Desktop-style hub + `Sound*Leaf` StickyPaneLoaders; **Mixer** Wave Link–style grid (channels/inputs × mixes; Speakers/mix listen; rename; peaks; drag-reorder with full-row/column drop lines + wider gutters); instant expand/listen (dbl-click rename); slideVol + dump-pause while dragging levels; honest setup CTA; × confirm; graph editor escape (`qpwgraph` Install… → Repos); refcounted `mixBusy`; folder/picker wheel capture; resident `proteus-audio-mix serve` (Python mutations + fallback); Output/Input/Apps/Latency FormRows; pactl + `pw-metadata` |
| Network → This machine / Devices / Diagnostics / Wi‑Fi / Bluetooth / LocalSend / Tailscale / VPN (`network`) | `shipped` — hub + leaves; password Wi‑Fi; BT pair; Devices IPv4; **Diagnostics** (iface bars · `ss` · firewall · route/DNS · ping · Wireshark); LocalSend; Tailscale peers/exit/login-server; VPN up/down + WG import; Headscale admin / OpenVPN wizard Out |
| Power (PPD mode + battery + idle/lid) | `shipped` — Performance/Balanced/Eco via `powerprofilesctl`; battery via UPower; `pkexec proteus-logind` drop-in + reload (not restart); CC Power tile; charge thresholds / TLP Out |
| Date, time & weather (clock, timezone search, NTP, locale, **Location**) | `shipped` — timezone/NTP/`localectl set-locale` polkit-gated; searchable locale picker + locale.conf escape; Location explicit place search (never IP); Open-Meteo current + **5-day forecast** + Conditions H/L/sunrise; Match time zone to place when TZ differs; desktop/lock weather widget; manual time / RTC writers Out |
| Users (session actions + read-only local users · greetd status) | `shipped` — Session Lock/Logout; Reboot/Shutdown confirm strip; **lock screen PIN** set/change/clear (`proteus-pin.py`, PAM password gate; hash not in settings.json); current user GECOS/home/UID/groups; other users read-only; Online accounts jump; greetd status + conf escape; no add/remove; Settings does not write greeter prefs |
| Online accounts (provider seats) | `partial` — locked connector catalog (Google connectable; Microsoft/Nextcloud/Apple/Exchange/IMAP/CalDAV/CardDAV listed); `proteus-accounts` + vault tokens (not settings.json); Google PKCE when client id set; mail/contacts/Drive apps Out |
| Privacy & security (transparency · mute · session · grants) | `partial` — hub + leaves; what leaves; weather mute; DND / Lock / clipboard / LocalSend; **In use now** (mic/camera/screen apps via `privacy-indicators.py`); category Allow/Deny + per-app Allow/Ask/Deny in `permissions.json` (`proteus-permissions.py` · `Permissions.qml`); Flatpak mic/camera overrides; EnvGate honors manifest `permissions` (ask=deny until Allow) — **fail-open until `Permissions.ready`** (mirror Hardware.ready; brief startup window); Beacon + dock grant parity; **Diagnostics deny** gates Network Diagnostics polling; smoke/install harness gates privacy helpers; **native pacman apps observed not sandboxed**; portal store write Out |
| About (hardware class / capabilities) | `shipped` — OS/kernel/hostname (`SystemInfo`); Hyprland/Quickshell versions; tip hash; hw-probe class/caps; CPU/mem/swap/storage/uptime (`SystemLoad`, About-active only); battery when present (`Power`/UPower); Mission Center escape; Check for updates → Software; soft Hyprland profile; Copy + Copied; session under Users only; hard posture Out; no in-Settings live dashboard |
| Host / VM·container setup | **out of Settings** — separate app later |
| Cold-start (open feel) | `shipped` — async `shell.qml` → `Settings.qml`; `kit/StickyPaneLoader` (active category first, sticky after visit); Keyboard/Keybinds deferred; Settings QS skips live hw-probe (`Hardware.isSettingsApp` → cache only) |
| Window & layout | `shipped` — normal app window (tiles / floats like any other; legacy float+center windowrule removed, config.sh strips it from old installs); wide/tiled windows cap + center the pane column (`paneMaxW` 760; back/title track it, ✕ stays at the corner; Mixer full-bleed); **single-instance** (`proteus-settings` reuses via `nav` IPC + `raise` / hypr focus; `quickshell -n` race guard) |
| Dual-path chrome (GUI + keyboard) | `shipped` — mouse-legible Settings IA; `Super+,`; Beacon Settings search; Actions (Wi‑Fi / Displays / Mixer / Privacy / Focus / Updates + session); `Super+Shift+F` Focus cycle; Settings `/` typeahead jump; hub lists ↑↓ Enter |

Modular panes: `apps/proteus-settings/panes/*` · form kit: `kit/*` (shell stays in `Settings.qml`).
Shared spine: flat `shell/shared/` + named helpers — [FACTS.md](./FACTS.md).
North-star IA: [SETTINGS-IA.md](./SETTINGS-IA.md).

---

## 4. Postures

Locked product set: [POSTURES.md](./POSTURES.md).

| Posture | Status |
|---------|--------|
| desktop | `partial` — primary focus spine |
| console | `partial` — layered ConsoleShell + hard `proteus-posture` (posture flip skips cold-boot re-lock + workspace hygiene); **tvOS-style shelf Home** — pinned cinematic Featured (tracks focused card), one active shelf (others peek/dim), curated lean-back Apps (not desktop dump) + Web/Games/Media + Jump Back In; **Library** = full DesktopEntries catalog; Search = Shortcuts + typed catalog; cards/hero without category chips (shelf titles); **Phase 1 seat:** `proteus-console-seat` + `proteus-console-capabilities` (supervised map→fullscreen, Gamescope only when Vulkan usable / skip in QEMU); Theme accent/icons; Media lean sheet + Details; Jump ✕ remove; CC/HUD/toasts; pad Menu/Open/Details; Guide long-hold → exit; cold-boot lock; `apply-console-kit.sh`; **Phase 2** Gamescope *session* later |
| host | `planned` — hard switch (lean/ops; UI on demand); hypr stub `host.conf` |
| home · wearable · xr · vehicle | `parked` — thesis only; not in proof order |

Focus set + hard switches: [POSTURES.md](./POSTURES.md). Hard console flip:
`proteus-posture console|desktop` (Fact `~/.config/proteus/posture` + chrome +
profile; sets `PROTEUS_SKIP_SESSION_LOCK=1` so mid-session flips do not blank
the console). Enter from desktop: Beacon Action · Control Center tile ·
`Super+Shift+C` (CC prefers live `$PROTEUS_ROOT/vm/guest/proteus-posture`).
Soft hypr helper `set-hypr-profile.sh` + Settings → About picker remain
soft-only (window-rule component, not the product flip).

Console dogfood (guest): `sudo bash /mnt/proteus/vm/guest/apply-console-kit.sh`
then `proteus-posture console` (or `/mnt/proteus/vm/guest/proteus-posture` if
`/usr/local` is stale). Titles launch via `proteus-console-seat` →
`proteus-console-launch` (VM bare kiosk; Gamescope when Vulkan usable). Check
`chrome state.surface === console` and `proteus-console-seat.log`. Home is
tvOS-inspired shelves + full-bleed Featured; Library/Search are destinations
from the slim top chrome.

---

## 5. Config facts

| Path | Role |
|------|------|
| `~/.config/proteus/settings.json` | Theme/desktop prefs (Config.qml FileView); wallpaper keys; `lockWidgets[]`, `desktopWidgets[]`, `notificationsDnd` — behaviour in Background / Widgets / Audio / … |
| `~/.config/proteus/keybinds.json` | Shortcut overrides |
| `~/.config/proteus/permissions.json` | App permission categories + per-app Allow/Ask/Deny (0600; `proteus-permissions.py` / `Permissions.qml`) — not in settings.json; [CONFIG-SCHEMA.md](./CONFIG-SCHEMA.md) |
| `~/.local/share/proteus/auth/pin` | Lock-screen unlock PIN hash (0600; `proteus-pin.py` / `check-unlock.py` / `proteus_auth.py`) — not in settings.json; apps install helpers + optional `proteus-lock` PAM (`login` fallback); [CONFIG-SCHEMA.md](./CONFIG-SCHEMA.md) · [INSTALL.md](./INSTALL.md) |
| `~/.config/proteus/hw-probe.json` | Cached Wave A hardware probe |
| `~/.config/hypr/proteus-keybinds.conf` | Generated Hyprland binds (sourced) |
| `~/.config/hypr/proteus-general.conf` | Gaps, borders, rounding, animations (sourced) |
| `~/.config/hypr/proteus-monitors.conf` | Displays live `monitor =` lines (sourced) |
| `~/.config/hypr/proteus-profile.conf` | Active posture profile pointer → `profiles/*.conf` |
| `~/.config/proteus/posture` | Hard-switch Fact (`desktop` \| `console`) — boot + `proteus-qs` when `PROTEUS_SURFACE` unset |
| `~/.config/hypr/profiles/*.conf` | Posture fragments (desktop + console fullscreen rules shipped; host / home stubs) |
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
| `./vm/provision.sh` | Prepare ISO/disk hints + SSH overlay (`bootstrap.sh`); `status` = read-only checklist (ISO/disk/SSH/last overlay; running-VM-safe `qemu-img -U`) |
| `./vm/bootstrap.sh` | SSH guest → light overlay (`vm/install/bootstrap.sh`; passes REPAIR/UPDATE knobs) |
| `bash /mnt/proteus/vm/install/bootstrap.sh` | On guest: staged overlay incl. `console` stage (multilib + Steam/RetroArch/cores/pads); `repair` = fast config→apps→console preset; `PROTEUS_INSTALL_UPDATE=1` = -Syu + list refresh; skip/resume/only knobs |
| `./vm/install/check.sh` | Host tree/`bash -n` gate for overlay stages + roster split + repair/status wiring + INSTALL.md |
| `bash /mnt/proteus/vm/guest/install-settings-app.sh` | Install Settings + keybinds + desktop/displays conf |
| `bash /mnt/proteus/vm/guest/install-keybinds.sh` | Keybinds file + hypr source (user home) |
| `bash /mnt/proteus/vm/guest/install-desktop-conf.sh` | `proteus-general.conf` + `proteus-monitors.conf` + sources |
| `bash /mnt/proteus/vm/guest/install-lock-pam.sh` | `/etc/pam.d/proteus-lock` (falls back to `login` if absent) |
| `./scripts/run-nested.sh` | Nested Hyprland on host |
| `./scripts/smoke-all.sh` | Host smokes (layout · widget-layout-resolve · ipc-contract · config-schema · config-roundtrip · app-manifest · chrome-tokens · software-reliability · power-logind · accounts · lock-pin · permissions · desktop · beacon · audio-mix-serve · hw-probe · install · session · posture-hard · console · qs-version); guest `qs-guest` + `software-guest` if SSH or `PROTEUS_GUEST=1` |
| `./scripts/smoke/layout-smoke.sh` | Flat `shell/shared/` + Settings `kit/` structure |
| `./scripts/smoke/widget-layout-resolve-smoke.sh` | Widget free/snap resolve capped + flush/no-overlap geometry stress |
| `./scripts/smoke/ipc-contract-smoke.sh` | Smoke `qs ipc call` sites ⊆ shell/Settings `IpcHandler` methods |
| `./scripts/smoke/config-roundtrip-smoke.sh` | Mutate `settings.minimal.json` prefs; still ⊆ Config keys + JSON round-trip |
| `./scripts/smoke/config-schema-smoke.sh` | Config FileView keys ↔ `tests/fixtures/settings.minimal.json` |
| `./scripts/smoke/app-manifest-smoke.sh` | `env/apps` schema + catalog gate |
| `./scripts/smoke/chrome-tokens-smoke.sh` | `env/chrome` tokens JSON/CSS + ThemeSlider/ThemeSwitch stock-ban |
| `./scripts/smoke/software-reliability-smoke.sh` | Host static checks — all six Software leaves + hub helper honesty + op narrative / leafUi |
| `./scripts/smoke/power-logind-smoke.sh` | Host static checks for `proteus-logind` + Power.qml wiring |
| `./scripts/smoke/accounts-smoke.sh` | Host static checks for `proteus-accounts` + Online accounts wiring |
| `./scripts/smoke/lock-pin-smoke.sh` | Host static checks for unlock PIN hash store + `check-unlock.py` / `proteus-pin.py` / `proteus_auth.py` + apps.sh install + `shell/pam/proteus-lock` source (no live PAM auth) |
| `./scripts/smoke/permissions-smoke.sh` | Host static checks for `permissions.json` store + Privacy leaves + EnvGate grant gate |
| `./scripts/smoke/desktop-smoke.sh` | Host static checks for Desktop leaves + `proteus-defaults.py` / `beacon-file-index.py` + CC Edit › wiring |
| `./scripts/smoke/beacon-smoke.sh` | Host checks for Beacon Files index rebuild/search/status + UniversalSearch / defaultAppSubtitle / wtype wiring |
| `./scripts/smoke/audio-mix-serve-smoke.sh` | Host checks for `proteus-audio-mix` dump/serve + Audio.qml wiring |
| `./scripts/smoke/hw-probe-smoke.sh` | Wave A probe JSON (device_class + capabilities) |
| `./scripts/smoke/install-smoke.sh` | Overlay installer tree check (stages incl. console · package roster split · repair preset · provision status · INSTALL.md) |
| `./scripts/smoke/session-smoke.sh` | Host gate for `proteus-session` contract + `proteus.desktop` |
| `./scripts/smoke/posture-hard-smoke.sh` | Host static checks for hard `proteus-posture` + console profile rename (no live compositor flip) |
| `./scripts/smoke/console-smoke.sh` | Host Phase 1 gate — ConsoleShelf/Lean · seat/caps JSON · apps/console install wiring (no live posture flip) |
| `./scripts/smoke/qs-version-smoke.sh` | Record QS version policy (no IgnorePkg); checks `qs-guest-smoke` upgrade path |
| `./scripts/smoke/qs-guest-smoke.sh` | Guest cold-start `SHELL_OK` / `SETTINGS_OK` + record `quickshell` version + polkit agent + nav deep link + Beacon + calendar + Customize/widgets IPC (add/move/snap/remove worldclock probe) |
| `./scripts/smoke/software-guest-smoke.sh` | Guest Software dogfood (browse/inventory + Flatpak install/remove; yay\|paru; pacman mutator if passwordless sudo); in `smoke-all` (SKIP unless SSH / `PROTEUS_GUEST=1`) |

SSH default: `ssh -p 2222 andrew@127.0.0.1`
Install path SoT (three layers, knobs, repair, failures): [INSTALL.md](./INSTALL.md)

---

## 7. Docs locks (ahead of code)

| Lock | Doc | Code status |
|------|-----|-------------|
| Stack split (QML / Tauri / Rust) | [STACK.md](./STACK.md) | Settings+shell = QML; no Tauri apps yet |
| Hyprland as backend + QS limits | [COMPOSITOR.md](./COMPOSITOR.md) | Desktop Hyprland `shipped`; console hard switch `partial` (ConsoleShell + proteus-posture skip re-lock + console.conf); host `planned`; home parked |
| Adaptive apps / environment contract | [APPLICATIONS.md](./APPLICATIONS.md) | `partial` — `env/apps` manifests + EnvGate prefer; postures unused |
| Hardware module catalog | [HARDWARE.md](./HARDWARE.md) | Wave A probe + `Hardware.qml` session load |
| Capability / posture resolver | [POSTURES.md](./POSTURES.md) | Probe → caps in shell; posture still stub |
| Chrome language (company reference) | [CHROME.md](./CHROME.md) | `Theme.qml` + Settings `kit/` + `env/chrome/` export `shipped`; Rowena retarget `partial` |
| Facts / Config schema | [FACTS.md](./FACTS.md) · [CONFIG-SCHEMA.md](./CONFIG-SCHEMA.md) | Layout + docs `shipped` |

---

## 8. Not yet

- Remaining focus hard switch (**host**) — lean ops session; console Gamescope *session* hardening
- Soft hypr profile reload sold as posture (use `proteus-posture` for console)
- Parked postures (home / wearable / xr / vehicle) before focus three are proven  
- Snap / dependency graphs in Software  
- pacman IgnorePkg / ISO QS version pin (record + smoke only today)  
- Host posture chrome or workload panes  
- First-party Tauri app under `apps/`  
- More Rust helper CLIs under `services/` (Wave A probe is Python; `proteus-pkg` + `proteus-logind` mutators + `proteus-audio-mix` resident dump/peaks shipped; mixer mutations still Python)  
- Posture / prefers / device_classes enforcement on manifests (schema only today)  
- ISO / installer productization (dogfood overlay in `vm/install/` is enough for now; path documented in [INSTALL.md](./INSTALL.md))  
- Settings UI for posture **hard-switch** picker (soft Hyprland profile picker shipped in About)  
- Rowena (and other sibling) CSS retarget onto `--proteus-*` export  

When shipping a feature, update this file in the same change.
