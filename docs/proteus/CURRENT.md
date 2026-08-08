---
doc: current
role: status
audience: contributors, coding agents
last_updated: "2026-08-08"
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
| [1. Platform](#1-platform) | Arch guest, smithay compositor, iced shell |
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
| Hyprland session | `retired` | Purged 2026-08-06 — smithay only |
| Quickshell shell | `retired` | QML chrome deleted 2026-08-06; do not reintroduce |
| Nested compositor (host) | `shipped` | `dev/run-nested.sh` — compositor winit `-c proteus-chrome` (Hyprland purged) |
| Owned-engine dogfood gate | `shipped` — Wave 4 closed; **2026-08-06 tree flip:** `shell/` is sole chrome crate (was `shell-next`); Quickshell + Settings QML deleted; face scaffold `shell/src/faces/`; see OWNED-STACK |
| Owned compositor (`proteus-compositor`) | `shipped` (thin) | `compositor/` Smithay; DRM session + nested winit; `zwp_idle_inhibit` → systemd-inhibit for `proteus-idle` — [COMPOSITOR.md](./COMPOSITOR.md) · [COMPOSITOR-SPIKE.md](./COMPOSITOR-SPIKE.md) |
| Soft hypr profile reload | `retired` | `env/hypr/` deleted; hard posture via `proteus-posture` only |
| QS version pin / respawn policy | `retired` | `proteus-qs` + user unit deleted with QML chrome |

---

## 2. Shell

Desktop (owned iced — `shell/src/app/` session + `platform/` helpers + shared `surfaces/` kit + `faces/{desktop,console,host}/`):

| Feature | Status |
|---------|--------|
| Top bar (workspaces, title, clock+weather center, CC icon) | `shipped` — wallpaper-first glass menu bar (Apple-quiet right cluster). **Left:** Spaces. **Center:** date · time · weather · notif badge → hub / glance. **Right:** tray · privacy · DND · battery · Control Center (wifi/BT/volume live in CC). IPC: `chrome calendar` · `chrome weather` · `chrome notifications`. Detail: [§2a](#2a-top-bar-detail) |
| Spaces (multi-display) | `partial` — **iced Spaces overview** (`proteus-spaces`): bar icon · equal landscape cards · 2×2 grim mosaic · soft active plate · pencil-glyph rename → `workspaceNames` · auto grow/shrink (occupied ∪ active + trailing empty, 1–10) · drag window → `movetoworkspacesilent` · stronger scrim open fade · `chrome spaces` IPC. Super+**1–10** = synced `workspace N` (all heads); **Super+Ctrl+1–10** = local `workspace N,local` on focused output. Per-output boards: `workspace N,output:NAME` · monitors JSON `activeWorkspace` + real `focused` · **overview per-head columns** (one strip per monitor when `monitors.len() > 1`; per-output occupied/visible; select respects `workspaceMode` perDisplay) · `proteus-workspace` synced/local goto. Compositor loads `workspaceNames` + `dispatch renameworkspace` (persists Fact). Settings `workspaceMode` Fact drives script mode. **Out:** Scratchpad ◇ UI · strip pills / parallax · Super+Shift move chords |
| Control Center (quick settings) | `shipped` (thin) — **2-column module grid** (Wi‑Fi / BT / DND / Focus) + paired brightness/volume · media · Appearance/mute · power · screenshot · network lists · Settings deep links. **No inbox** (center hub). Alpha frost (true blur Out). **Out:** layout editor, LocalSend, multi-monitor CC polish |
| Status HUD (volume · brightness) | `shipped` — top-right elevated glass chip; XF86 media keys + `proteus-shellctl hud` + CC sliders; suppressed while Control Center open; brightness honest-skip without `/sys/class/backlight` |
| **Beacon** — system search (`Super+Space` / `Super+D`) | `partial` — iced Apps + Settings + running Windows + file index search (`beacon-file-index.py`); empty-query **Places** (Home/Documents/Downloads/Desktop) + **Recents** (`launcherFileRecents`); **Clipboard** thin (`cliphist list` → Enter decode\|`wl-copy`, optional `wtype` Ctrl+V); **Calc** thin (safe `+ - * / % ^ ()` → copy result). Ghostty → `proteus-terminal`. Escape: `proteus-clipboard`. **Out / rebuild:** mode chrome (Ctrl+1–4), unit convert, image clipboard preview, Privacy grant search, QML-era Pinned richness |
| Dock (pins, layouts, running dots) | `shipped` — iced dock on **Top** with `exclusive_zone` from rest strip (`dock_strip_h`); Facts `dockLayout` (`center`\|`span`\|`left`\|`right`), `dockRounding`, `dockIconSize`, `dockEnabled`, `dockAutoHide` (slide + edge peek); **no magnify** — per-icon hover scale + stronger launch bounce; menu bar `barHeight` / `barRounding` / `barAutoHide`; running mute disc / focused pill / **1–3 multi-window dots**; divider pins ‖ transients; bottom-dock dwell preview (~350ms grim thumbs; vertical preview Out). **Long-press edit** (~450ms): reorder pinned cells (Beacon fixed at 0) + **(−) remove pin** + Done → `dockPins` persist. Settings → Desktop → Dock & menu bar. **Out:** drag-off unpin gesture; right-click Keep/Remove; `dockMonitor` / `barMonitor`; Win11 centered-on-span icons; vertical dwell previews |
| Session start (`proteus-session`) | `shipped` — **smithay only** (`proteus-compositor --backend drm -c proteus-chrome`); Hyprland **purged** (Fact=hyprland / nested display / missing bin / DRM fail → exit 1); SSD title (double-click maximize · button hover/press) + smart-gaps; portal-wlr |
| Desktop widgets (free place; Customize) | `shipped` (thin) — **hold empty wallpaper** (~450ms) or `Super+Shift+W` / `chrome customizeDesktop`; free-place drag + Snap to Grid + alignment guides; persist `desktopWidgets[]`; widgets clickable outside Customize (clock→calendar, weather→glance, …). Gallery Add Widget. **Out / thinner than QML era:** arrow-key nudge polish, live scaled previews, note edit-in-place depth. Lock stays **zone/strip** Customize (not free-place). Detail: [§2b](#2b-desktop-widgets-detail) |
| Lock screen (`Super+L`, PAM + `WlSessionLock`) | `shipped` — Customize mode, zone layout, applets; cold boot auto-lock **with no desktop peek** (bar/dock/widgets **and** Beacon/CC/calendar/toasts/HUD gate on `sessionStartLockPending`; overlay toggles blocked while pending; held until first unlock; **opaque wallpaper/solid floor** painted into the Overlay lock so app windows cannot show through the dim wash; **`ext-session-lock-v1` thin on compositor** — blanks xdg windows + draws LockSurfaces; ctl `session-lock` reports `supported`/`pending`/`locked`/`active`; Fact `session-lock` / `PROTEUS_SESSION_LOCK` default stays **overlay**; protocol opt-in via `proteus-session-lock` + nested dogfood `compositor-session-lock.sh`); wake-up keystroke is kept for password mode (PIN digits via keyboard too); password field auto-focused; lock tick is light (1s, no sensor spam) and key-repeat is ignored on the wake/PIN path so lag cannot insert ghost characters; attempt cooldown after 3 misses; optional **unlock PIN** (numpad + keyboard digits, auto-submit; password still works) — PIN pad vertically centered above applets, strip widgets hide while PIN is up, layout reserve keeps tiles out of the auth band; via `check-unlock.py` + hashed `~/.local/share/proteus/auth/pin`; **console** reuses the same lock / PAM+PIN path |
| Global shortcuts (Beacon, settings, lock) | `shipped` (thin) — compositor Super chords (`binds.rs`): Beacon · Settings · lock · terminal · Spaces customize · screenshot · **Super+E** files (`xdg-open $HOME`) · XF86 volume/brightness → HUD; **bindm** Super+LMB move · Super+RMB resize (`keybinds.json` `bindm`); overrides `~/.config/proteus/keybinds.json`; `dispatch reloadbinds`; Settings Keyboard thin rebind (Set chord / Reset → Fact + `reloadbinds`; Spaces/XF86 / full editor Out) |
| Hardware probe at session start | `shipped` — Wave A (`proteus-hw-probe` + shell/shell-core cache) |
| Env gate (Beacon / Settings / dock) | `shipped` — shell-core gate (+ `env/apps` manifests); **postures** + **device_classes** hard allow-lists · **prefers** soft hint/boost · **adapts** soft profile (input/nav/panes via Focus) + **`PROTEUS_ADAPT_*` launch env** on Dock/Beacon/`openSettings`; **Focus minimal hard-hides** non-allowlisted Settings panes; **`adapts.input` remote** via probe CEC/IR/lirc / Bluetooth HID + `PROTEUS_REMOTE_PROBE` stub; Settings About may surface adapt env + remote status + Focus density; app icon resolve + Proteus brand marks |
| Chrome design lock (`CHROME.md`) | `shipped` — principles + token tables + Settings patterns; sibling export `env/chrome/` `shipped` |
| Owned-stack ladder ([OWNED-STACK.md](./OWNED-STACK.md)) | `partial` — iced chrome + smithay compositor **shipped** (thin); Settings iced sibling; polish holdouts remain; **desktop gamescope nest** via `proteus-gamescope` (Steam `%command%`); **gamescope console-home not swapped** |
| Theme tokens | `shipped` — space/radius scale + accent/font from Config; company lock [CHROME.md](./CHROME.md) |
| Themed controls (`theme_slider` / `theme_switch`) | `shipped` — `proteus-ui` kit; QML ThemeSlider/ThemeSwitch retired |
| Shared package layout | `shipped` — `shell/{src,scripts,pam,assets}` + `app/` (session + `handlers/{overlays,spaces,dock,…}`) + `platform/{power,network,notifs,…}` + `faces/{desktop,console,host}/` + `surfaces/{bar,dock,…}`; `main.rs` boot + App seed, session logic in `app/`; QML `shared/` deleted |
| Smoke suite (`dev/smoke-all.sh`) | `shipped` — **desktop spine only** (shell · compositor · settings-next · install · session · owned-guest); console/host/software-guest + QML-era leaf stubs deferred |


### 2a. Top bar detail

Glass menu bar, wallpaper-first (`menuBarAlpha` clearer than the dock; soft text
outline when thin, including DND/Awake chips).

**Left**
- **Spaces icon** — opens full-screen Spaces overview (`proteus-spaces`);
  wheel over the icon cycles the shell visible set (occupied ∪ active + one
  trailing empty, cap 10). Rename and window drag live in the overview, not on
  the bar. `workspaceMode` synced/perDisplay is Settings Fact–only until
  compositor multi-head Spaces.
- **No menu-bar window chrome** — apps draw their own titlebars (CSD).
  Compositor forces ClientSide (GTK’s ServerSide asks are ignored) so SSD
  never steals a 28px gap above tiled windows.

**Center** — date · time · weather · notif badge
- Date dim + time demi; weather glyph/temp; unread badge.
- Date/time opens the **center hub** on the Calendar tab (real month grid + today).
- Badge (or empty-dot) opens the hub on **Notifications** (inbox moved out of CC).
- Weather chip opens the **weather glance** (Open-Meteo when location set; honest
  mute / “Set location” deep links otherwise).
- IPC: `chrome calendar` · `chrome weather` · `chrome notifications`.

**Right**
- **App tray** (StatusNotifier — 1Password etc.).
- **Privacy dots** — mic orange · camera green · screen purple; click → Privacy.
- **System services** — wifi · Bluetooth (open CC) · volume (scroll step / click mute) · battery.
- **Tiling toggle** — grid glyph; click `togglefloating` on the focused window
  (compositor). Floating move/resize via compositor pointer path.
- DND · battery · **Control Center glyph** (wifi / BT / volume detail open in CC).

**Notes**
- Beacon button is off the bar — the dock pin and `Super+Space` own it.
- Battery % shows only with a real battery (`Power.hasBattery`) — a VM/desktop
  shows none rather than 0%.

### 2b. Desktop widgets detail

Enter Customize by **hold-click empty wallpaper** (~450ms; not on widget bodies —
avoids phantom Customize from ordinary clicks) or `Super+Shift+W`
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

**Catalog** (shell desktop widgets)

| Widget | Notes |
|--------|-------|
| clock · media · battery · weather | — |
| **calendar** | today tile at S; month grid + today disc at M/L; midnight rollover |
| **system glance** | CPU/mem bars + uptime via `SystemLoad` retain/release refcount; storage at L |
| **note** | sticky — click to write in place, debounced save to `noteText`; widget layer raises and grabs the keyboard while editing; read-only on lock |
| **world clock** | first multi-instance type (`unique: false`) — one per city; `TZ=<zone> date` owns the tz math; in-widget city picker persists `tzId`/`tzLabel` |

Separate from the lock screen; **not** surfaced in Settings; a widget store is Out.

---

## 3. Settings

App: iced sibling `../ProteusSettings` (`proteus-settings-next`) via
`/usr/local/bin/proteus-settings` · `Super+,` / Beacon / `proteus-open settings`.
QML Settings is **retired** (no escape). Legacy Tauri `app/` is frozen.

**Wave 4 iced default `shipped`** — deep links `--page`/`--query` + single-instance.
**Look `shipped` (thin):** System Settings posture via `proteus-ui` —
`settings_group` inset lists + hairlines, `hub_row` list nav (not CTA slabs),
compact Shrink CTAs / `button_cluster`, trailing form rows, `large_title`,
sidebar `accent_soft` selection (true blur Out).
Ported thin: Appearance · Software · Sound (Mixer grid thin — route/volume/ensure
In; peaks + drag-reorder Out) · Notifications · Users · Privacy (activity +
categories + per-app grants + Flatpak/Diagnostics thin) · Network
(machine/wifi/BT/Devices/Diagnostics/LocalSend · VPN import thin · Tailscale thin usable ·
Headscale HuJSON + structured ACL groups thin) · Desktop (gaps live-apply ·
defaults/focus CRUD thin/beacon) · Power · Date/Time · About · Virtualization ·
Peripherals (mouse/touchpad/tablet → `proteus-settings-apply input` · gamepads Guide
Facts) · Accounts (multi-seat glances thin) · Displays. Holdouts: Mixer
peaks/drag-reorder, Tailscale deep ACL, Headscale ACL visual graph, Focus
critical/auto-apply/RRULE.
([STACK.md](./STACK.md) §6).

| Pane | Status |
|------|--------|
| Appearance → Accent / Background / Lock / Icons / Font (`style`) | `shipped` (iced) — Accent/mode/font; lock wallpaper/dim; daily/slideshow/`proteus-bg`; Font picker + userFonts; Icons; chrome apply via tokens / settings-apply |
| Desktop → Gaps / Borders / Motion / Dock & menu bar / Spaces / Default apps / Focus / Control Center / Beacon | `shipped` (thin iced) — Gaps live via `proteus-settings-apply`; Spaces `workspaceMode` Fact; **Default apps** picker (`proteus-defaults.py`); **Focus** enable + active picker + **profile CRUD** (add/rename/delete · keywordAllow/Deny · **allowedApps** CSV · **schedule** `{enabled,days,start,end}`); CC columns 2|3; Beacon blurb + Clear recents; **Dock & menu bar** layout/size/rounding/autohide Facts → shell mtime reload. **Out:** critical-break UI · auto-apply schedule · RRULE · shell keyword/allowlist enforcement |
| Displays (scale / mode / orientation, Identify; layout canvas) | `shipped` (thin) — iced list + layout canvas; Apply writes `~/.config/proteus/displays.json` + live `proteus-settings-apply apply-displays` (`output` scale/pos/mode/**transform**); Fact loads transform at compositor start; monitors JSON reports live wl transform; **Identify** (`dispatch identify`); **10s snapshot Revert** (Keep / timeout / Refresh / leave / topology); Settings orientation UI **In** (Normal/90/180/270 · flipped Out) |
| Peripherals → Keyboard (shortcuts) / Mouse (sensitivity, accel) / Touchpad / Tablet / Gamepads | `shipped` (thin) — mouse/touchpad/tablet Facts → `proteus-settings-apply input` → compositor `dispatch input-reload` (sensitivity scale · natural scroll · scroll factor; tip/eraser piecewise-linear pressure curves + linear min/max on `TabletToolAxis`; tap/accel/DWT held on InputConfig); keyboard thin rebind UI → `keybinds.json` + `reloadbinds`; tablet gestures Out; **Gamepads** Guide Facts (`gamepadsGuideSingle` / `gamepadsGuideDouble` nav\|cc\|off → `proteus-guide` re-read); device list Out; **per-device** `inputDeviceOverrides` Out |
| Software → Updates / Repos / AUR / Flathub / AppImages / Web apps / Orphans (`packages`) | `shipped` — iced hub + leaves; Install\|Installed mode-safe loads; sticky action bar; live `$` op + Cancel + last error; empty Installed / orphans / AppImages honesty; **Web apps** (`proteus-webapp` → user `.desktop`, no polkit); hub Needs yay/paru · flatpak; AppImages user-only; escape **Install…** → seeded Software leaf; gated via `settings-next-smoke` (guest `software-guest-smoke` deferred); dep graphs / Snap Out |
| Sound → Output / Input / Applications / Mixer / Latency (`sound`) | `shipped` — iced hub + leaves; **Mixer** Wave Link–style grid thin (channels/inputs × mixes · route · volume · Ensure In); Speakers/mix listen + rename when dump provides them; honest setup CTA; graph editor escape (`qpwgraph` Install… → Repos); resident `proteus-audio-mix serve` (Python mutations + fallback); Output/Input/Apps/Latency; pactl + `pw-metadata`. **Out:** row peaks · drag-reorder |
| Network → This machine / Devices / Diagnostics / Wi‑Fi / Bluetooth / LocalSend / Tailscale / VPN / Headscale (`network`) | `shipped` (thin iced) — machine/wifi/BT; **Devices** link+IPv4; **Diagnostics** route/DNS/`ss`/ping; LocalSend detect/open; **Tailscale thin usable** (login-server Fact · peers · exit-node · up/down); VPN nmcli up/down + **WG/OpenVPN import thin** (`nmcli connection import`); Headscale users + HuJSON check/save + **structured ACL groups thin** (JSON-compatible subset · add/remove members → draft → Check/Save). Out: cert path / user-pass / PKCS#11 · Wireshark · Tailscale deep ACL · Headscale ACL visual graph |
| Power (PPD mode + battery + idle/lid + charge limits) | `shipped` — Performance/Balanced/Eco via `powerprofilesctl`; battery via UPower; `pkexec proteus-logind` drop-in + reload (not restart); CC Power tile; **Charge limits** when sysfs `charge_control_*` present (`pkexec proteus-battery-threshold` · fail-closed otherwise); TLP Out |
| Date, time & weather (clock, timezone search, NTP, locale, **Location**) | `shipped` — timezone/NTP/`localectl set-locale` polkit-gated; searchable locale picker + locale.conf escape; Location explicit place search (never IP); Open-Meteo current + **5-day forecast** + Conditions H/L/sunrise; Match time zone to place when TZ differs; desktop/lock weather widget; manual time / RTC writers Out |
| Users (session actions + read-only local users · greetd autologin) | `shipped` — Session Lock/Logout; Reboot/Shutdown confirm strip; **lock screen PIN** set/change/clear (`proteus-pin.py`, PAM password gate; hash not in settings.json); current user GECOS/home/UID/groups; other users read-only; Online accounts jump; greetd status + **autologin toggle** via `proteus-greetd` (pkexec `[initial_session]`; no greetd restart); conf escape; no add/remove |
| Online accounts (provider seats) | `partial` — iced hub + password providers with glance create/edit (Nextcloud/IMAP/CalDAV/CardDAV/Apple via `proteus-accounts`); OAuth PKCE Connect wired; **multi-seat glances thin** (list per provider · create/edit/disconnect upsert without clobbering siblings). CalendarPanel write polish depth remains thin. Detail: [§3a](#3a-online-accounts-detail) |
| Privacy & security (transparency · mute · session · grants) | `partial` — iced hub: **In use now**; category Allow/Ask/Deny; **per-app grants thin** (permissions.json `apps` ∪ desktop apps · `store-set-app`); **Flatpak** mic/camera overrides (`proteus-permissions.py`); **Diagnostics** readiness (permissions.json · portal-sync · activity). Shell Ask prompt + capture enforce remain. Out: AppArmor |
| About (hardware class / capabilities) | `shipped` (thin iced) — OS/kernel/hostname; tip hash; hw-probe class/caps; load strip; battery when present; Mission Center escape; Check for updates → Software; **hard Session posture** (`proteus-posture`, confirm); session power under Users only |
| Host / VM·container setup | **thin Settings hub** (`virtualization`) — Workloads jump · engines status · headless chrome Fact; mutations stay in `proteus-workloads` app; auto-resolver / Portainer Out |
| Cold-start (open feel) | `shipped` — iced `proteus-settings-next` (sibling); pane load deferred where needed; hw-probe cache-first in Settings |
| Window & layout | `shipped` — normal app window (tiles / floats like any other); pane column capped; **single-instance** via `proteus-settings` / nav IPC |
| Dual-path chrome (GUI + keyboard) | `shipped` — mouse-legible Settings IA; `Super+,`; Beacon Settings search; Actions (Wi‑Fi / Displays / Mixer / Privacy / Focus / Updates + session); `Super+Shift+F` Focus cycle; Settings `/` typeahead jump; hub lists ↑↓ Enter |

Settings app: sibling [`../ProteusSettings`](../../../ProteusSettings/AGENTS.md) (`proteus-settings-next` via `proteus-settings`). Shared iced kit: `services/proteus-ui`. Facts spine: [FACTS.md](./FACTS.md). North-star IA: [SETTINGS-IA.md](./SETTINGS-IA.md).


### 3a. Online accounts detail

**Shape** — hub → per-provider leaves (`AccountsPane` Connected / Add account ·
`AccountsProviderLeaf` · SettingsNav `accounts` hub). Canonical provider list with
friendly blurbs: Google · Microsoft · **Exchange** · Nextcloud · IMAP · CalDAV ·
CardDAV · Apple. Status and seats merge from `proteus-accounts`, so a stale
catalog cannot inject Coming-later rows.

**Auth** — OAuth Connect inline once a client id is ready; **multi-seat**
Disconnect and OAuth Reconnect per seat id (connect upserts by identity /
explicit edit seat — does not wipe sibling seats for the provider); tokens live
in the vault, never `settings.json`.

**Glances** — calendar + mail + contacts (CalendarPanel · `CalendarEvents` /
`MailGlance` / `ContactsGlance` · fetch scripts) over IMAP/CalDAV/CardDAV/Apple
plus Google/MS/Exchange Graph; Settings lists every seat per provider. Older
Google/MS seats must reconnect to pick up write/send/contacts scopes.

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
| console | `partial` — list IA + owned console face stub: Games/Media/Apps + **Console Settings face thin** (Wi‑Fi/Sound/Privacy jumps). **gamescope console-home not swapped** (desktop nest is separate — `proteus-gamescope`). Detail: [§4a](#4a-console-detail) |
| host | `partial` — seat-driven headless default; owned host face Glance **HexOS cards** (`proteus-host-metrics.py`); Workloads mutation surface; graphical-remote attach Out |
| home · wearable · xr · vehicle | `parked` — thesis only; not in proof order |

Focus set + separation rules: [POSTURES.md](./POSTURES.md) §2a. Hard flips:
`proteus-posture console|desktop|host` — **uniform session restart to the
greeter** in managed sessions (`proteus-session` picks the engine at next
login); dev/nested fallback = in-place chrome flip
(`PROTEUS_SKIP_SESSION_LOCK=1`). Host defaults headless; `--chrome` or
`proteus-host-seat attach` for UI. Enter from desktop: Beacon · CC ·
`Super+Shift+C` / `Super+Shift+H`. Settings → About **Session posture** = hard
picker (soft hypr profile retired with `env/hypr/`).

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

- Gamescope owns the session; **Proteus Home** is an xdg client under that seat.
- Guide focus-flip via `proteus-console-focus` baselayer atoms.
- Lock = session exit — the login screen *is* the lock.
- Prove paths: bare metal, or **VFIO passthrough** (`PROTEUS_VM_VFIO`).

**Interim** (VirGL / no hardware Vulkan) — smithay seat + supervised seat +
per-title/nested Gamescope. Shelf Home is retired from the primary path; Guide
long-hold exits to desktop.

**Pad input** is **single-fire** — `proteus-guide` single-instance lock,
BTN_DPAD/HAT dual-report dedupe, hold-repeat delay. Kit: `apply-console-kit.sh`.


---

## 5. Config facts

| Path | Role |
|------|------|
| `~/.config/proteus/settings.json` | Theme/desktop prefs (shell-core / iced Settings); wallpaper keys; widgets; DND — [CONFIG-SCHEMA.md](./CONFIG-SCHEMA.md) |
| `~/.config/proteus/keybinds.json` | Shortcut overrides for compositor (defaults baked in `binds.rs`) |
| `~/.config/proteus/displays.json` | Output scale/pos/mode/transform for compositor |
| `~/.config/proteus/gamescope-flags` | Desktop nest argv for `proteus-gamescope` (Steam: `proteus-gamescope %command%`) |
| `~/.config/proteus/permissions.json` | App permission categories + per-app Allow/Ask/Deny (0600; `proteus-permissions.py`) — not in settings.json |
| `~/.local/share/proteus/auth/pin` | Lock-screen unlock PIN hash (0600; `proteus-pin.py` / `check-unlock.py` / `proteus_auth.py`) — not in settings.json; apps install helpers + optional `proteus-lock` PAM (`login` fallback); [CONFIG-SCHEMA.md](./CONFIG-SCHEMA.md) · [INSTALL.md](./INSTALL.md) |
| `~/.config/proteus/hw-probe.json` | Cached Wave A hardware probe |
| `~/.config/proteus/hw.env` | GPU envs from `install/hardware` — sourced by `proteus-session` |
| `~/.config/proteus/session.env` | Optional operator session overrides (after `hw.env`) |
| `~/.config/hypr/proteus-keybinds.conf` | Legacy Hypr binds (unused; Hyprland purged) |
| `~/.config/hypr/proteus-general.conf` | Legacy gaps/borders fragment (unused) |
| `~/.config/hypr/proteus-monitors.conf` | Legacy monitors fragment (unused) |
| `~/.config/hypr/proteus-profile.conf` | Legacy posture profile pointer (unused; `set-hypr-profile` retired) |
| `~/.config/proteus/root` | Install-root Fact — greetd starts `proteus-session` with a clean env, so bare metal cannot rely on `/mnt/proteus`; written by `install/config.sh`, validated before use ([INSTALL.md](./INSTALL.md)) |
| `~/.config/proteus/posture` | Hard-switch Fact (`desktop` \| `console` \| `host`) — boot + chrome when `PROTEUS_SURFACE` unset |
| `~/.config/proteus/host-chrome` | Host seat chrome (`none` \| `full`) — `proteus-posture` / `proteus-host-seat` |
| `~/.config/proteus/displays.json` | Displays layout Fact — loaded at compositor start; Settings Apply + `apply-displays` |
| `env/hypr/` | **Deleted** — Hyprland purged; no archived templates |

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
| `bash /mnt/proteus/install/machine/install-keybinds.sh` | Seed `~/.config/proteus/keybinds.json` (no hypr conf) |
| `bash /mnt/proteus/install/machine/install-desktop-conf.sh` | Soft no-op (Hypr fragments deleted); lock PAM bits may still apply |
| `bash /mnt/proteus/install/machine/install-lock-pam.sh` | `/etc/pam.d/proteus-lock` (falls back to `login` if absent) |
| `./dev/run-nested.sh` | Nested compositor (winit) + iced chrome on host |
| `./dev/smoke-all.sh` | **Desktop spine only** — shellcheck · doc-links · layout · ipc · config-schema · chrome-tokens · shell-core · shell · compositor · owned-dogfood · settings-next · settings-backing · install · install-idempotency · session · guest `owned-guest` (SSH / `PROTEUS_GUEST=1`). Console/host/software-guest deferred |

**In `smoke-all` (desktop):**

| Gate | Role |
|------|------|
| `shellcheck-smoke.sh` | Shell static analysis — gate = severity `error`; SKIPs without `shellcheck` |
| `doc-links-smoke.sh` | Every relative link in tracked `.md` must resolve |
| `layout-smoke.sh` | Owned tree — no QML/`shell-next`/`compositor-next`; faces present |
| `ipc-contract-smoke.sh` | `proteus-shellctl` targets/verbs ⊆ `shell/src/ctl.rs` |
| `config-schema-smoke.sh` | Fixture + CONFIG-SCHEMA ↔ shell-core SoT |
| `chrome-tokens-smoke.sh` | `env/chrome` tokens drift gate |
| `shell-core-smoke.sh` | rung-0 — schema · facts · gate matrix · catalog · `proteus-open` · `serve` |
| `shell-smoke.sh` | iced shell — lib tests · layers · IPC · ctl · owned-only engine |
| `compositor-smoke.sh` | compositor winit (+ portal/screencast/gamescope when available) |
| `shell-owned-dogfood-smoke.sh` | build · headless ctl · PAM unlock · face boot · HUD |
| `settings-next-smoke.sh` | iced Settings sibling; skips if `../ProteusSettings` missing |
| `settings-backing-smoke.sh` | HARD RULE 2 — every hub `backsFacts` / `backsCli` resolves |
| `install-smoke.sh` · `install-idempotency-smoke.sh` | Overlay tree + repair idempotency |
| `session-smoke.sh` | `proteus-session` contract + `proteus.desktop` |
| `owned-guest-smoke.sh` | Guest desktop — owned shell + smithay live |

**Deferred** (scripts remain; not in `smoke-all` until desktop is rock solid):
console / host / posture / workloads / software-guest / QML-era leaf SKIP stubs
(`console-*-smoke`, `host-*-smoke`, `spaces-smoke`, `beacon-smoke`,
`accounts-smoke`, `qs-*-smoke`, …). Run individually when that work resumes.

SSH default: `ssh -p 2222 andrew@127.0.0.1`
Install path SoT (three layers, knobs, repair, failures): [INSTALL.md](./INSTALL.md)

---

## 7. Docs locks (ahead of code)

| Lock | Doc | Code status |
|------|-----|-------------|
| Stack split (iced / Tauri / Rust) | [STACK.md](./STACK.md) | Shell+Settings iced; no first-party Tauri apps yet |
| Owned compositor + chrome | [COMPOSITOR.md](./COMPOSITOR.md) | Desktop smithay+iced `shipped` (thin); console Gamescope session `partial`; host seat-driven `partial`; home parked |
| Posture separation rules | [POSTURES.md](./POSTURES.md) §2a | Shared rules `partial` (gating panes, keybind filter, hard posture, host seat scaffold) |
| Adaptive apps / environment contract | [APPLICATIONS.md](./APPLICATIONS.md) | `partial` — `env/apps` manifests + shell-core gating + Focus / Beacon adapt hints; **remote** via probe + soft stub |
| Hardware module catalog | [HARDWARE.md](./HARDWARE.md) | Wave A probe + shell-core / Settings consumers |
| Capability / posture resolver | [POSTURES.md](./POSTURES.md) | Probe → caps in shell-core; full resolver still thin |
| Chrome language (company reference) | [CHROME.md](./CHROME.md) | `proteus-ui` + `env/chrome/` export `shipped`; Rowena retarget `partial` |
| Facts / Config schema | [FACTS.md](./FACTS.md) · [CONFIG-SCHEMA.md](./CONFIG-SCHEMA.md) | Layout + docs `shipped` |

---

## 8. Not yet

- Host virt auto-resolver · Portainer-style Settings UI · graphical-remote seat attach (thin Virtualization + Workloads + host-chrome / proteus-host-seat shipped)
- Gamescope-as-session console + Guide focus-flip (interim nested session Fact shipped; launcher-first / stores-as-backend locked)
- Soft hypr profile reload (retired with Hyprland — use `proteus-posture`)
- Parked postures (home / wearable / xr / vehicle) before focus three are proven  
- Snap / dependency graphs in Software  

- First-party Tauri app under `apps/`  
- More Rust helper CLIs under `services/` (Wave A probe is Python; `proteus-pkg` + `proteus-logind` mutators + `proteus-audio-mix` resident dump/peaks shipped; mixer mutations still Python)  
- Tablet gesture maps (tip/eraser pressure curves + linear min/max remap shipped thin; active-area mm + eraser-as-button + monitor region Facts remain)  
- ISO / installer productization — bare metal now runs the same overlay against a manual Arch base, but there is no unattended installer for real hardware ([INSTALL.md](./INSTALL.md))
- Bare-metal proof: nothing in the tree has been booted on real hardware yet. `game_scope`, charge thresholds, `/sys/class/backlight`, SMART and multi-head hotplug are all **unexercised** — the VM cannot reach them
- Second user: nothing here has been installed by anyone who did not write it  
- Rowena (and other sibling) CSS retarget onto `--proteus-*` export  

When shipping a feature, update this file in the same change.
