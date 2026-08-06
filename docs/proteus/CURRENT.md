---
doc: current
role: status
audience: contributors, coding agents
last_updated: "2026-08-05"
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
  - ../../dev/vm/README.md
status_legend:
  shipped: Works in dogfood path
  partial: Present; gaps remain
  planned: Specced; not built
  stub: Placeholder only
---

# Proteus — current status

Desktop spine is dogfoodable (shell + Settings largely shipped). Console and
host hard switches are `partial` (layered shells + `proteus-posture`); parked
postures are thesis only. Docs describe the thesis ahead of code where marked
`planned`.

## Document map

| Section | Contents |
|---------|----------|
| [1. Platform](#1-platform) | Arch guest, Hyprland, Quickshell |
| [2. Shell](#2-shell) | Desktop chrome |
| ↳ [2a. Top bar detail](#2a-top-bar-detail) · [2b. Desktop widgets detail](#2b-desktop-widgets-detail) | Expanded from the table |
| [3. Settings](#3-settings) | Control center |
| ↳ [3a. Online accounts detail](#3a-online-accounts-detail) | Expanded from the table |
| [4. Postures](#4-postures) | Loader status |
| ↳ [4a. Console detail](#4a-console-detail) | Expanded from the table |
| [5. Config facts](#5-config-facts) | On-disk paths |
| [6. Harness](#6-harness) | VM / nested |
| [7. Docs locks (ahead of code)](#7-docs-locks-ahead-of-code) | Stack / compositor / chrome |
| [8. Not yet](#8-not-yet) | Explicit gaps |

---

## 1. Platform

| Piece | Status | Notes |
|-------|--------|-------|
| Arch Linux guest | `shipped` | QEMU/KVM via `dev/vm/run.sh` |
| Bare-metal install path | `partial` — overlay is path-agnostic (root Fact + `readlink`-resolved helpers + `PROTEUS_INSTALL_COPY_HELPERS` escape); base Arch is still a manual install, and **no bare-metal dogfood run has happened yet** — untested against real GPU/battery/backlight ([INSTALL.md](./INSTALL.md)) |
| Hyprland session | `shipped` | Backend for desktop posture; greetd / proteus-session |
| Quickshell shell | `retired` | QML chrome deleted 2026-08-06; do not reintroduce |
| Nested Hyprland (host) | `shipped` | `dev/run-nested.sh` — `proteus-chrome` → `proteus-shell` |
| Owned-engine dogfood gate | `shipped` — Wave 4 closed; **2026-08-06 tree flip:** `shell/` is sole chrome crate (was `shell-next`); Quickshell + Settings QML deleted; face scaffold `shell/src/faces/`; see OWNED-STACK |
| Hyprland posture profiles | `partial` — desktop + console / host / home stub + `proteus-posture` — [POSTURES.md](./POSTURES.md) · [COMPOSITOR.md](./COMPOSITOR.md) |
| QS version pin / respawn policy | `retired` | `proteus-qs` + user unit deleted with QML chrome |

---

## 2. Shell

Desktop (owned iced — `shell/src/surfaces.rs` + `shell/src/faces/desktop.rs`):

| Feature | Status |
|---------|--------|
| Top bar (workspaces, title, clock+weather center, CC icon) | `shipped` — wallpaper-first glass menu bar. **Left:** traffic-light window controls · app name · Spaces strip. **Center:** date · time · weather → calendar / weather popovers. **Right:** tray · privacy dots · system services · tiling toggle · status cluster · Control Center. Detail: [§2a](#2a-top-bar-detail) |
| Spaces (multi-display) | `partial` — Settings configures `workspaceMode` synced \| perDisplay (`proteus-workspace` bands); Super+**1–10** (Super+0 = Space 10) logical SoT / Super+Ctrl local / Super+Shift move / strip / wheel; **Named Spaces** (`workspaceNames`); **strip drag reorder** (`workspaceOrder` visual perm); **Scratchpad** Super+S / Super+Alt+S (`special:scratch` ≠ dock `special:minimized`); **custom specials** (`specialWorkspaces` CRUD · strip pills up to 8 · Super+Alt+1–8 / Super+Alt+Shift+1–8 index fallback · **optional per-special toggle chords** via `specialWorkspaceChords` → `special-toggle <slug>` · **optional per-special move chords** via `specialWorkspaceMoveChords` → `special-move <slug>`); **multi-head:** `status` / `ensure` + SpacesDisplays; **disconnect:** `migrate-disconnect` orphan bands → primary; spaces-smoke; **strip Scratchpad ◇ pill** |
| Control Center (notifications + quick settings) | `shipped` — notifications (grouped by app) + Focus Mode (profiles · allowlist · critical · schedules) · Privacy In-use strip · Sound (Listen/Sources/**Output**) · Display · layout-driven tiles (`ControlCenterLayout` / `controlCenterLayout` — order/visibility/span/size/**columns 2|3**) · Appearance Dark/Light · Wi‑Fi SSID list · BT devices · Power/Awake/LocalSend/posture · Screenshot Region/Screen · Edit tiles › Settings · multi-monitor host via `controlCenterMonitor`; soft Focus ≠ posture |
| Status HUD (volume · brightness) | `shipped` — top-right elevated glass chip (`Hud` / `StatusHud`, toast plate language); XF86 + IPC; suppressed while Control Center open; brightness honest-skip without `/sys/class/backlight` |
| **Beacon** — system search (`Super+Space` / `Super+D`; `Beacon.qml`, internal ids stay `launcher*`) | `shipped` — **universal Apps surface**: apps + Settings + Actions + calc + running **Windows** (focus) + Privacy **In use** / per-app grant search; empty Apps = Recents + Pinned + Windows; Files via **beacon-file-index** (fd/walk cache); file rows show default app; Clipboard paste via **wtype**; Actions: calendar/weather/screenshot; privacy-blocked Enter → Privacy leaf; `chrome beacon` / `beaconState` IPC |
| Dock (pins, magnify, running dots) | `shipped` — continuous frosted glass shelf (`glassAlpha` frost floor + curve-following edge glow **looping the full plate** — plate lifts 1px so the bottom band isn't clipped at the surface edge; no straight specular); smooth magnify; running disc vs active accent pill; hairline divider pins ‖ transients; launch bounce until first window; **window management**: click minimizes the focused app (parks on `special:minimized`; click restores — multi-window focused apps cycle instead), **hover-dwell preview popup** (glass plate, live `ScreencopyView` thumbnail per window · click focuses/restores · ✕ closes · "Hidden" badge on parked; popup band is a **fixed surface reserve + input mask** — resizing the layer on hover made Hyprland clip the dock bottom, and the mask keeps the transparent band click-through); **Settings pin** title-matches `Proteus Settings` (not shared `quickshell` class) — click toggles minimize/restore, never spawns a second instance; Beacon + desktop entry also route through `openSettings` single-instance; long-press edit (−/+ · Done); press-drag reorder / drag-off remove (`beginDrag` uses `cellLefts` so the separator doesn't skew the ghost); glass Keep/Remove/Quit (`ChromeMenuPlate`) |
| Session start (`proteus-session`) | `shipped` — prefers `start-hyprland` (known paths; fail-closed to Hyprland); hypr seed `exec-once` = **proteus-chrome** / bg / cliphist / polkit agent (Wave 4 owned default; Quickshell via `shell-engine` fact); Settings tiles like any app window (legacy float+center rule removed; config.sh migrates old installs); `hide-system-apps` via apps + post-install; host `session-smoke` + `install-smoke` |
| Desktop widgets (free place; Customize) | `shipped` — long-press or `Super+Shift+W`; free-place + optional Snap to Grid, alignment guides, arrow-key nudge; widgets stay click-interactive outside Customize; Add Widget gallery renders live previews. Catalog: clock · media · battery · weather · calendar · system glance · note · world clock. Separate from lock; **not** in Settings; widget store Out. Detail: [§2b](#2b-desktop-widgets-detail) |
| Lock screen (`Super+L`, PAM + `WlSessionLock`) | `shipped` — Customize mode, zone layout, applets; cold boot auto-lock **with no desktop peek** (bar/dock/widgets **and** Beacon/CC/calendar/toasts/HUD gate on `sessionStartLockPending`; overlay toggles blocked while pending; held until first unlock — only the wallpaper maps beneath the lock); wake-up keystroke is kept for password mode (PIN digits already were); attempt cooldown after 3 misses; optional **unlock PIN** (numpad + keyboard digits, auto-submit; password still works) — PIN pad vertically centered above applets, strip widgets hide while PIN is up, layout reserve keeps tiles out of the auth band; via `check-unlock.py` + hashed `~/.local/share/proteus/auth/pin`; **console** reuses the same `LockSurface` / PAM+PIN path (`ConsoleShell` hosts `WlSessionLock`) |
| Global shortcuts (Beacon, settings, lock) | `shipped` |
| Hardware probe at session start (`Hardware.qml`) | `shipped` — Wave A |
| Env gate (Beacon / Settings / dock) | `shipped` — `EnvGate.qml` (+ `env/apps` manifests); **postures** + **device_classes** hard allow-lists · **prefers** soft hint/boost · **adapts** soft profile (input/nav/panes via FocusMode) + **`PROTEUS_ADAPT_*` launch env** on Dock/Beacon/`openSettings`; **Focus minimal hard-hides** non-allowlisted Settings panes; **`adapts.input` remote** via probe CEC/IR/lirc / Bluetooth HID + `PROTEUS_REMOTE_PROBE` stub; **Settings About** reads via `AdaptEnv.qml` + remote status + Focus density; app icon resolve + Proteus brand marks |
| Chrome design lock (`CHROME.md`) | `shipped` — principles + token tables + Settings patterns; sibling export `env/chrome/` `shipped` |
| Owned-stack ladder ([OWNED-STACK.md](./OWNED-STACK.md)) | `partial` — Wave 4 owned chrome **transition closed** (guest dogfood 2026-08-05); Settings iced default; polish holdouts remain; compositor rung 2 parked; **gamescope console-home not swapped** |
| Theme tokens | `shipped` — space/radius scale + accent/font from Config; company lock [CHROME.md](./CHROME.md) |
| Themed controls (`theme_slider` / `theme_switch`) | `shipped` — `proteus-ui` kit; QML ThemeSlider/ThemeSwitch retired |
| Shared package layout | `shipped` — `shell/{src,scripts,pam,assets}` + `shell/src/faces/`; QML `shared/` deleted |
| Smoke suite (`dev/smoke/*-smoke.sh`) | `shipped` — layout/shell/shell-core/settings-next/owned-guest primary; former QML leaf smokes are SKIP stubs |


### 2a. Top bar detail

Glass menu bar, wallpaper-first (`menuBarAlpha` clearer than the dock; soft text
outline when thin, including DND/Awake chips).

**Left**
- **Traffic-light window controls** for the focused toplevel — Hyprland draws no
  decorations, so the bar owns ✕ close · − minimize to `special:minimized` ·
  + maximize (`fullscreen 1`). Symbols on hover; hidden with no focused window.
- App name via desktop-entry lookup (`ActiveWindow.barText`).
- **Dynamic workspace strip** — logical Spaces 1–10 via `proteus-workspace`;
  per-monitor ID bands; default **synced** multi-display switch (Settings →
  Desktop → Spaces for per-display); `Super+Ctrl+N` always targets this display;
  pills min 4 / cap 10; occupied dots = has toplevels on the logical slot; wheel
  cycles; "+" jumps to next.

**Center** — date · time · weather cluster
- Date dim + time demi; weather glyph/temp; accent soft while the calendar is open.
- Date drops, then the cluster fades, when left/right chrome crowds the mid band.
- `…` / `—` while loading or on error when a location is set.
- Date/time opens the **calendar popover**; the weather chip opens the **weather
  glance** (`WeatherPanel` · Open-Meteo conditions/forecast; **Open Weather** →
  `gnome-weather`). CalendarPanel's weather row jumps to the glance.
- IPC: `chrome calendar` · `chrome weather`.

**Right**
- **App tray** (StatusNotifier — 1Password etc.).
- **Privacy dots** — mic orange · camera green · screen purple; click → Privacy.
- **System services** — network · Bluetooth · volume scroll · battery.
- **Tiling toggle** (COSMIC-adjacent) — grid glyph = tiled, accent overlapping
  panes = floating; click `togglefloating` on the focused window. Floating windows
  resize by grabbing any edge/corner (hypr `resize_on_border` + 12px grab area)
  and move with **⌘+drag anywhere on the window** (`bindm` mouse binds emitted
  with the generated keybinds; ⌘+right-drag resizes). The **accent focus ring**
  follows hover/keyboard focus: `col.active_border` accent, inactive fully
  transparent.
- Status cluster — unread badge · DND · Awake · battery.
- **Control Center glyph** — three mini sliders with staggered knobs (ThemeSlider
  language); knobs slide + accent while open.

**Notes**
- Beacon button is off the bar — the dock pin and `Super+Space` own it.
- Battery % shows only with a real battery (`Power.hasBattery`) — a VM/desktop
  shows none rather than 0%.

### 2b. Desktop widgets detail

Enter Customize by long-press (empty desktop or a widget) or `Super+Shift+W`
(probe: `chrome customizeDesktop` IPC).

**Placement**
- Free-place, plus optional Snap to Grid (16px edge lattice, no overlap).
- **Tight packing** — frame width/height tables match the drawn cards, so there is
  no invisible slack (`overlapGap: 0`). Collision resolve caches neighbours,
  prefers flush seats and min-penetration separation, and caps the spiral — an
  earlier version froze on free-drag.
- **Alignment guides** while dragging free or snapped — accent hairlines magnetize
  edges/centres to neighbours and the surface centre (10px threshold). Snap mode
  keeps magnetized axes off the lattice so stacks stay flush; guides are dropped
  if collision resolution moves the frame.
- **Arrow keys nudge the selection** — 8px, Shift 40px, one pitch when snapping.
  Customize grabs the keyboard so Esc and arrows land.

**Interaction outside Customize** — widgets stay clickable: clock/calendar →
calendar popover · weather → popover, or Settings → Date, time & weather when no
location is set · system → Mission Center/Software · battery → Settings → Power ·
note → edit in place · world clock → city picker.

> The old per-widget hold timer armed on an unaccepted press and fired Customize
> after ordinary clicks (phantom Customize). Long-press now lives on the surface
> (with press hit-test select) plus the interactive areas' own `onPressAndHold`.

**Add Widget gallery** renders live scaled previews — real widget instances,
non-interactive, with a catalog glyph while loading.

**Catalog** (`Widgets.qml`)

| Widget | Notes |
|--------|-------|
| clock · media · battery · weather | — |
| **calendar** | today tile at S; month grid + today disc at M/L; midnight rollover |
| **system glance** | CPU/mem bars + uptime via `SystemLoad` retain/release refcount; storage at L |
| **note** | sticky — click to write in place, debounced save to `noteText`; widget layer raises and grabs the keyboard while editing (`ShellState.desktopNoteEditing`); read-only on lock |
| **world clock** | first multi-instance type (`unique: false`) — one per city; `TZ=<zone> date` owns the tz math; in-widget city picker persists `tzId`/`tzLabel` |

Separate from the lock screen; **not** surfaced in Settings; a widget store is Out.

---

## 3. Settings

App: iced sibling `../ProteusSettings` (`proteus-settings-next`) via
`/usr/local/bin/proteus-settings` · QML fallback `proteus-settings-qml` ·
`apps/proteus-settings/` · `Super+,`

**Wave 4 iced default `shipped`** — `proteus-settings` launches iced when the
binary is installed; escape to `proteus-settings-qml` for polish holdouts (Mixer
peaks/drag-reorder · Headscale structured ACL · multi-seat glance megas). Legacy
Tauri `app/` is frozen. `--page`/`--query` deep links preserved. Ported:
Appearance (accent + background/lock/icons/font thin) · Software (updates confirm ·
search · orphans · flatpak/webapps · AppImages · AUR thin) · Sound
(output/input/latency/apps · Mixer Wave Link grid thin) · Notifications · Users ·
Privacy core · Network (machine/wifi/BT · VPN · Headscale users + policy HuJSON) ·
Desktop hypr leaves · Power · Date/Time · About · Virtualization · Peripherals
(mouse/touchpad thin) · Tailscale thin · Accounts hub + password glance create/edit
+ OAuth Connect · Displays list+apply + layout canvas. Holdouts: Mixer
peaks/drag-reorder polish, Headscale structured ACL editor, Accounts multi-seat
glance megas, peripherals tablet/gamepads, Diagnostics depth.
([STACK.md](./STACK.md) §6).

| Pane | Status |
|------|--------|
| Appearance → Accent / Background / Lock / Icons / Font (`style`) | `shipped` — hub + five `Style*Leaf` StickyPaneLoaders; Kind/color chrome via `kit/` (`SettingsKindPicker`, `SettingsColorPresetGroup`, `ColorGraphPicker` debounced); Dark/Light; empty-album honesty; preview above Kind; lock wallpaper/dim in Settings (widgets via lock Customize); daily/slideshow/`proteus-bg`; **bg runtime hardened** (installed wrapper is a crash-respawn loop — clean exit/TERM/KILL stop it; shell watchdog re-spawns a dead runner ~15s, only after seeing it alive; `applyBackground` detection matches legacy `exec -a` cmdline **and excludes its own pgrep self-match** — both bugs stacked/blocked wallpaper instances until reboot); Font picker + userFonts Add/Remove; Icons squircle compare + Tint; hypr live apply coalesced; mega-page merge Out |
| Desktop → Gaps / Borders / Motion / Dock & menu bar / Spaces / Default apps / Focus / Control Center / Beacon | `shipped` — Appearance-style hub + `Desktop*Leaf` StickyPaneLoaders; Gaps/Borders/Motion `SettingsFormRow` + live hints; Dock disable honesty + Advanced conf escape; Spaces `workspaceMode`; **Default apps** (`proteus-defaults.py` + xdg-mime / mimeapps.list); **Focus** filters + **profile entity CRUD** (add/rename/delete; combo picker when >3); **Control Center** plates/tiles + **columns 2|3**; Beacon blurb (universal search; Tab / Ctrl+1–4 modes), Clear recent apps + recent files, tag FormRows; live hypr + `proteus-general.conf` / `settings.json` |
| Displays (scale / mode / orientation, Identify; layout canvas) | `shipped` — drag layout + full-snapshot Revert; Refresh/re-entry clears Revert; post-Apply topology drift + Hyprland monitor events cancel Revert; list merge by connector name; clearer Apply/Revert status + conf escape |
| Peripherals → Keyboard (shortcuts) / Mouse (sensitivity, accel) / Touchpad / Tablet / Gamepads | `shipped` — touchpad + tablet Facts → hyprctl; **per-device** `device {}` via `inputDeviceOverrides` (sensitivity + accel; Mouse leaf); tablet **active-area mm** + **pressure range** (global linear) + **eraser-as-button** (`eraser_button_mode` / `override`) + **monitor region** (`input:tablet:*` / `input:tablettool:*`); bezier per-tool curves / gesture maps Out |
| Software → Updates / Repos / AUR / Flathub / AppImages / Web apps / Orphans (`packages`) | `shipped` — hub + `Packages*Pane` StickyPaneLoaders; Install\|Installed mode-safe loads + leafUi; sticky action bar; live `$` op + Cancel + last error; empty Installed / orphans / AppImages honesty; **Web apps** (`proteus-webapp` → user `.desktop`, no polkit); hub Needs yay/paru · flatpak; AppImages user-only; escape **Install…** → seeded Software leaf; `software-reliability-smoke` + `software-guest-smoke` in `smoke-all` (yay **or** paru); dep graphs / Snap Out |
| Sound → Output / Input / Applications / Mixer / Latency (`sound`) | `shipped` — Desktop-style hub + `Sound*Leaf` StickyPaneLoaders; **Mixer** Wave Link–style grid (channels/inputs × mixes; Speakers/mix listen; rename; peaks; drag-reorder with full-row/column drop lines + wider gutters); instant expand/listen (dbl-click rename); slideVol + dump-pause while dragging levels; honest setup CTA; × confirm; graph editor escape (`qpwgraph` Install… → Repos); refcounted `mixBusy`; folder/picker wheel capture; resident `proteus-audio-mix serve` (Python mutations + fallback); Output/Input/Apps/Latency FormRows; pactl + `pw-metadata` |
| Network → This machine / Devices / Diagnostics / Wi‑Fi / Bluetooth / LocalSend / Tailscale / VPN / Headscale (`network`) | `shipped` — hub + leaves; password Wi‑Fi; BT pair; Devices IPv4; **Diagnostics** (iface bars · `ss` · firewall · route/DNS · ping · Wireshark); LocalSend; Tailscale peers/exit/login-server; VPN up/down + **WireGuard + OpenVPN import** (`.ovpn` · optional session user/pass · **cert path attach** CA/cert/key/+tls-auth via `+vpn.data` · `networkmanager-openvpn`); **Headscale admin thin** (`proteus-headscale.py` · vault API key · node list · expire/enable · **users list/create** · **policy HuJSON check/save** · browser escape); OpenVPN PKI/PKCS#11/server install · Headscale preauth · user rename/delete · structured ACL editor Out |
| Power (PPD mode + battery + idle/lid + charge limits) | `shipped` — Performance/Balanced/Eco via `powerprofilesctl`; battery via UPower; `pkexec proteus-logind` drop-in + reload (not restart); CC Power tile; **Charge limits** when sysfs `charge_control_*` present (`pkexec proteus-battery-threshold` · fail-closed otherwise); TLP Out |
| Date, time & weather (clock, timezone search, NTP, locale, **Location**) | `shipped` — timezone/NTP/`localectl set-locale` polkit-gated; searchable locale picker + locale.conf escape; Location explicit place search (never IP); Open-Meteo current + **5-day forecast** + Conditions H/L/sunrise; Match time zone to place when TZ differs; desktop/lock weather widget; manual time / RTC writers Out |
| Users (session actions + read-only local users · greetd autologin) | `shipped` — Session Lock/Logout; Reboot/Shutdown confirm strip; **lock screen PIN** set/change/clear (`proteus-pin.py`, PAM password gate; hash not in settings.json); current user GECOS/home/UID/groups; other users read-only; Online accounts jump; greetd status + **autologin toggle** via `proteus-greetd` (pkexec `[initial_session]`; no greetd restart); conf escape; no add/remove |
| Online accounts (provider seats) | `partial` — iced hub + password providers with glance create/edit (Nextcloud/IMAP/CalDAV/CardDAV/Apple via `proteus-accounts`); OAuth PKCE Connect wired; multi-seat glance megas / CalendarPanel write polish stay QML. Detail: [§3a](#3a-online-accounts-detail) |
| Privacy & security (transparency · mute · session · grants) | `partial` — hub + leaves; what leaves; weather mute; DND / Lock / clipboard / LocalSend; **In use now** (mic/camera/screen apps via `privacy-indicators.py`); category Allow/Deny + per-app Allow/Ask/Deny in `permissions.json` (`proteus-permissions.py` · `Permissions.qml`); Flatpak mic/camera overrides; **portal PermissionStore sync** (devices mic/camera + screencast best-effort); **capture enforce** (Deny + Ask mute/destroy active mic/camera/**screen** screencast-like PW nodes; session Allow-once via runtime session file); **portal Session.Close** best-effort on screen Deny/Ask (`org.freedesktop.portal.Session.Close` + PW destroy fallback); **Ask prompt** (`PrivacyAsk` · Allow once / Always Allow / Deny at Dock/Beacon launch **+ mid-session mic/camera/screen** via activity probe); EnvGate ask≠deny; **fail-closed until `Permissions.ready`** (privacy-gated apps + Diagnostics); smoke/install harness; **not a full OS sandbox** (no AppArmor/v4l2 ACL · perfect screencast attribution Out) |
| About (hardware class / capabilities) | `shipped` — OS/kernel/hostname (`SystemInfo`); Hyprland/Quickshell versions; tip hash; hw-probe class/caps; CPU/mem/swap/storage/uptime (`SystemLoad`, About-active only); battery when present (`Power`/UPower); Mission Center escape; Check for updates → Software; **hard Session posture** (`SessionPosture` → `proteus-posture`, confirm); soft Hyprland profile under **Advanced · window rules** (`HyprProfile`); Copy + Copied; session power under Users only; no in-Settings live dashboard |
| Host / VM·container setup | **thin Settings hub** (`virtualization`) — Workloads jump · engines status · headless chrome Fact; mutations stay in `proteus-workloads` app; auto-resolver / Portainer Out |
| Cold-start (open feel) | `shipped` — async `shell.qml` → `Settings.qml`; `kit/StickyPaneLoader` (active category first, sticky after visit); Keyboard/Keybinds deferred; Settings QS skips live hw-probe (`Hardware.isSettingsApp` → cache only) |
| Window & layout | `shipped` — normal app window (tiles / floats like any other; legacy float+center windowrule removed, config.sh strips it from old installs); wide/tiled windows cap + center the pane column (`paneMaxW` 760; back/title track it, ✕ stays at the corner; Mixer full-bleed); **single-instance** (`proteus-settings` reuses via `nav` IPC + `raise` / hypr focus; `quickshell -n` race guard) |
| Dual-path chrome (GUI + keyboard) | `shipped` — mouse-legible Settings IA; `Super+,`; Beacon Settings search; Actions (Wi‑Fi / Displays / Mixer / Privacy / Focus / Updates + session); `Super+Shift+F` Focus cycle; Settings `/` typeahead jump; hub lists ↑↓ Enter |

Modular panes: `apps/proteus-settings/panes/*` · form kit: **`shell/shared/kit/*`** (symlinked as `apps/proteus-settings/kit` so panes keep `import "../kit"`; it lives in the shared spine so the console renderer under `shell/surfaces/console/` can reach it too). Shell stays in `Settings.qml`.
Shared spine: flat `shell/shared/` + named helpers — [FACTS.md](./FACTS.md).
North-star IA: [SETTINGS-IA.md](./SETTINGS-IA.md).


### 3a. Online accounts detail

**Shape** — hub → per-provider leaves (`AccountsPane` Connected / Add account ·
`AccountsProviderLeaf` · SettingsNav `accounts` hub). Canonical provider list with
friendly blurbs: Google · Microsoft · **Exchange** · Nextcloud · IMAP · CalDAV ·
CardDAV · Apple. Status and seats merge from `proteus-accounts`, so a stale
catalog cannot inject Coming-later rows.

**Auth** — OAuth Connect inline once a client id is ready; multi-seat Disconnect
and OAuth Reconnect; tokens live in the vault, never `settings.json`.

**Glances** — calendar + mail + contacts (CalendarPanel · `CalendarEvents` /
`MailGlance` / `ContactsGlance` · fetch scripts) over IMAP/CalDAV/CardDAV/Apple
plus Google/MS/Exchange Graph. Older Google/MS seats must reconnect to pick up
write/send/contacts scopes.

**Thin write paths**

| Area | Backend | Surface |
|------|---------|---------|
| Calendar create/edit/delete | `proteus-calendar-mutate.py` — CalDAV · Google `calendar.events` · MS/Exchange `Calendars.ReadWrite` | CalendarPanel Add/Edit/✕ (title + day) |
| Recurrence create+edit | daily/weekly/monthly · **COUNT end presets** Forever/2×/5×/10× | whole series only |
| Mail compose | `proteus-mail-send.py` — Google `gmail.send` · MS/Exchange `Mail.Send` · IMAP/Apple SMTP | To/Cc/Bcc/Subject/Body · **one-file attach** |
| Contacts create/edit/delete | `proteus-contacts-mutate.py` — CardDAV · Apple Basic · Google People `contacts` · MS/Exchange `Contacts.ReadWrite` | CalendarPanel Add/Edit/✕ (name + one email) |

**Out** — first-party Proteus mail/contacts/Drive apps · photos/groups/full vCard ·
HTML, drafts, reply, multi-file attach · this-vs-all, UNTIL date, attendees,
exceptions · EWS/NTLM · Sign in with Apple OAuth.

---

## 4. Postures

Locked product set: [POSTURES.md](./POSTURES.md).

| Posture | Status |
|---------|--------|
| desktop | `partial` — primary focus spine |
| console | `partial` — list IA + owned Hypr face: Games/Media/Apps + **Console Settings face thin** (Wi‑Fi/Sound/Privacy jumps). **gamescope console-home not swapped**. Detail: [§4a](#4a-console-detail) |
| host | `partial` — seat-driven headless default; owned host face Glance **HexOS cards** (`proteus-host-metrics.py`); Workloads mutation surface; graphical-remote attach Out |
| home · wearable · xr · vehicle | `parked` — thesis only; not in proof order |

Focus set + separation rules: [POSTURES.md](./POSTURES.md) §2a. Hard flips:
`proteus-posture console|desktop|host` — **uniform session restart to the
greeter** in managed sessions (`proteus-session` picks the engine at next
login); dev/nested fallback = in-place chrome flip
(`PROTEUS_SKIP_SESSION_LOCK=1`). Host defaults headless; `--chrome` or
`proteus-host-seat attach` for UI. Enter from desktop: Beacon · CC ·
`Super+Shift+C` / `Super+Shift+H`. Settings → About **Session posture** = hard
picker; **Hyprland profile** = Advanced soft window rules only (not exit).

Console dogfood (guest): `bash /mnt/proteus/dev/dogfood/dogfood-console.sh`
(`--launch browser|retroarch`; `--restore`). Host dogfood:
`bash /mnt/proteus/dev/dogfood/dogfood-host.sh` (default headless → seat attach/detach;
`--restore` → desktop). Titles via `proteus-console-seat` (Gamescope when usable).
Primary chrome is Games/Media/Search/Settings list IA; stores-as-backend locked in POSTURES.

### 4a. Console detail

**Primary chrome** — list IA: Games · Media · Apps · Search · Settings, with a
footer status strip and pad legend.

| Destination | Contents |
|-------------|----------|
| **Games** | Recent · **Installed titles** (`proteus-console-games.py` scans Steam appmanifests + RetroArch playlists → per-title seat launch) · Launchers |
| **Media** | Streaming allowlist **only** — no AudioVideo-category fallback; local playback lives in the Search sheet |
| **Apps** | Curated lean-back tools — browser, Discord, terminal |
| **Settings** | In-chrome **Console Settings face** (`settingsFaceHubs(console)`) — Wi‑Fi scan/connect, Sound sink picker, status strip; Full Settings is the desktop escape |

Stores are backends, not the shell — locked in [POSTURES.md](./POSTURES.md).

**Gamescope-as-session** (`partial`) — `proteus-session` switches engine at login
when `game_scope` is available (gamescope + hardware Vulkan) and hands off to
`proteus-console-gs-session`:

- Gamescope owns the session; **Proteus Home** is a QS xdg client (`shell/console-home`).
- Guide focus-flip via `proteus-console-focus` baselayer atoms.
- Lock = session exit — the login screen *is* the lock.
- Host-side spike `dev/spike/gs-qs-spike.sh` PASSED.
- Prove paths: bare metal, or **VFIO passthrough** (`PROTEUS_VM_VFIO`).

**Interim** (VirGL / no hardware Vulkan) — Hyprland kiosk + supervised seat +
per-title/nested Gamescope. Shelf Home is retired from the primary path; Guide
long-hold exits to desktop.

**Pad input** is **single-fire** — `proteus-guide` single-instance lock,
BTN_DPAD/HAT dual-report dedupe, hold-repeat delay. Kit: `apply-console-kit.sh`.


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
| `~/.config/proteus/root` | Install-root Fact — greetd starts `proteus-session` with a clean env, so bare metal cannot rely on `/mnt/proteus`; written by `install/config.sh`, validated before use ([INSTALL.md](./INSTALL.md)) |
| `~/.config/proteus/posture` | Hard-switch Fact (`desktop` \| `console` \| `host`) — boot + `proteus-qs` when `PROTEUS_SURFACE` unset |
| `~/.config/proteus/host-chrome` | Host seat chrome (`none` \| `full`) — `proteus-posture` / `proteus-host-seat` |
| `~/.config/hypr/profiles/*.conf` | Posture fragments (desktop + console fullscreen + host lean ops shipped; home stub) |
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
| `./dev/vm/run.sh` | Boot installed guest (disk under `PROTEUS_VM_CACHE`, default `~/.cache/proteus-vm`) |
| `./dev/vm/run.sh snapshot\|restore` | qcow2 snapshots (`hyprland-base`, …) |
| `./dev/vm/download-iso.sh` / `create-disk.sh` | Fetch ISO / create disk in cache |
| `./dev/vm/provision.sh` | Prepare ISO/disk hints + SSH overlay (`bootstrap.sh`); `status` = read-only checklist (ISO/disk/SSH/last overlay; running-VM-safe `qemu-img -U`) |
| `./dev/vm/bootstrap.sh` | SSH guest → light overlay (`install/bootstrap.sh`; passes REPAIR/UPDATE knobs) |
| `bash /mnt/proteus/install/bootstrap.sh` | On guest: staged overlay incl. `console` stage (multilib + Steam/RetroArch/cores/pads); `repair` = fast config→apps→console preset; `PROTEUS_INSTALL_UPDATE=1` = -Syu + list refresh; skip/resume/only knobs |
| Repo layout (post-split) | `install/` overlay (VM + bare metal) · `install/machine/` install-time mutators · `shell/scripts/` **all** runtime PATH helpers · `dev/dogfood/` · `dev/vm/` QEMU harness only — asserted by `check.sh` ([ARCHITECTURE.md](./ARCHITECTURE.md) §4) |
| Product vs maintainer boundary | `dev/` holds **all** maintainer tooling (vm harness · smoke · dogfood · spike · fixtures · runners) and is never installed onto a machine; repo root is product-only. Enforced by `check.sh` — including that `install/` never *executes* anything from `dev/` |
| `./dev/smoke/install-idempotency-smoke.sh` | **Executable** — runs the `config` stage twice in a stubbed sandbox and diffs; catches a broken append-guard duplicating `hyprland.conf` directives. Covers `config` only (the rest are pacman/root-dominated) |
| `./dev/vm/provision.sh fresh` | `partial` — unattended VM base install via `auto-install.py` over QEMU serial. Wiring gated by `check.sh`; **never run end-to-end** |
| `./dev/smoke/settings-backing-smoke.sh` | **Executable** — HARD RULE 2 enforced. Every settings hub declares `backsFacts` / `backsCli`; the gate resolves 46 CLI and 16 Fact declarations against helpers, services, a declared external-tool list and §5. Catches a renamed helper or an undocumented config path at gate time |
| `./install/check.sh` | Host tree/`bash -n` gate for overlay stages + roster split + repair/status wiring + bare-metal root chain + snapshots + INSTALL.md |
| `PROTEUS_ROOT="$PWD" sudo -E bash install/bootstrap.sh` | **Bare metal** — same overlay, no 9p; writes the root Fact ([INSTALL.md](./INSTALL.md)) |
| `proteus-cli-surface [posture] [--facts] [--json]` | Derives a posture's inspectable command surface from the hubs' `backsCli` (desktop 44 · console 38 · host 41). Capability-gated when an hw-probe cache exists; marks each command on-PATH / in-checkout / absent. **Host is headless by default — this is its interface** |
| `proteus-snapshot status\|list\|create\|pre-flip\|rollback` | Bare-metal rollback net (btrfs + snapper); `rollback` is a dry run without `--yes`; honest when unsupported |
| `bash /mnt/proteus/install/machine/install-settings-app.sh` | Install Settings + keybinds + desktop/displays conf |
| `bash /mnt/proteus/install/machine/install-keybinds.sh` | Keybinds file + hypr source (user home) |
| `bash /mnt/proteus/install/machine/install-desktop-conf.sh` | `proteus-general.conf` + `proteus-monitors.conf` + sources |
| `bash /mnt/proteus/install/machine/install-lock-pam.sh` | `/etc/pam.d/proteus-lock` (falls back to `login` if absent) |
| `./dev/run-nested.sh` | Nested Hyprland on host |
| `./dev/smoke-all.sh` | Host smokes (layout · widget-layout-resolve · ipc-contract · config-schema · config-roundtrip · app-manifest · chrome-tokens · shell-core · software-reliability · power-logind · accounts · users · lock-pin · permissions · desktop · spaces · focus · control-center · beacon · audio-mix-serve · hw-probe · install · session · posture-hard · console · host · workloads-app · qs-version); guest `qs-guest` + `software-guest` + `console-guest` + `host-guest` if SSH or `PROTEUS_GUEST=1` |
| `./dev/smoke/shellcheck-smoke.sh` | **Executable** static analysis of 116 shell sources — gate = severity `error` (green); backlog **24 warning · 170 info** (mostly cross-file `SC2034` shellcheck cannot resolve) reported, not gated. SKIPs honestly without `shellcheck`. Found a live `SC2259` bug on adoption (piped stdin swallowed by a heredoc) |
| `./dev/smoke/doc-links-smoke.sh` | **Executable** — every relative link in every tracked `.md` must resolve (201 links / 39 docs). Caught 5 breaks the install/ rename left behind |
| `./dev/smoke/layout-smoke.sh` | Flat `shell/shared/` + Settings `kit/` structure |
| `./dev/smoke/widget-layout-resolve-smoke.sh` | Widget free/snap resolve capped + flush/no-overlap geometry stress |
| `./dev/smoke/ipc-contract-smoke.sh` | Smoke `qs ipc call` sites ⊆ shell/Settings `IpcHandler` methods |
| `./dev/smoke/config-roundtrip-smoke.sh` | Mutate `settings.minimal.json` prefs; still ⊆ Config keys + JSON round-trip |
| `./dev/smoke/config-schema-smoke.sh` | Config FileView keys ↔ `dev/fixtures/settings.minimal.json` |
| `./dev/smoke/app-manifest-smoke.sh` | `env/apps` schema + catalog + EnvGate postures/prefers/device_classes wiring |
| `./dev/smoke/chrome-tokens-smoke.sh` | `env/chrome` tokens JSON/CSS (generated by `proteus-shell-core tokens`; drift-gated when built) + ThemeSlider/ThemeSwitch stock-ban |
| `./dev/smoke/shell-core-smoke.sh` | `proteus-shell-core` rung-0 parity — settings schema keys vs Config.qml JsonAdapter · facts fixtures (couch→console, fail-open) · 25-case gate matrix (apps + panes) · `env/settings/catalog.json` extraction · `proteus-open` contract + ShellState thin-exec wiring · `serve` first NDJSON line |
| `./dev/smoke/shell-smoke.sh` | owned iced shell rung-1 — workspace · proteus-ui/shell lib tests · layer namespaces · IPC targets · daemon multi-layer boot markers · headless `proteus-shellctl` roundtrip · default engine Owned honesty + Quickshell fallback · UI/UX parity markers (kit widgets, icon pipeline, anim engine, heavy-worker freeze guard) |
| `./dev/smoke/shell-owned-dogfood-smoke.sh` | owned dogfood gate — build · headless ctl under `PROTEUS_SHELL_ENGINE=owned` · PAM unlock · face boot · HUD verbs · points at `owned-guest-smoke` for VM |
| `./dev/smoke/owned-guest-smoke.sh` | guest Wave 4 chrome — `shell-engine=owned` · `proteus-shell` live · ctl · hypr proteus-chrome · no QS primary (QS fallback via `PROTEUS_GUEST_QS=1`) |
| `./dev/smoke/settings-next-smoke.sh` | iced Settings sibling — packages confirm/orphans · sound latency/test/peak source gates · cargo build; skips if `../ProteusSettings` missing |
| `./dev/smoke/software-reliability-smoke.sh` | Host static checks — all six Software leaves + hub helper honesty + op narrative / leafUi |
| `./dev/smoke/power-logind-smoke.sh` | Host static checks for `proteus-logind` + Power.qml wiring |
| `./dev/smoke/accounts-smoke.sh` | Host static checks for `proteus-accounts` + Online accounts wiring |
| `./dev/smoke/users-smoke.sh` | Host static checks for `proteus-greetd` + Users autologin wiring |
| `./dev/smoke/lock-pin-smoke.sh` | Host static checks for unlock PIN hash store + `check-unlock.py` / `proteus-pin.py` / `proteus_auth.py` + apps.sh install + `shell/pam/proteus-lock` source (no live PAM auth) |
| `./dev/smoke/permissions-smoke.sh` | Host static checks for `permissions.json` store + Privacy leaves + EnvGate grant gate |
| `./dev/smoke/desktop-smoke.sh` | Host static checks for Desktop leaves + `proteus-defaults.py` / `beacon-file-index.py` + CC Edit › wiring |
| `./dev/smoke/spaces-smoke.sh` | Host checks for `proteus-workspace` band math + `status --fixture` 2-head + ensure/SpacesDisplays/hotplug + scratch/special CRUD fixtures (no live 2-head required) |
| `./dev/smoke/focus-smoke.sh` | Host checks for FocusMode add/rename/delete + DesktopFocusLeaf CRUD UI + roundtrip `name` field |
| `./dev/smoke/control-center-smoke.sh` | Host checks for ControlCenterLayout.setColumns + Settings columns UI + QuickSettingsGrid bind |
| `./dev/smoke/beacon-smoke.sh` | Host checks for Beacon Files index rebuild/search/status + UniversalSearch / defaultAppSubtitle / wtype wiring |
| `./dev/smoke/audio-mix-serve-smoke.sh` | Host checks for `proteus-audio-mix` dump/serve + Audio.qml wiring |
| `./dev/smoke/hw-probe-smoke.sh` | Wave A probe JSON (device_class + capabilities) |
| `./dev/smoke/install-smoke.sh` | Overlay installer tree check (stages incl. console · package roster split · repair preset · provision status · INSTALL.md) |
| `./dev/smoke/session-smoke.sh` | Host gate for `proteus-session` contract + `proteus.desktop` |
| `./dev/smoke/posture-hard-smoke.sh` | Host static checks for hard `proteus-posture` (desktop/console/host) + console profile rename (no live compositor flip) |
| `./dev/smoke/console-smoke.sh` | Host Phase 1/2 gate — SideList/detail · Games/Media/Search/Settings · streaming classifier · seat/caps/session · dogfood-console · install wiring (no live posture flip) |
| `./dev/smoke/console-guest-smoke.sh` | Guest console dogfood flip+verify + restore desktop (`dogfood-console.sh`); in `smoke-all` (SKIP unless SSH / `PROTEUS_GUEST=1`) |
| `./dev/smoke/host-smoke.sh` | Host Phase 1 gate — HostShell · default headless · proteus-host-seat · enter-host --chrome wires (no live posture flip) |
| `./dev/smoke/host-guest-smoke.sh` | Guest host dogfood flip+seat+restore (`dogfood-host.sh`); in `smoke-all` (SKIP unless SSH / `PROTEUS_GUEST=1`) |
| `./dev/smoke/workloads-app-smoke.sh` | Host static checks for thin `proteus-workloads` app + HostHome handoff |
| `./dev/smoke/qs-version-smoke.sh` | Record QS version policy (no IgnorePkg); checks `qs-guest-smoke` upgrade path |
| `./dev/smoke/qs-guest-smoke.sh` | Guest cold-start `SHELL_OK` / `SETTINGS_OK` + record `quickshell` version + polkit agent + nav deep link + Beacon + calendar + Customize/widgets IPC (add/move/snap/remove worldclock probe) |
| `./dev/smoke/software-guest-smoke.sh` | Guest Software dogfood (browse/inventory + Flatpak install/remove; yay\|paru; pacman mutator if passwordless sudo); in `smoke-all` (SKIP unless SSH / `PROTEUS_GUEST=1`) |

SSH default: `ssh -p 2222 andrew@127.0.0.1`
Install path SoT (three layers, knobs, repair, failures): [INSTALL.md](./INSTALL.md)

---

## 7. Docs locks (ahead of code)

| Lock | Doc | Code status |
|------|-----|-------------|
| Stack split (QML / Tauri / Rust) | [STACK.md](./STACK.md) | Settings+shell = QML; no Tauri apps yet |
| Hyprland as backend + QS limits | [COMPOSITOR.md](./COMPOSITOR.md) | Desktop Hyprland `shipped`; console interim Hypr+nested Gamescope `partial`; Gamescope-as-session + focus-flip `planned`; host seat-driven `partial`; home parked |
| Posture separation rules | [POSTURES.md](./POSTURES.md) §2a | Shared rules `partial` this pass (EnvGate panes, keybind filter, soft≠hard Advanced, host seat scaffold) |
| Adaptive apps / environment contract | [APPLICATIONS.md](./APPLICATIONS.md) | `partial` — `env/apps` manifests + EnvGate requires/postures/device_classes/prefers + adapts (input/nav/panes via FocusMode + Beacon hint + `PROTEUS_ADAPT_*` launch env) + Settings Focus hard pane hide + About `AdaptEnv` consumer; **remote** via probe CEC/IR/lirc / Bluetooth HID + soft stub (`PROTEUS_REMOTE_PROBE`) |
| Hardware module catalog | [HARDWARE.md](./HARDWARE.md) | Wave A probe + `Hardware.qml` session load |
| Capability / posture resolver | [POSTURES.md](./POSTURES.md) | Probe → caps in shell; posture still stub |
| Chrome language (company reference) | [CHROME.md](./CHROME.md) | `Theme.qml` + Settings `kit/` + `env/chrome/` export `shipped`; Rowena retarget `partial` |
| Facts / Config schema | [FACTS.md](./FACTS.md) · [CONFIG-SCHEMA.md](./CONFIG-SCHEMA.md) | Layout + docs `shipped` |

---

## 8. Not yet

- Host virt auto-resolver · Portainer-style Settings UI · graphical-remote seat attach (thin Virtualization + Workloads + host-chrome / proteus-host-seat shipped)
- Gamescope-as-session console + Guide focus-flip (interim nested session Fact shipped; launcher-first / stores-as-backend locked)
- Soft hypr profile reload sold as posture (Advanced window rules only; use `proteus-posture`)
- Parked postures (home / wearable / xr / vehicle) before focus three are proven  
- Snap / dependency graphs in Software  
- pacman IgnorePkg / ISO QS version pin (record + smoke only today)  
- First-party Tauri app under `apps/`  
- More Rust helper CLIs under `services/` (Wave A probe is Python; `proteus-pkg` + `proteus-logind` mutators + `proteus-audio-mix` resident dump/peaks shipped; mixer mutations still Python)  
- Tablet bezier per-tool pressure curves · gesture maps (active-area mm + pressure range + eraser-as-button + monitor region shipped)  
- ISO / installer productization — bare metal now runs the same overlay against a manual Arch base, but there is no unattended installer for real hardware ([INSTALL.md](./INSTALL.md))
- Bare-metal proof: nothing in the tree has been booted on real hardware yet. `game_scope`, charge thresholds, `/sys/class/backlight`, SMART and multi-head hotplug are all **unexercised** — the VM cannot reach them
- Second user: nothing here has been installed by anyone who did not write it  
- Rowena (and other sibling) CSS retarget onto `--proteus-*` export  

When shipping a feature, update this file in the same change.
