---
doc: settings-ia
role: reference
audience: UI, contributors
last_updated: "2026-08-02"
doc_status: active
scope: Settings control-center categories, backends, hybrid UX pattern
related:
  - ARCHITECTURE.md
  - CURRENT.md
  - CHROME.md
  - POSTURES.md
  - COMPOSITOR.md
  - STACK.md
status_legend:
  shipped: In code today
  partial: UI present; depth remains
  planned: Designed; not in code
---

# Settings — information architecture

**One Facts SoT** (`settings.json`, helpers, Theme). **Three disconnected faces**
per focus posture — same idea, different primary catalog and chrome. Apps and
files are shared; Settings **faces** are not one skin.

| Face | Surface | Primary catalog |
|------|---------|-----------------|
| **Desktop** | `proteus-settings` app (pointer, full IA) | Full `settingsCatalog` |
| **Console** | In-chrome `ConsoleSettingsPane` (pad) | `settingsFaceHubs("console")` — living-room + shared core |
| **Host** | HostShell / Workloads + Settings deep links (ops) | `settingsFaceHubs("host")` — virt + shared core |

Shell ⚙ / dock / `Super+,` launch the **desktop face**. Console/host default
paths use `ShellState.openSettingsSmart` / `openConsoleSettings` — not the
desktop app for ordinary jobs. Escape: “Open in Full Settings…” → desktop face.

**Shared core hubs** (all faces when capability-ok): Network, Sound, Power,
Notifications, Software (`packages`), About (`system`), Users.

**Face-only emphasis:** Desktop → Desktop hub / Style depth / Privacy / Accounts /
Datetime / CC layout. Console → Appearance light, Displays/brightness, Gamepads,
Web apps leaf, session. Host → Virtualization / seat chrome, updates/ops.

**Console couch depth (Network · Sound):** Hub status strip + drill modes
(`hub` · `wifi` · `sinks` · `wifiPassword`). Wi‑Fi rescan/list/connect via
`ConsoleSettingsNet` + `Config.wifiConnect` / `wifiConnectPassword` /
`wifiDisconnect` (nmcli; secured SSIDs → password `TextField`). Sound volume /
mute stay on hub; **Choose output…** → `Audio.listSinks` / `setDefaultSink`.
Ⓑ / Back exits drill before leaving Settings. Software install UI · captive
portals · on-screen keyboard stay Out (Full Settings escape for deep leaves).

Code: `apps/proteus-settings/` (`Settings.qml` shell + `kit/*` form primitives +
`panes/*`; `SettingsNav.qml`; `shared/` → `shell/shared`). Face hub lists:
`EnvGate.settingsFaceHubs` / `availableSettingsPanesForFace`.

## Document map

| Section | Contents |
|---------|----------|
| [Posture faces](#posture-faces) | Shared Facts · three faces · escape |
| [1. Pattern](#1-pattern) | Elegant UI → inspectable fact |
| [2. Categories](#2-categories) | Sidebar IA (desktop face) |
| [3. Containers](#3-containers) | Top-level vs submenu vs sections |
| [4. Appearance hub](#4-appearance-hub) | Drill-in |
| [5. Keyboard pattern](#5-keyboard-pattern) | Prototype hybrid feature |
| [6. Desktop + Displays](#6-desktop--displays) | Same hybrid pattern (+ Sound · Network) |
| [7. Growth](#7-growth) | Next panes |
| [8. UX locks](#8-ux-locks) | Calm chrome |

---

## Posture faces

Do **not** fork `settings.json` per posture. Do **not** ship three Settings apps.
Do disconnect **primary navigation** and **input grammar**:

- Legality stays `EnvGate.paneAvailable` (posture + hardware + Focus).
- Face lists are **emphasis** — what Console/Host Settings home shows first.
- Desktop face remains the deep editor; console/host escape into it when needed.

### What "face" means here — and where each one lives

A face is a **renderer plus a navigation emphasis**, not an app. One catalog
(`EnvGate.settingsFaceHubs(posture)`) is the SoT; today two renderers serve the
three faces:

| Face | Renderer | Lives in | Hubs |
|------|----------|----------|------|
| desktop | `proteus-settings`, full IA | `apps/proteus-settings/` | whole catalog |
| console | `ConsoleSettingsPane` + `ConsoleSettingsNet` — in-chrome, pad-first | `shell/surfaces/console/` | 10, then **Full Settings** escapes to the desktop face |
| host | `proteus-settings` filtered, reached via `openSettingsSmart` | `apps/proteus-settings/` | 9; mutations live in `proteus-workloads` |

Console renders its own surface because the posture is one fullscreen app with a
pad grammar — that is a **second renderer**, not a second Settings app, and it is
why the ban above still holds. Host is the asymmetric one: config comes from the
desktop app while mutations come from Workloads.

> **Open decision.** Whether host should absorb its config face into
> `proteus-workloads` (one app per posture) is unresolved. It brushes against the
> "no three Settings apps" rule above and should be decided deliberately rather
> than drifted into — and not before host has actually been dogfooded.

Shared vocabulary lives in `shell/shared/kit/`, reachable from every renderer.
It moved out of `apps/proteus-settings/kit/` precisely because the console face
sits under `shell/` and could not import across into `apps/`.

---

## 1. Pattern

```
Settings control  →  ~/.config/… or helper CLI  →  daemon/compositor apply
```

Examples:

| Control | Fact |
|---------|------|
| Accent / wallpaper / lock / font | `settings.json` + Theme + **Background.qml** / **proteus-bg** (`shell/wallpaper`); Qt FileDialog/FolderDialog in Settings |
| Gaps / borders / rounding / animations | json + `hyprctl` + `~/.config/hypr/proteus-general.conf` |
| Keyboard shortcuts | `~/.config/proteus/keybinds.json` + `~/.config/hypr/proteus-keybinds.conf` |
| Mouse sensitivity / accel | json + `hyprctl` input:* (+ general conf `input` block) |
| Displays (list) | `hyprctl monitors -j` (name-merge on refresh; add/remove status) |
| Displays scale / mode / orientation / layout | `hyprctl keyword monitor` + `proteus-monitors.conf` (recommended modes; confirm large jumps; 10s full-snapshot Revert keyed by connector; drift/hotplug cancel; Identify flash; drag layout canvas) |
| Volume / mute / default sink | `pactl` |
| Input volume / mute / default source | `pactl` |
| Audio matrix (node routing) | `pw-link` via `shell/scripts/audio-matrix.py` (Omnibus-style grid) |
| App mixer (Wave Link–style) | Channels (default Apps/…) + mic/line inputs × mixes; Speakers/mix listen; rename; peaks; drag-reorder; × confirm; graph escape (`qpwgraph`, Install… → Repos); `~/.config/proteus/audio-mix.json`; resident `proteus-audio-mix serve`; mutations `audio-mix.py`; **CC Sound plate** |
| Input level meter | streaming `audio-peak.py` on default source (Settings Input leaf) |
| Per-app volume / mute | `pactl list/set-sink-input-*` |
| Sound latency / buffer | `settings.json` `audioLatency` → `pw-metadata -n settings 0 clock.force-quantum` (256 / 512 / 1024) |
| Network (open editor) | NetworkManager UI / `nmtui` |
| Wi‑Fi connect / disconnect / password | `nmcli device wifi` (secured SSIDs prompt in Settings; password never in settings.json) |
| Hostname | `hostnamectl` (polkit-gated set) |
| Bluetooth (power · scan · pair/connect) | `bluetoothctl` · blueman escape for advanced |
| VPN profiles (list · up/down · WG / OpenVPN import · cert path attach) | `nmcli connection` up/down · `import type wireguard|openvpn` · optional user/pass + CA/cert/key `+vpn.data` (session-only) |
| LocalSend (status + open / start / stop) | `localsend` · port 53317 |
| Tailscale (status · peers · exit-node · login-server) | `tailscale status --json` · `set --exit-node` · `up --login-server` · `wl-copy` |
| Network diagnostics (iface rates · ss · firewall · route · DNS · ping) | `/proc/net/dev` · `ss -tun/-tln` · firewalld/ufw/`nft` · `/proc/net/route` · `resolv.conf` · `ping` |
| Packet capture escape | Wireshark Open / Install… → Repos · `wireshark-qt` (Flatpak still Opens if present) |
| Package updates / search / remove / orphans | `pacman -Qu` / `-Ss` / `-Qqe` / `-Qdt` · apply `pkexec proteus-pkg` (multi install/remove; selective upgrades) |
| AUR search / install / remove / update | `yay`/`paru` `-Ssa` · remove via `-Qqm` foreign pkgs · multi-select |
| Flatpak / Flathub search / list / install / remove / update | `flatpak --user` · Flathub remote · Install\|Installed (mode-safe; empty honesty) · multi-select + live Cancel |
| Package picker chrome | `kit/PackagesPickerRow` · `PackagesActionBar` · `PackagesOpProgress` (exact `$` command + last error) |
| AppImages library | `~/.local/share/proteus/appimages` + `proteus-appimage-*.desktop` |
| Web apps | `proteus-webapp` → `~/.local/share/applications/proteus-web-*.desktop` (Chromium `--app` / Firefox kiosk) |
| Timezone / network time | `timedatectl set-timezone` / `set-ntp` (polkit-gated; errors surfaced in-pane) |
| Locale | `localectl list-locales` / `set-locale LANG=…` (polkit-gated; stderr in-pane) + `/etc/locale.conf` escape |
| Location | Explicit place search → precise lat/lon + place timezone in `settings.json` (**never IP-inferred**); Open-Meteo geocoding; optional Match time zone to place |
| Weather | `api.open-meteo.com` current + 5-day daily forecast for the stored location — no API key; only those coordinates are sent; mute via `weatherEnabled` (Privacy & security); Location category Deny also mutes fetch |
| App permissions | Category + per-app Allow/Ask/Deny in `permissions.json`; Flatpak mic/camera overrides; EnvGate `permissions` on manifests |
| Battery charge / health / estimate | UPower display device (`Quickshell.Services.UPower`) |
| Power mode (Performance / Balanced / Eco) | `powerprofilesctl` → `power-profiles-daemon` (`power-saver` labeled Eco); only profiles the driver advertises |
| Idle / lid policy | `pkexec proteus-logind` → `/etc/systemd/logind.conf.d/99-proteus.conf` (+ **reload** logind — never restart, which drops the seat); effective merge with main conf; escape hatch still opens `logind.conf` |

Power escape hatch: always allow opening or editing the underlying file when
one exists (Keyboard / Desktop / Displays → “Edit … conf”). Prefer Quickshell
built-ins before new daemons; use Rust helpers for messy IO —
[COMPOSITOR.md](./COMPOSITOR.md) / [STACK.md](./STACK.md).

---

## 2. Categories

Left-nav + content pane (macOS System Settings style).

**North-star sidebar order** (stable page IDs in parentheses where shipped):

| Category | Holds | Backend | Status |
|----------|-------|---------|--------|
| **Appearance** (`style`) | Category → Accent, Background, Lock screen, Icons (style compare + dock pins), Font (searchable + Add) | `settings.json`, Theme, `proteus-bg`; shared Kind/color/font/icon kit | `shipped` |
| **Desktop** (`desktop`) | Category → Gaps, Borders & rounding, Motion, Dock & menu bar, Spaces, Default apps, **Focus**, **Control Center** layout, Beacon | json + hypr · FocusMode · ControlCenterLayout · `proteus-defaults.py` · launcher* | `shipped` |
| **Displays** (`displays`) | Layout canvas + per-monitor scale/mode/orientation; 10s Revert; Refresh/hotplug honesty; conf escape | hyprctl + `proteus-monitors.conf` | `shipped` |
| **Sound** (`sound`) | Category → Output / Input / Applications / Mixer / Latency — leaf files + FormRow kit | pactl + `proteus-audio-mix` / `audio-peak.py` + `pw-metadata` + `pw-link` | `shipped` |
| **Network** (`network`) | Category → This machine / Devices / Diagnostics / Wi‑Fi / Bluetooth / LocalSend / Tailscale / VPN / Headscale — password Wi‑Fi · BT pair · TS peers/exit/login-server · VPN up/down · WG/OpenVPN import · Headscale admin thin (nodes · users · policy text) | hostnamectl / nmcli / bluetoothctl / localsend / tailscale / `proteus-headscale.py` / `NetworkDiagnostics` | `shipped` |
| **Peripherals** (`peripherals`) | Category → Keyboard, Mouse, Touchpad, Tablet, Gamepads (Guide Facts) | keybinds + input hyprctl (`mouse*` · `touchpad*` · `tablet*` · active-area/pressure/eraser · `inputDeviceOverrides` → `device {}`) + `gamepadsGuide*` | `shipped` |
| **Power** (`power`) | Power mode segmented (PPD); battery (UPower); **Charge limits** (sysfs `charge_control_*` when present); idle / lid FormRows via `proteus-logind` drop-in + conf escape | `powerprofilesctl` / UPower / `proteus-logind` / `proteus-battery-threshold` | `shipped` |
| **Users** (`users`) | Session Lock/Logout + confirm Reboot/Shutdown; lock screen PIN set/change/clear; current user (GECOS/home) + other local users read-only; Online accounts jump; greetd status + autologin write + conf escape | `Config.session` · `proteus-pin.py` · id/getent · `proteus-greetd` (pkexec `[initial_session]`) | `shipped` |
| **Online accounts** (`accounts`) | Hub → per-provider leaves (Google / Microsoft / Exchange / Nextcloud / IMAP / CalDAV / CardDAV / Apple); PKCE + app-password seats (`proteus-accounts` vault); calendar + mail + contacts glances; **calendar event create/edit/delete** (CalDAV + Google/MS/Exchange · CalendarPanel); **recurrence thin create+edit** (daily/weekly/monthly · COUNT end Forever/2×/5×/10×); **mail compose thin** (Google/MS/Exchange + IMAP/Apple SMTP · To/Cc/Bcc/Subject/Body · one-file attach); **contacts create/edit/delete thin** (CardDAV + Apple + Google/MS/Exchange · name + email) | `proteus-accounts` + `Accounts.qml` + `AccountsPane` / `AccountsProviderLeaf` + `CalendarEvents` / mutate · `MailGlance` / send · `ContactsGlance` / mutate (HTML/drafts/multi-file · photos/groups/apps Out) | `partial` |
| **Date, time & weather** (`datetime`) | Live clock, searchable timezone + locale pickers, NTP, **Location** (place + units + 5-day forecast + Match TZ) | `timedatectl` / `localectl set-locale` / Open-Meteo | `shipped` |
| **Notifications** (`notifications`) | Prefs: hard DND · jump to Focus · live list stays Control Center | `notificationsDnd` · FocusMode | `shipped` |
| **Privacy & security** (`privacy`) | Hub → What leaves + weather mute + session; **In use now**; category leaves (Allow/Deny + per-app Allow/Ask/Deny); Flatpak overrides; portal PermissionStore sync; capture enforce (Deny + Ask mute/destroy mic/camera/**screen**); **portal Session.Close** best-effort; **Ask launch + mid-session mic/camera/screen** | `permissions.json` · `proteus-permissions.py` · PrivacyAsk · PrivacyIndicators · EnvGate · portal Session.Close + pactl/PW enforce | `partial` |
| **Software** (`packages`) | Hub → Updates; Repos / AUR / Flathub (Install\|Installed mode-safe, per-mode search, op narrative); AppImages; **Web apps** (URL → `proteus-web-*.desktop` via `proteus-webapp`, no polkit); Orphans — helper honesty when yay/paru/flatpak missing | `pacman` + `proteus-pkg` · yay/paru · flatpak + Flathub · local AppImages · `proteus-webapp` | `shipped` |
| **Virtualization** (`virtualization`) | Thin host ops hub — Workloads › jump · engines status · **seat chrome** (`proteus-host-seat` attach/detach · `host-chrome`) | `Workloads` · `proteus-host-seat` · `proteus-posture` · `host-chrome` (mutations / auto-resolver / Portainer / graphical-remote Out) | `shipped` |
| **About** (`system`) | OS/kernel/hostname · QS/Hypr · load/mem/storage · battery when present · Mission Center (Install… → Flathub · `io.missioncenter.MissionCenter`) · Check for updates → Software; hardware caps; **hard Session posture** (`SessionPosture` → `proteus-posture`, confirm); soft Hyprland profile under **Advanced · window rules** (`HyprProfile`); Copy + Copied; Virtualization › jump | `SystemInfo` · `SystemLoad` · `MissionCenter` · `Power` · probe · `SessionPosture` · `HyprProfile` | `shipped` |

VM / container **mutations** stay in the Workloads app; Settings → Virtualization
is jumps + engine/headless status only. Soft Hyprland profile (Advanced) does **not**
flip hard posture — use Session posture (or Beacon / CC / `proteus-posture`).
Hostname **edit** stays under Network.

Panes live under `apps/proteus-settings/panes/`. EnvGate capability-gates
sidebar entries (`display` for Desktop / Displays / Keyboard, audio/network
caps for Sound / Network).

---

## 3. Containers

| Container | When |
|-----------|------|
| **Top-level sidebar** | Flat list of jobs — click jumps to that category page |
| **Category page** | Heading = category; body = sub-settings list (› rows) |
| **Leaf page** | One control; **‹ Category** / Esc returns to the list |

Navigation API (`SettingsNav`): `go(id)` in, `back()` out, `goSection(id)` from sidebar,
`canGoBack` / `backLabel` for the header button. Category panes load via
`kit/StickyPaneLoader` (compile on first visit, keep alive after).

---

## 4. Appearance hub

Click **Appearance** in the sidebar → content heading is **Appearance**, body is
the sub-settings list:

| Sub-setting | Role |
|-------------|------|
| Accent & chrome | Presets + custom hex + **HSV color graph** (`kit/ColorGraphPicker`, debounced commit / coalesced settings+hypr); **Dark / Light** (`kit/SettingsSegmented`); **Opacity** (0% clear · 100% solid, live — bar uses clearer `menuBarAlpha`, dock richer `glassAlpha`) + **Blur** (frosted bar/dock/Beacon; debounced Hypr apply) |
| Background | Kind hub (`kit/SettingsKindPicker`): Color (`kit/SettingsColorPresetGroup` + graph) · Image (built-in stock + albums/slideshow; empty-album honesty; Missing thumb overlay) · Daily · Video · Animated. Applied by **`proteus-bg`** (Hypr `exec-once`) |
| Lock screen | Same Kind/color kit as Background + dim; Match desktop; **widgets only via lock Customize** (long-press) — not in Settings |
| Icons | **Default / Dark / Clear / Tinted** side-by-side squircle compare (`kit/SettingsIconStylePicker`); Tinted tint graph; custom art Switch/Reset; dock Keep/Remove via glass right-click menu + long-press edit (−) / drag-off (running apps appear on dock) |
| Desktop widgets | **Not in Settings** — unlocked desktop long-press or `Super+Shift+W` → Customize (Theme elevated bar · empty-hint honesty · size/− chrome); free place + optional Snap to Grid; separate `desktopWidgets[]`; store Out |
| Notifications / DND | **Live list** stays **Shell Control Center** (top-bar status cluster) — toast/`showToast` · DND · QS volume/tiles; Network tile → **Settings → Network**; Status HUD for media-key volume/brightness (suppressed while CC open). **Prefs** live in top-level **Settings → Notifications** (`notifications` · hard DND · jump to Focus); deep Sound/Network/Power stay in Settings panes |
| Mix (inputs) | **Shell Control Center** unified **Sound** plate — master volume on plate; Listen ▾ + Sources ▾ (name · On/Off · peak · volume); Mixer › → Settings |
| Keep Awake | **Shell Control Center** duration menu (+ menu-bar **Awake** when on; Beacon Actions) — temporary `systemd-inhibit idle:sleep` so hypridle/logind skip idle lock & sleep; **not** a Settings Power control |
| Power mode | **Settings → Power** segmented + Control Center **Power** tile menu — `powerprofilesctl` (Performance / Balanced / Eco) |
| LocalSend | **Settings → Network → LocalSend** + Control Center tile **menu** (start/stop · open · copy `ip:53317` · settings) + Beacon — install honesty when missing |
| Font | Searchable system/user list (`kit/SettingsFontPicker`); **Add font…** user-scoped install (`~/.local/share/fonts/proteus` · `userFonts`); size slider; live Aa preview |

Open a row → leaf controls; **‹ Appearance** / Esc returns to the list. Desktop
uses the same pattern. Pane visibility is owned by `Settings.qml` (only one
category visible at a time). Page id remains `style` / `style-*`.

**Module rule:** Appearance helpers (`ColorGraphPicker`, Kind/color/font/icon
pickers, segmented chrome) live in `kit/` (or `shell/shared`) — not bare
`panes/` types without a qmldir.
---

## 5. Keyboard pattern

Reference hybrid leaf under **Peripherals → Keyboard**:

1. Friendly catalog in `shell/shared/Keybinds.qml`
2. Overrides in `~/.config/proteus/keybinds.json`
3. Generated `~/.config/hypr/proteus-keybinds.conf` sourced by Hyprland
4. UI: search, categories, record chord, conflict detection, restore defaults
5. Guest wiring: `install/machine/install-keybinds.sh`

**Peripherals** category (same drill-in as Appearance): Keyboard · Mouse ·
Touchpad · Tablet · Gamepads. Headphones/speakers stay under **Sound**, not
Peripherals. Touchpad/tablet Facts live in `settings.json` and apply via
`hyprctl input:touchpad:*` / `input:tablet:*` / `input:tablettool:*` +
`proteus-general.conf`. Per-device `device {}` (sensitivity + accel via
`inputDeviceOverrides` on Mouse) and tablet active-area mm + pressure range
(global linear) + eraser-as-button + monitor region map are In; bezier
per-tool curves and gesture maps stay Out.

Defaults include Beacon (`Super+Space` / `Super+D`), Settings (`Super+,`),
terminal, workspaces, etc. (`env/hypr/proteus-keybinds.conf` template).

---

## 6. Desktop + Displays

Desktop: click sidebar → heading **Desktop** + sub-settings list, then leaf
pages via `kit/StickyPaneLoader` (`DesktopGapsLeaf`, `DesktopChromeLeaf`,
`DesktopMotionLeaf`, `DesktopDockLeaf`, `DesktopSpacesLeaf`, `DesktopDefaultsLeaf`,
`DesktopFocusLeaf`, `DesktopControlCenterLeaf`, `DesktopLauncherLeaf`).

| Sub-setting | Role |
|-------------|------|
| Gaps | Inner/outer `SettingsFormRow` sliders; live hypr |
| Borders & rounding | Border size + window rounding FormRows; live hypr |
| Motion | Window animations switch |
| Dock & menu bar | Show/hide/monitor/size FormRows; Advanced → `proteus-general.conf` |
| Spaces | Displays share Spaces (`workspaceMode` synced \| perDisplay); **Named Spaces** (`workspaceNames`); Super+**1–10** logical (+ Super+Ctrl local · Super+Shift move); strip drag `workspaceOrder` + wheel; **Scratchpad** Super+S / Super+Alt+S + strip ◇ pill (`special:scratch` ≠ dock minimize); **custom specials** (`specialWorkspaces` CRUD · strip pills ≤8 · Super+Alt+1–8 / Super+Alt+Shift+1–8 index + optional per-slug toggle + move chords); bands via `proteus-workspace`; multi-head `status`/`ensure` + disconnect `migrate-disconnect`; spaces-smoke |
| Default apps | Browser / Files / Images / Music / Video / PDF / Text / Archives / Mail / Calendar via `proteus-defaults.py` + `xdg-mime`; mimeapps.list escape |
| Focus | Soft quiet profiles (seed Work/Sleep/Personal + **add/rename/delete**); allowlist · keywords · schedule · critical; combo picker when >3; CC menu + Desktop → Focus leaf |
| Control Center | Plates + tile visibility/size/span/order + **columns 2\|3** + reset (`ControlCenterLayout`); Settings → Desktop → Control Center |
| Beacon | Universal Apps (+ Windows · Privacy · **focus-cycle** Action); Files index (`beacon-file-index`); Clipboard `wtype`; tags / clear recents |

| Pane | Live apply | On-disk fragment | Guest seed |
|------|------------|------------------|----------|
| Desktop | `hyprctl keyword` (gaps, border, rounding, animations) + dock/menu sizes + Beacon tags/recents in `settings.json` | `proteus-general.conf` + `settings.json` (`launcherRecents`, `launcherFileRecents`, `launcherTagCatalog`, `launcherAppTags`) | `install/machine/install-desktop-conf.sh` |
| Displays | Scale + mode + orientation + layout via `hyprctl keyword monitor`; Revert snapshot; Refresh/hotplug rebind | Live `monitor =` lines in `proteus-monitors.conf` | same |

Templates: `env/hypr/proteus-general.conf`, `env/hypr/proteus-monitors.conf`. Nested
`env/hypr/hyprland.conf` sources both plus keybinds.

**Module rule:** Desktop leaf helpers stay in `panes/Desktop*Leaf.qml` + `kit/`
FormRow/Group — not a single mega-inline `DesktopPane` body.

### Displays

Displays: single pane `DisplaysPane.qml` (layout canvas + per-monitor FormRows).
Not a leaf-split hub — follow-ups closed Revert honesty after Refresh / sleep /
hotplug without redesigning the canvas.

| Concern | Role |
|---------|------|
| Layout canvas | Drag + edge snap; Apply layout |
| Modes / scale / orientation | Per-connector FormRows; Identify flash |
| Revert | 10s full-snapshot; connector-name key; cancel on Refresh, re-entry, topology drift, or monitor events |
| List honesty | `adoptMonitorList` merges by name; keeps dirty drafts; add/remove status |
| Escape | Edit `proteus-monitors.conf` |

**Module rule:** Keep Displays logic in `DisplaysPane.qml` + `shell/shared/Displays.qml`
— no second conf store.

### Sound

Sound: click sidebar → heading **Sound** + sub-settings list, then leaf pages
via `kit/StickyPaneLoader` (`SoundOutputLeaf`, `SoundInputLeaf`,
`SoundAppsLeaf`, `SoundMatrixLeaf` (Mixer), `SoundLatencyLeaf`). Hub state lives
in `SoundPane.qml`
(`property Item host` on leaves).

| Sub-setting | Role |
|-------------|------|
| Output | Volume/mute FormRows + live hints; test tone; sink list with `deviceHint` |
| Input | Level/mute FormRows; peak meter FormRow; source list with `deviceHint` |
| Applications | Per-app volume + mute; empty Playing now honesty |
| Mixer | Wave Link–style grid: channels/inputs × mixes; Speakers vs mix listen; Level; rename (dbl-click); instant expand/listen; slideVol while dragging; row peaks; drag-reorder; add channel/input/mix; × confirm; graph editor escape (`qpwgraph`, Install… → Repos). Quick per-source adjust also in Control Center Sources ▾ |
| Latency & buffer | Profile segmented + quantum frames; PipeWire clock summary when known |

| Pane | Live apply | On-disk / helper |
|------|------------|------------------|
| Sound | `pactl` volume/mute/default sink·source · sink-input volume/mute · test tone · matrix link/unlink · mixer routes | `settings.json` `audioLatency` → `pw-metadata`; Mixer dump+peaks via resident `proteus-audio-mix serve` (Python `audio-mix.py` / `audio-mix-peaks.py` fallback); matrix via `audio-matrix.py` → `pw-link`; mutations via `audio-mix.py` |

**Module rule:** Sound leaf helpers stay in `panes/Sound*Leaf.qml` + `kit/`
FormRow/Group — not a single mega-inline `SoundPane` body.

### Network

Network: click sidebar → heading **Network** + sub-settings list, then leaf pages
via `kit/StickyPaneLoader` (`NetworkMachineLeaf`, `NetworkDevicesLeaf`,
`NetworkDiagnosticsLeaf`, `NetworkWifiLeaf`, `NetworkBluetoothLeaf`,
`NetworkLocalSendLeaf`, `NetworkTailscaleLeaf`, `NetworkVpnLeaf`). Hub state
lives in `NetworkPane.qml` (`property Item host` on leaves; LocalSend /
Diagnostics use shared singletons).

| Sub-setting | Role |
|-------------|------|
| This machine | Hostname draft + Apply (`hostnamectl`); Refresh all |
| Devices | nmcli interfaces with type · state · IPv4 · connection hints |
| Diagnostics | Iface rx/tx + calm rate bars; active connections / listening (`ss`); firewall one-liner; route/DNS; ping; Wireshark Open / Install… → Repos seeded |
| Wi‑Fi | Scan/connect/disconnect; secured SSIDs → in-pane password; Rescan |
| Bluetooth | Power · Scan · pair/connect/disconnect/forget; Install… → Repos seeded `blueman` when missing; blueman escape |
| LocalSend | Install… → AUR seeded `localsend-bin`; Start/Stop / Open / copy address; CC menu + Beacon |
| Tailscale | Status / IP / peers / exit-node / login-server; Install… → Repos seeded `tailscale`; up·down·login |
| VPN | Profile Connect/Disconnect; WireGuard + OpenVPN `.ovpn` import; optional user/pass + cert path attach; NetworkManager escape for PKCS#11 / advanced |
| Headscale | Remote admin URL + vault API key; node list; expire/enable; users list/create; policy HuJSON check/save (db mode); Open admin UI; does not run Headscale locally |

| Pane | Live apply | On-disk / helper |
|------|------------|------------------|
| Network | `hostnamectl` · `nmcli` wifi/VPN/WG/OpenVPN · `bluetoothctl` · `tailscale` up/down/set/login-server · `proteus-headscale.py` · clipboard IP | Escape: blueman / NetworkManager / Wireshark / browser admin — OpenVPN PKI/PKCS#11 · Headscale preauth/structured ACL · in-pane capture Out |

**Module rule:** Network leaf helpers stay in `panes/Network*Leaf.qml` + `kit/`
FormRow/Group — not a single mega-inline `NetworkPane` body.

### Software

Software: click sidebar → heading **Software** + sub-settings list, then leaf
pages via `kit/StickyPaneLoader` (`PackagesUpdatesPane`, `PackagesSearchPane`,
`PackagesAurPane`, `PackagesFlatpakPane`, `PackagesAppImagesPane`,
`PackagesWebAppsPane`, `PackagesOrphansPane`). Hub: `PackagesPane.qml`. Shared
mutators / browse: `shell/shared/Packages.qml` + `pkexec proteus-pkg`. Kit:
`PackagesPickerRow`, `PackagesActionBar`, `PackagesOpProgress`, `PackagesConfirm`.

| Sub-setting | Role |
|-------------|------|
| Updates | `pacman -Qu` list; Sync DB / selective or full upgrade; empty = up to date + Full upgrade… |
| Repos | Install\|Installed mode-safe search; popular browse; leafUi memory |
| AUR | Same pattern via `yay` **or** `paru`; hub “Needs yay/paru” when missing |
| Flathub | Same pattern via `flatpak`; hub Needs flatpak / Add Flathub remote |
| AppImages | User library `~/.local/share/proteus/appimages`; no polkit; empty honesty |
| Web apps | URL → `~/.local/share/applications/proteus-web-*.desktop` via `proteus-webapp`; no polkit |
| Orphans | `pacman -Qdt` list; remove via `proteus-pkg orphans`; empty honesty |

**Smoke matrix:** host `./dev/smoke/software-reliability-smoke.sh` (hub + leaves +
Web apps); guest `./dev/smoke/software-guest-smoke.sh` in `smoke-all` (SKIP unless SSH /
`PROTEUS_GUEST=1`). **Out:** Snap; dependency graphs.

**Module rule:** Software leaf helpers stay in `panes/Packages*Pane.qml` + `kit/`
— not a single mega-inline hub body.

---

## 7. Growth

**Appearance** hub + five leaves shipped (mega-page merge Out). **Date, time & weather**
locale set + 5-day forecast + Match TZ shipped; manual time / RTC writers Out.
**Power** mode (PPD) + logind writer + sysfs charge limits shipped; TLP stays Out.

**Online accounts** seats are `partial` — Settings **hub → per-provider leaves**
(Connected / Add account; canonical blurbs; OAuth Connect inline; multi-seat
Disconnect + Reconnect) + Google/Microsoft/Exchange PKCE + Nextcloud
app-password + IMAP + CalDAV + CardDAV + Apple (Apple ID + app-specific
password) when configured; **calendar + mail + contacts glances** (menu-bar)
consume seats; CardDAV/Apple + Google/MS/Exchange **contacts write thin** (name + email) In
(reconnect older OAuth seats for contacts scopes);
mail/contacts/Drive **apps**, photos/groups, Sign in
with Apple OAuth, and EWS/NTLM stay Out.
**Privacy & security** ships transparency + weather mute + session + **permissions
store** (adaptive EnvGate + Flatpak overrides; native capture observed, not
sandboxed). **Users** session/greeter status shipped (add-remove + writing greeter
prefs stay Out).

Depth order for what’s left:

1. ~~Users depth~~ — greetd autologin write via `proteus-greetd` shipped; add-remove stays Out of Settings  
2. ~~Online accounts depth~~ — hub → provider leaves + Microsoft / Exchange / Nextcloud / IMAP / CalDAV / CardDAV / Apple (app-specific password) connect shipped; ~~calendar + mail + contacts glances~~ + ~~CalDAV + Google/MS/Exchange create/edit/delete~~ + ~~mail compose thin~~ + ~~one-file attach~~ + ~~recurrence thin create+edit + COUNT end~~ + ~~CardDAV + Google/MS/Exchange contacts write thin~~ shipped; HTML/drafts/reply/multi-file · UNTIL date · this-vs-all · photos/groups · EWS/NTLM + Sign in with Apple OAuth + mail/contacts apps Out  
3. ~~**Privacy native enforcement**~~ — portal PermissionStore sync + capture enforce (Deny + Ask) mic/camera/**screen** shipped; ~~**Ask UI**~~ launch + mid-session mic/camera/screen prompt shipped; ~~**fail-closed until ready**~~ shipped; ~~**kill screencast streams**~~ best-effort PW destroy shipped; ~~**portal Session.Close**~~ best-effort shipped; full OS sandbox / v4l2 ACL / perfect screencast attribution Out  
4. ~~**Network polish**~~ — largely shipped (IPv4 on Devices · Diagnostics ss/firewall · OpenVPN `.ovpn` import + cert path attach · Headscale admin thin + users/policy text); OpenVPN PKI/PKCS#11 · Headscale preauth/structured ACL stay Out  
5. ~~**Peripherals** — touchpad / tablet / per-device `device {}` / active-area / pressure / region / eraser~~ — Touchpad + Tablet + Mouse per-device sensitivity/accel + active-area mm + pressure range + eraser-as-button + monitor region shipped; bezier per-tool curves / gestures Out  
6. **Software depth** — dependency graphs later; Snap stays Out (hub + six leaves + smoke matrix shipped)  
7. ~~Settings Notifications pane~~ — shipped (prefs-only; CC remains live list)  

*(Displays layout + Revert follow-ups shipped — removed from growth depth.)*
*(Network hub + FormRow polish shipped — depth wizards stay on the list.)*
*(Network Diagnostics · Wireshark escape shipped — in-pane capture Out.)*
*(Network depth: password Wi‑Fi · BT pair · TS peers/exit/login-server · VPN up/down · WG + OpenVPN import + cert path attach · Headscale admin thin + users list/create + policy HuJSON shipped — OpenVPN PKI/PKCS#11 · Headscale preauth/structured ACL Out.)*
*(Control Center notifications + QS depth shipped — Settings Notifications prefs pane shipped; live list stays CC.)*
*(Users session + greetd status shipped — writing greeter prefs / useradd stay Out.)*
*(Users depth: proteus-greetd pkexec `[initial_session]` autologin toggle + users-smoke
shipped — greetd restart mid-session · tuigreet theme · useradd stay Out.)*
*(Users polish: Reboot/Shutdown confirm · GECOS/home · Online accounts jump · lock screen PIN shipped.)*
*(Lock PIN catch-up: apps/check harness · lock-pin-smoke install/PAM source ·
INSTALL/FACTS honesty shipped — biometrics · greetd PIN · require proteus-lock
PAM · PIN in settings.json Out.)*
*(Power mode PPD + logind writer + sysfs charge limits shipped — TLP stays Out.)*
*(Software hub + six leaves + reliability/guest smoke shipped — dep graphs / Snap stay Out.)*
*(Appearance hub + Date, time & weather locale/forecast shipped — manual time/RTC Out.)*
*(About OS/kernel/hostname · load strip · Mission Center escape · Copy+Copied ·
hard Session posture picker + soft Hyprland profile under Advanced · window rules
shipped — Beacon/CC still flip hard too; no in-Settings live dashboard.)*
*(Privacy & security hub · In use now · category grants · Flatpak overrides ·
portal PermissionStore sync · capture enforce (mic/camera/screen) · Beacon/dock
grant parity · Diagnostics deny → Network Diagnostics · smoke/install privacy
harness shipped — ~~Ask launch prompt~~ · ~~fail-closed until Permissions.ready~~
· ~~kill screencast streams (best-effort)~~ · ~~portal Session.Close (best-effort)~~
shipped; full OS sandbox / v4l2 ACL / perfect screencast attribution still Out.)*
*(Desktop catch-up: desktop-smoke · defaults/beacon-index install · Focus/CC/Spaces
roundtrip · guest Desktop nav · Beacon Settings blurb · SETTINGS-IA §6 Focus/CC
rows shipped.)*
*(Spaces catch-up + multi-head + Named Spaces + keyboard 1–10 + disconnect
migration + strip drag: spaces-smoke · band selftest · status/migrate fixtures ·
ensure/`apply-names`/`migrate-disconnect` · `workspaceOrder` · SpacesNames ·
Super+1–10 logical SoT + Scratchpad (keys + strip ◇ pill) + custom special CRUD
+ strip pills / Super+Alt+1–4 (`specialWorkspaces`) shipped; Spaces row stays
`partial` until live 2-head is routine.)*
*(Focus profile CRUD: FocusMode add/rename/delete · DesktopFocusLeaf UI · combo
at >3 · focus-smoke · CONFIG-SCHEMA profile object shipped — duplicate/reorder /
CC inline CRUD Out.)*
*(CC columns UI: ControlCenterLayout.setColumns · Settings Layout segmented 2|3 ·
control-center-smoke · roundtrip columns shipped — panel width scaling · CC
inline Customize · per-monitor columns Out.)*
*(Beacon catch-up: beacon-smoke · index rebuild/search · FACTS cache path ·
INSTALL helper honesty shipped — full-text content index · require fd/wtype ·
Spotlight-class relevance Out.)*

Virt / container **mutations** stay in Workloads; Settings Virtualization hub is
jumps/status only (auto-resolver / Portainer Out).

---

## 8. UX locks

Canonical chrome language (tokens + patterns): [CHROME.md](./CHROME.md)
(`Theme.qml` is the live binding).

- Calm chrome: discoverability without permanent label clutter  
- Accent = selection/action only  
- Legibility floor: prefs must not produce unreadable UI  
- Settings visual language: modern System Settings (grouped lists, soft selection, large titles)  
- **Dual-path:** mouse-legible Settings for ordinary jobs; keyboard path for frequent actions (`Super+,` · Beacon Settings search / Actions · in-app `/` jump · hub ↑↓ Enter · CC). No TUI-only control center; no sanding off Facts/escapes  
- **Escapes:** quiet Fact-backed hatches (tool or conf); honest missing install; wrap engines into chrome — don’t re-skin full GUIs; don’t use escapes to hide a broken path ([CHROME.md](./CHROME.md) §1.8)  
- `Super+,` opens Settings (global shortcut + Hyprland bind)  
- Host posture reuses this app; does not invent a second control center
- Virtualization **mutations** stay in Workloads — Settings → Virtualization is a
  thin jumps/status hub (About still jumps there); auto-resolver / Portainer Out

Growth for this lock (not a second Omarchy menu): more Actions / chords as traffic warrants;
keep leaf chrome FormRow-legible.
