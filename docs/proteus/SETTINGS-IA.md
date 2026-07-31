---
doc: settings-ia
role: reference
audience: UI, contributors
last_updated: "2026-07-30"
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
| App mixer (Wave Link–style) | Channels (default Apps/…) + mic/line inputs × mixes; Speakers/mix listen; rename; peaks; `~/.config/proteus/audio-mix.json`; resident `proteus-audio-mix serve` (dump+peaks); mutations `audio-mix.py`; **CC Sound plate** — master on plate; per-source levels in Sources ▾ |
| Input level meter | streaming `audio-peak.py` on default source (Settings Input leaf) |
| Per-app volume / mute | `pactl list/set-sink-input-*` |
| Sound latency / buffer | `settings.json` `audioLatency` → `pw-metadata -n settings 0 clock.force-quantum` (256 / 512 / 1024) |
| Network (open editor) | NetworkManager UI / `nmtui` |
| Wi‑Fi connect / disconnect | `nmcli device wifi` (saved/open; password via NM) |
| Hostname | `hostnamectl` (polkit-gated set) |
| Bluetooth (status + open) | `bluetoothctl` · blueman / blueberry |
| VPN profiles (list + open NM) | `nmcli connection` (vpn / wireguard) |
| LocalSend (status + open / start / stop) | `localsend` · port 53317 |
| Tailscale (status + up/down + copy IP) | `tailscale status --json` · `wl-copy` |
| Package updates / search / remove / orphans | `pacman -Qu` / `-Ss` / `-Qqe` / `-Qdt` · apply `pkexec proteus-pkg` (multi install/remove; selective upgrades) |
| AUR search / install / remove / update | `yay`/`paru` `-Ssa` · remove via `-Qqm` foreign pkgs · multi-select |
| Flatpak / Flathub search / list / install / remove / update | `flatpak --user` · Flathub remote · Install\|Installed (mode-safe; empty honesty) · multi-select + live Cancel |
| Package picker chrome | `kit/PackagesPickerRow` · `PackagesActionBar` · `PackagesOpProgress` (exact `$` command + last error) |
| AppImages library | `~/.local/share/proteus/appimages` + `proteus-appimage-*.desktop` |
| Timezone / network time | `timedatectl set-timezone` / `set-ntp` (polkit-gated; errors surfaced in-pane) |
| Locale | `localectl status` (read-only + `/etc/locale.conf` escape hatch) |
| Location | Explicit place search → precise lat/lon in `settings.json` (**never IP-inferred**); Open-Meteo geocoding |
| Weather | `api.open-meteo.com` current conditions for the stored location — no API key; only those coordinates are sent |
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
| **Appearance** (`style`) | Category → Accent, Background, Lock screen, Icons (style compare + dock pins), Font (searchable + Add) | `settings.json`, Theme, `proteus-bg`; shared Kind/color/font/icon kit | `partial` |
| **Desktop** (`desktop`) | Category → Gaps, Borders & rounding, Motion, Dock & menu bar, Launcher (Spotlight Apps/Files/Clipboard/Actions · tags/recents) — leaf files + FormRow kit | json + hyprctl + `proteus-general.conf` · `launcherRecents` / `launcherFileRecents` / `launcherTagCatalog` / `launcherAppTags` | `shipped` |
| **Displays** (`displays`) | Layout canvas + per-monitor scale/mode/orientation; 10s Revert; Refresh/hotplug honesty; conf escape | hyprctl + `proteus-monitors.conf` | `shipped` |
| **Sound** (`sound`) | Category → Output / Input / Applications / Mixer / Latency — leaf files + FormRow kit | pactl + `proteus-audio-mix` / `audio-peak.py` + `pw-metadata` + `pw-link` | `shipped` |
| **Network** (`network`) | Category → This machine / Devices / Wi‑Fi / Bluetooth / LocalSend / Tailscale / VPN — leaf files + FormRow kit | hostnamectl / nmcli / bluetoothctl / localsend / tailscale | `shipped` |
| **Peripherals** (`peripherals`) | Category → Keyboard, Mouse; later touchpad / tablet | keybinds + input hyprctl | `shipped` |
| **Power** (`power`) | Power mode segmented (PPD); battery (UPower); idle / lid FormRows via `proteus-logind` drop-in + conf escape | `powerprofilesctl` / UPower / `proteus-logind` | `shipped` |
| **Users** (`users`) | Session Lock/Logout/Reboot/Shutdown; current + other local users (read-only + Refresh); greetd status + conf escape | `Config.session` · id/getent · greetd/`/etc/greetd/config.toml` | `shipped` |
| **Online accounts** (`accounts`) | Mail / contacts / cloud provider seats (coming soon; no OAuth) | TBD (not inventing mail/contacts apps here) | `partial` |
| **Date & time** (`datetime`) | Live clock, searchable timezone picker, network time toggle, locale, **Location** (shared system place + units) | `timedatectl` / `localectl` / Open-Meteo | `partial` |
| **Privacy** (`privacy`) | Permission categories listed; grants not enforced yet | EnvGate / adaptive apps later | `partial` |
| **Software** (`packages`) | Hub → Updates; Repos / AUR / Flathub (Install\|Installed mode-safe, per-mode search, op narrative); AppImages; Orphans | `pacman` + `proteus-pkg` · yay/paru · flatpak + Flathub · local AppImages | `partial` |
| **About** (`system`) | Hardware caps; session actions → Users | probe | `partial` |

VM / container **setup** is **not** a Settings category — a separate host app later.
About may still show host-relevant hardware facts.

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
| Accent color | Presets + custom hex + **HSV color graph** (`kit/ColorGraphPicker`, debounced commit / coalesced settings+hypr); **Dark / Light** (`kit/SettingsSegmented`); **Opacity** (0% clear · 100% solid, live — bar uses clearer `menuBarAlpha`, dock richer `glassAlpha`) + **Blur** (frosted bar/dock/launcher; debounced Hypr apply) |
| Background | Kind hub (`kit/SettingsKindPicker`): Color (`kit/SettingsColorPresetGroup` + graph) · Image (built-in stock + albums/slideshow; empty-album honesty; Missing thumb overlay) · Daily · Video · Animated. Applied by **`proteus-bg`** (Hypr `exec-once`) |
| Lock screen | Same Kind/color kit as Background + dim; Match desktop; **widgets only via lock Customize** (long-press) — not in Settings |
| Icons | **Default / Dark / Clear / Tinted** side-by-side squircle compare (`kit/SettingsIconStylePicker`); Tinted tint graph; custom art Switch/Reset; dock Keep/Remove via glass right-click menu + long-press edit (−) / drag-off (running apps appear on dock) |
| Desktop widgets | **Not in Settings** — unlocked desktop long-press or `Super+Shift+W` → Customize; free place + optional Snap to Grid; separate `desktopWidgets[]` |
| Notifications / DND | **Shell Control Center** (top-bar status cluster) — list depth · toast/`showToast` · DND · QS volume/tiles; Status HUD for media-key volume/brightness (suppressed while CC open); deep Sound/Network stay in Settings panes; **no Settings Notifications category** |
| Mix (inputs) | **Shell Control Center** unified **Sound** plate — master volume on plate; Listen ▾ + Sources ▾ (name · On/Off · peak · volume); Mixer › → Settings |
| Keep Awake | **Shell Control Center** duration menu (+ menu-bar **Awake** when on; Spotlight Actions) — temporary `systemd-inhibit idle:sleep` so hypridle/logind skip idle lock & sleep; **not** a Settings Power control |
| Power mode | **Settings → Power** segmented + Control Center **Power** tile menu — `powerprofilesctl` (Performance / Balanced / Eco) |
| LocalSend | **Settings → Network → LocalSend** + Control Center tile **menu** (start/stop · open · copy `ip:53317` · settings) + Spotlight — install honesty when missing |
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

Defaults include launcher (`Super+Space` / `Super+D`), Settings (`Super+,`),
terminal, workspaces, etc. (`env/hypr/proteus-keybinds.conf` template).

---

## 6. Desktop + Displays

Desktop: click sidebar → heading **Desktop** + sub-settings list, then leaf
pages via `kit/StickyPaneLoader` (`DesktopGapsLeaf`, `DesktopChromeLeaf`,
`DesktopMotionLeaf`, `DesktopDockLeaf`, `DesktopLauncherLeaf`).

| Sub-setting | Role |
|-------------|------|
| Gaps | Inner/outer `SettingsFormRow` sliders; live hypr |
| Borders & rounding | Border size + window rounding FormRows; live hypr |
| Motion | Window animations switch |
| Dock & menu bar | Show/hide/monitor/size FormRows; Advanced → `proteus-general.conf` |
| Launcher | Spotlight help (Ctrl+1–4 Apps/Files/Clipboard/Actions); empty Apps = Recents section or honest empty; empty Files = Recents + Places (or honest empty); Files search = Folders then Files · depth ≤5 · 40-cap; Clear recent apps / recent files; app tag catalog FormRows |

| Pane | Live apply | On-disk fragment | Guest seed |
|------|------------|------------------|----------|
| Desktop | `hyprctl keyword` (gaps, border, rounding, animations) + dock/menu sizes + Launcher tags/recents in `settings.json` | `proteus-general.conf` + `settings.json` (`launcherRecents`, `launcherFileRecents`, `launcherTagCatalog`, `launcherAppTags`) | `vm/guest/install-desktop-conf.sh` |
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
| Mixer | Wave Link–style grid: channels/inputs × mixes; Speakers vs mix listen; Level; rename; row peaks; add channel/input/mix. Quick per-source adjust also in Control Center Sources ▾ |
| Latency & buffer | Profile segmented + quantum frames; PipeWire clock summary when known |

| Pane | Live apply | On-disk / helper |
|------|------------|------------------|
| Sound | `pactl` volume/mute/default sink·source · sink-input volume/mute · test tone · matrix link/unlink · mixer routes | `settings.json` `audioLatency` → `pw-metadata`; Mixer dump+peaks via resident `proteus-audio-mix serve` (Python `audio-mix.py` / `audio-mix-peaks.py` fallback); matrix via `audio-matrix.py` → `pw-link`; mutations via `audio-mix.py` |

**Module rule:** Sound leaf helpers stay in `panes/Sound*Leaf.qml` + `kit/`
FormRow/Group — not a single mega-inline `SoundPane` body.

### Network

Network: click sidebar → heading **Network** + sub-settings list, then leaf pages
via `kit/StickyPaneLoader` (`NetworkMachineLeaf`, `NetworkDevicesLeaf`,
`NetworkWifiLeaf`, `NetworkBluetoothLeaf`, `NetworkLocalSendLeaf`,
`NetworkTailscaleLeaf`, `NetworkVpnLeaf`). Hub state lives in `NetworkPane.qml`
(`property Item host` on leaves; LocalSend uses shared `LocalSend` singleton).

| Sub-setting | Role |
|-------------|------|
| This machine | Hostname draft + Apply (`hostnamectl`); Refresh all |
| Devices | nmcli interfaces with type · state · connection hints |
| Wi‑Fi | Scan/connect/disconnect FormRows; signal/security hints; Rescan |
| Bluetooth | Adapter Powered/Off; blueman escape (pairing Out) |
| LocalSend | Install honesty; Start/Stop / Open / copy address; CC menu + Spotlight |
| Tailscale | Status / IP copy / peers / up·down·login; `tailscale status` escape |
| VPN | NM VPN/WireGuard profile list; single NetworkManager escape |

| Pane | Live apply | On-disk / helper |
|------|------------|------------------|
| Network | `hostnamectl` set · `nmcli` wifi · `tailscale` up/down · clipboard IP | Escape: blueman / NetworkManager / `nmtui` — password Wi‑Fi, pairing, Headscale, WireGuard wizard Out |

**Module rule:** Network leaf helpers stay in `panes/Network*Leaf.qml` + `kit/`
FormRow/Group — not a single mega-inline `NetworkPane` body.

---

## 7. Growth

**Date & time** is `partial` (see §2) — remaining work is write-gaps (locale
set, forecast UI), not a greenfield pane. **Power** mode (PPD) + logind writer
shipped; charge-threshold / TLP stay Out.

**Online accounts · Privacy** are `partial` — provider OAuth and permission
enforcement Out. **Users** session/greeter status shipped (add-remove + writing
greeter prefs stay Out).

Depth order for what’s left:

1. **Users depth** — write greeter/autologin prefs; add-remove stays Out of Settings  
2. **Online accounts** — real provider connect when adaptive mail/contacts exist  
3. **Privacy** — grant model when adaptive apps need it  
4. **Date & time** — locale set; weather forecast view  
5. **Network depth** — Tailscale login-server (Headscale); peer/exit-node UI; in-pane pairing; WireGuard / password Wi‑Fi wizard (hub + leaves shipped)  
6. **Peripherals** — touchpad / tablet  
7. **Software** — dep graphs later; Omarchy-style Install/Remove pickers + mode-safe loads + op narrative shipped (`partial`; Snap Out)  
8. **Settings Notifications pane** — optional later; shell Control Center is the SoT today  

*(Displays layout + Revert follow-ups shipped — removed from growth depth.)*
*(Network hub + FormRow polish shipped — depth wizards stay on the list.)*
*(Control Center notifications + QS depth shipped — Settings Notifications pane stays Out.)*
*(Users session + greetd status shipped — writing greeter prefs / useradd stay Out.)*
*(Power mode PPD + logind writer shipped — charge thresholds / TLP stay Out.)*

Virt / container setup stays a **separate app**, not a Settings growth item.

---

## 8. UX locks

Canonical chrome language (tokens + patterns): [CHROME.md](./CHROME.md)
(`Theme.qml` is the live binding).

- Calm chrome: discoverability without permanent label clutter  
- Accent = selection/action only  
- Legibility floor: prefs must not produce unreadable UI  
- Settings visual language: modern System Settings (grouped lists, soft selection, large titles)  
- `Super+,` opens Settings (global shortcut + Hyprland bind)  
- Host posture reuses this app; does not invent a second control center  
