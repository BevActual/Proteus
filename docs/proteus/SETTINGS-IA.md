---
doc: settings-ia
role: reference
audience: UI, contributors
last_updated: "2026-08-01"
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

**proteus-settings** is the product face of “usable custom OS”: Mac-smooth
controls, Linux facts underneath. Shell ⚙ / dock / `Super+,` only **launch** it.

Code: `apps/proteus-settings/` (`Settings.qml` shell + `kit/*` form primitives +
`panes/*`; `SettingsNav.qml`; `shared/` → `shell/shared`).

## Document map

| Section | Contents |
|---------|----------|
| [1. Pattern](#1-pattern) | Elegant UI → inspectable fact |
| [2. Categories](#2-categories) | Sidebar IA |
| [3. Containers](#3-containers) | Top-level vs submenu vs sections |
| [4. Appearance hub](#4-appearance-hub) | Drill-in |
| [5. Keyboard pattern](#5-keyboard-pattern) | Prototype hybrid feature |
| [6. Desktop + Displays](#6-desktop--displays) | Same hybrid pattern (+ Sound · Network) |
| [7. Growth](#7-growth) | Next panes |
| [8. UX locks](#8-ux-locks) | Calm chrome |

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
| VPN profiles (list · up/down · WG import) | `nmcli connection` up/down · `import type wireguard` |
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
| **Network** (`network`) | Category → This machine / Devices / Diagnostics / Wi‑Fi / Bluetooth / LocalSend / Tailscale / VPN — password Wi‑Fi · BT pair · TS peers/exit/login-server · VPN up/down · WG import | hostnamectl / nmcli / bluetoothctl / localsend / tailscale / `NetworkDiagnostics` | `shipped` |
| **Peripherals** (`peripherals`) | Category → Keyboard, Mouse, Gamepads (Guide Facts); later touchpad / tablet | keybinds + input hyprctl + `gamepadsGuide*` | `shipped` |
| **Power** (`power`) | Power mode segmented (PPD); battery (UPower); idle / lid FormRows via `proteus-logind` drop-in + conf escape | `powerprofilesctl` / UPower / `proteus-logind` | `shipped` |
| **Users** (`users`) | Session Lock/Logout + confirm Reboot/Shutdown; lock screen PIN set/change/clear; current user (GECOS/home) + other local users read-only; Online accounts jump; greetd status + conf escape | `Config.session` · `proteus-pin.py` (hash under `~/.local/share/proteus/auth/`) · id/getent · greetd/`/etc/greetd/config.toml` | `shipped` |
| **Online accounts** (`accounts`) | Connector catalog + Google PKCE seats (`proteus-accounts` vault); Microsoft/Nextcloud/… listed | `proteus-accounts` + `Accounts.qml` (mail/contacts apps Out) | `partial` |
| **Date, time & weather** (`datetime`) | Live clock, searchable timezone + locale pickers, NTP, **Location** (place + units + 5-day forecast + Match TZ) | `timedatectl` / `localectl set-locale` / Open-Meteo | `shipped` |
| **Notifications** (`notifications`) | Prefs: hard DND · jump to Focus · live list stays Control Center | `notificationsDnd` · FocusMode | `shipped` |
| **Privacy & security** (`privacy`) | Hub → What leaves + weather mute + session; **In use now**; category leaves (Allow/Deny + per-app Allow/Ask/Deny); Flatpak overrides | `permissions.json` · `proteus-permissions.py` · PrivacyIndicators · EnvGate grants · Flatpak override | `partial` |
| **Software** (`packages`) | Hub → Updates; Repos / AUR / Flathub (Install\|Installed mode-safe, per-mode search, op narrative); AppImages; **Web apps** (URL → `proteus-web-*.desktop` via `proteus-webapp`, no polkit); Orphans — helper honesty when yay/paru/flatpak missing | `pacman` + `proteus-pkg` · yay/paru · flatpak + Flathub · local AppImages · `proteus-webapp` | `shipped` |
| **About** (`system`) | OS/kernel/hostname · QS/Hypr · load/mem/storage · battery when present · Mission Center (Install… → Flathub · `io.missioncenter.MissionCenter`) · Check for updates → Software; hardware caps; soft Hyprland profile; Copy + Copied | `SystemInfo` · `SystemLoad` · `MissionCenter` · `Power` · probe · `HyprProfile` | `shipped` |

VM / container **setup** is **not** a Settings category — a separate host app later.
About may still show host-relevant hardware facts. Soft profile select does
**not** flip console/host hard switches. Hostname **edit** stays under Network.

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
5. Guest wiring: `vm/guest/install-keybinds.sh`

**Peripherals** category (same drill-in as Appearance): Keyboard · Mouse.
Headphones/speakers stay under **Sound**, not Peripherals.

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
| Spaces | Displays share Spaces (`workspaceMode` synced \| perDisplay); Super+Ctrl+N always this display; bands via `proteus-workspace` |
| Default apps | Browser / Files / Images / Music / Video / PDF / Text / Archives / Mail / Calendar via `proteus-defaults.py` + `xdg-mime`; mimeapps.list escape |
| Focus | Soft quiet profiles (Work/Sleep/Personal); allowlist · keywords · schedule · critical breakthrough; CC menu + Desktop → Focus leaf |
| Control Center | Plates + tile visibility/size/span/order + reset (`ControlCenterLayout`); **columns 2\|3 schema only — UI Out** |
| Beacon | Universal Apps (+ Windows · Privacy · **focus-cycle** Action); Files index (`beacon-file-index`); Clipboard `wtype`; tags / clear recents |

| Pane | Live apply | On-disk fragment | Guest seed |
|------|------------|------------------|----------|
| Desktop | `hyprctl keyword` (gaps, border, rounding, animations) + dock/menu sizes + Beacon tags/recents in `settings.json` | `proteus-general.conf` + `settings.json` (`launcherRecents`, `launcherFileRecents`, `launcherTagCatalog`, `launcherAppTags`) | `vm/guest/install-desktop-conf.sh` |
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
| VPN | Profile Connect/Disconnect; WireGuard import; NetworkManager escape for OpenVPN |

| Pane | Live apply | On-disk / helper |
|------|------------|------------------|
| Network | `hostnamectl` · `nmcli` wifi/VPN/WG · `bluetoothctl` · `tailscale` up/down/set/login-server · clipboard IP | Escape: blueman / NetworkManager / Wireshark — Headscale admin · OpenVPN wizard · in-pane capture Out |

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

**Smoke matrix:** host `./scripts/smoke/software-reliability-smoke.sh` (hub + leaves +
Web apps); guest `./scripts/smoke/software-guest-smoke.sh` in `smoke-all` (SKIP unless SSH /
`PROTEUS_GUEST=1`). **Out:** Snap; dependency graphs.

**Module rule:** Software leaf helpers stay in `panes/Packages*Pane.qml` + `kit/`
— not a single mega-inline hub body.

---

## 7. Growth

**Appearance** hub + five leaves shipped (mega-page merge Out). **Date, time & weather**
locale set + 5-day forecast + Match TZ shipped; manual time / RTC writers Out.
**Power** mode (PPD) + logind writer shipped; charge-threshold / TLP stay Out.

**Online accounts** seats are `partial` — catalog + Google PKCE when configured;
mail/contacts/Drive **apps** stay Out. **Privacy & security** ships transparency + weather
mute + session + **permissions store** (adaptive EnvGate + Flatpak overrides;
native capture observed, not sandboxed). **Users** session/greeter status shipped
(add-remove + writing greeter prefs stay Out).

Depth order for what’s left:

1. **Users depth** — write greeter/autologin prefs; add-remove stays Out of Settings  
2. **Online accounts depth** — Microsoft / Nextcloud connect; consumers stay Out  
3. **Privacy native enforcement** — PipeWire/v4l2 policy / portal store write stay Out  
4. **Network polish** — largely shipped (IPv4 on Devices · Diagnostics ss/firewall); Headscale admin / OpenVPN wizard stay Out  
5. **Peripherals** — touchpad / tablet  
6. **Software depth** — dependency graphs later; Snap stays Out (hub + six leaves + smoke matrix shipped)  
7. ~~Settings Notifications pane~~ — shipped (prefs-only; CC remains live list)  

*(Displays layout + Revert follow-ups shipped — removed from growth depth.)*
*(Network hub + FormRow polish shipped — depth wizards stay on the list.)*
*(Network Diagnostics · Wireshark escape shipped — in-pane capture Out.)*
*(Network depth: password Wi‑Fi · BT pair · TS peers/exit/login-server · VPN up/down · WG import shipped — Headscale admin / OpenVPN wizard Out.)*
*(Control Center notifications + QS depth shipped — Settings Notifications prefs pane shipped; live list stays CC.)*
*(Users session + greetd status shipped — writing greeter prefs / useradd stay Out.)*
*(Users polish: Reboot/Shutdown confirm · GECOS/home · Online accounts jump · lock screen PIN shipped.)*
*(Power mode PPD + logind writer shipped — charge thresholds / TLP stay Out.)*
*(Software hub + six leaves + reliability/guest smoke shipped — dep graphs / Snap stay Out.)*
*(Appearance hub + Date, time & weather locale/forecast shipped — manual time/RTC Out.)*
*(About OS/kernel/hostname · load strip · Mission Center escape · Copy+Copied ·
soft profile shipped — hard posture switch via proteus-posture / Beacon / CC (not About picker); no in-Settings live dashboard.)*
*(Privacy & security hub · In use now · category grants · Flatpak overrides ·
Beacon/dock grant parity · Diagnostics deny → Network Diagnostics · smoke/install
privacy harness shipped — native OS sandbox / portal store write still Out;
fail-open until Permissions.ready held.)*
*(Desktop catch-up: desktop-smoke · defaults/beacon-index install · Focus/CC/Spaces
roundtrip · guest Desktop nav · Beacon Settings blurb · SETTINGS-IA §6 Focus/CC
rows shipped — CC columns UI · Focus profile CRUD · Spaces multi-head depth Out.)*

Virt / container setup stays a **separate app**, not a Settings growth item.

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

Growth for this lock (not a second Omarchy menu): more Actions / chords as traffic warrants;
keep leaf chrome FormRow-legible.
