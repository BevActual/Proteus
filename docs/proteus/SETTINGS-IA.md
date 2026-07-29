---
doc: settings-ia
role: reference
audience: UI, contributors
last_updated: "2026-07-29"
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
| [6. Desktop + Displays](#6-desktop--displays) | Same hybrid pattern |
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
| Displays (list) | `hyprctl monitors -j` |
| Displays scale / mode / orientation / layout | `hyprctl keyword monitor` + `proteus-monitors.conf` (recommended modes; confirm large jumps; 10s full-snapshot Revert; Identify flash; drag layout canvas) |
| Volume / mute / default sink | `pactl` |
| Input volume / mute / default source | `pactl` |
| Input level meter | streaming `audio-peak.py` on default source (Settings Input leaf) |
| Per-app volume / mute | `pactl list/set-sink-input-*` |
| Sound latency / buffer | `settings.json` `audioLatency` → `pw-metadata -n settings 0 clock.force-quantum` (256 / 512 / 1024) |
| Network (open editor) | NetworkManager UI / `nmtui` |
| Wi‑Fi connect / disconnect | `nmcli device wifi` (saved/open; password via NM) |
| Hostname | `hostnamectl` (polkit-gated set) |
| Bluetooth (status + open) | `bluetoothctl` · blueman / blueberry |
| VPN profiles (list + open NM) | `nmcli connection` (vpn / wireguard) |
| Tailscale (status + up/down + copy IP) | `tailscale status --json` · `wl-copy` |
| Package updates / search / remove / orphans | `pacman -Qu` / `-Ss` / `-Qdt` · apply `pkexec proteus-pkg` (polkit; terminal fallback; live progress) |
| AUR search / install / remove / update | `yay` or `paru` as session user (not proteus-pkg) |
| Flatpak search / list / install / remove / update | `flatpak --user` (+ Add Flathub) |
| AppImages library | `~/.local/share/proteus/appimages` + `proteus-appimage-*.desktop` |
| Timezone / network time | `timedatectl set-timezone` / `set-ntp` (polkit-gated; errors surfaced in-pane) |
| Locale | `localectl status` (read-only + `/etc/locale.conf` escape hatch) |
| Location | Explicit place search → precise lat/lon in `settings.json` (**never IP-inferred**); Open-Meteo geocoding |
| Weather | `api.open-meteo.com` current conditions for the stored location — no API key; only those coordinates are sent |
| Battery charge / health / estimate | UPower display device (`Quickshell.Services.UPower`) |
| Idle / lid policy | `/etc/systemd/logind.conf` — **read-only**; commented keys reported as shipped defaults |

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
| **Appearance** (`style`) | Category → Accent, Background, Lock screen, Icons (plate + dock pins), Font | `settings.json`, Theme, `proteus-bg` | `partial` |
| **Desktop** (`desktop`) | Category → Gaps, Borders & rounding, Motion, Dock & menu bar, Launcher (Spotlight tags/recents) | json + hyprctl + `proteus-general.conf` · `launcherRecents` / `launcherTagCatalog` / `launcherAppTags` | `shipped` |
| **Displays** (`displays`) | Per-monitor scale + mode + layout canvas (Apply); conf escape hatch | hyprctl + `proteus-monitors.conf` | `partial` |
| **Sound** (`sound`) | Category → Output (volume/mute/device/test tone), Input (level, meter, device), Applications (per-app volume), Latency & buffer | pactl + `parec` + `pw-metadata` | `partial` |
| **Network** (`network`) | Hostname; Wi‑Fi scan/connect; Bluetooth; Tailscale; NM VPN | hostnamectl / nmcli / bluetoothctl / tailscale | `partial` |
| **Peripherals** (`peripherals`) | Category → Keyboard, Mouse; later touchpad / tablet | keybinds + input hyprctl | `shipped` |
| **Power** (`power`) | Battery charge / health / estimate (UPower); logind idle + lid policy read-only with conf escape hatch | UPower / `logind.conf` | `partial` |
| **Users** (`users`) | Session actions; current + other local users (read-only); greeter planned | `id` / getent · `Config.session` | `partial` |
| **Online accounts** (`accounts`) | Mail / contacts / cloud provider seats (coming soon; no OAuth) | TBD (not inventing mail/contacts apps here) | `partial` |
| **Date & time** (`datetime`) | Live clock, searchable timezone picker, network time toggle, locale, **Location** (shared system place + units) | `timedatectl` / `localectl` / Open-Meteo | `partial` |
| **Privacy** (`privacy`) | Permission categories listed; grants not enforced yet | EnvGate / adaptive apps later | `partial` |
| **Software** (`packages`) | Category → Updates, Search, AUR, Flatpak, AppImages, Orphans (propose → confirm → apply; Snap Out) | `pacman` + `proteus-pkg` · yay/paru · flatpak · local AppImages | `partial` |
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
| Accent color | Presets + custom hex + **HSV color graph**; **Dark / Light**; **Opacity** (0% clear · 100% solid, live) + **Blur** (frosted bar/dock/launcher; debounced Hypr apply) |
| Background | Kind hub (Qt dialogs): Color (+ presets + **HSV color graph**) · Image (+ folder slideshow) · Video (Qt Multimedia) · Animated (Drift / Pulse / Orbit / Aurora / Beacon). Applied by **`proteus-bg`** (Hypr `exec-once`) |
| Lock screen | Wallpaper Kind + dim in Settings; **widgets only via lock Customize** (long-press) |
| Icons | **Default / Dark / Clear / Tinted** restyle icon artwork (macOS Tahoe); custom art Switch/Reset; dock **Keep / Remove** via right-click (running apps appear on dock) |
| Desktop widgets | **Not in Settings** — unlocked desktop long-press or `Super+Shift+W` → Customize; free place (not stacked); separate `desktopWidgets[]` |
| Notifications / DND | **Shell Control Center** (top-bar status cluster); no Settings pane yet — deep Sound/Network stay in existing panes |
| Font | System `fc-list` discovery + size; live preview |

Open a row → leaf controls; **‹ Appearance** / Esc returns to the list. Desktop
uses the same pattern. Pane visibility is owned by `Settings.qml` (only one
category visible at a time). Page id remains `style` / `style-*`.

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

Desktop: click sidebar → heading **Desktop** + sub-settings list (Gaps,
Borders & rounding, Motion, Dock & menu bar, Launcher), then leaf pages.

| Pane | Live apply | On-disk fragment | Guest seed |
|------|------------|------------------|----------|
| Desktop | `hyprctl keyword` (gaps, border, rounding, animations) + dock/menu sizes + Launcher tags/recents in `settings.json` | `proteus-general.conf` + `settings.json` (`launcherRecents`, `launcherTagCatalog`, `launcherAppTags`) | `vm/guest/install-desktop-conf.sh` |
| Displays | Scale + mode + orientation + layout via `hyprctl keyword monitor` | Live `monitor =` lines in `proteus-monitors.conf` | same |

Templates: `env/hypr/proteus-general.conf`, `env/hypr/proteus-monitors.conf`. Nested
`env/hypr/hyprland.conf` sources both plus keybinds.

---

## 7. Growth

**Power** and **Date & time** are `partial` (see §2) — remaining work is
write-gaps (logind helper, locale set, forecast UI), not greenfield panes.

**Users · Online accounts · Privacy** are `partial` — session actions +
read-only local users shipped; provider OAuth and permission enforcement Out.

Depth order for what’s left:

1. **Users** — greeter / autologin; add-remove stays Out of Settings  
2. **Online accounts** — real provider connect when adaptive mail/contacts exist  
3. **Privacy** — grant model when adaptive apps need it  
4. **Power** — privileged logind idle/lid writer (read-only today)  
5. **Date & time** — locale set; weather forecast view  
6. **Network** — Tailscale login-server (Headscale); peer/exit-node UI; in-pane pairing; WireGuard wizard  
7. **Peripherals** — touchpad / tablet  
8. **Displays** — layout canvas + drag Apply shipped; re-verify Revert after sleep/hotplug  
9. **Software** — selective upgrade checkboxes / dep graphs later; AUR + Flatpak + AppImages in tree (`partial`; Snap Out)  

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
