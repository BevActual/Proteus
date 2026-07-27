---
doc: settings-ia
role: reference
audience: UI, contributors
last_updated: "2026-07-26"
doc_status: active
scope: Settings control-center categories, backends, hybrid UX pattern
related:
  - ARCHITECTURE.md
  - CURRENT.md
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

Code: `apps/proteus-settings/` (`Settings.qml` shell + `panes/*`; `SettingsNav.qml`;
`shared/` → `shell/shared`).

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
| Accent / wallpaper / font | `~/.config/proteus/settings.json` + Theme + swaybg |
| Gaps / borders / rounding / animations | json + `hyprctl` + `~/.config/hypr/proteus-general.conf` |
| Keyboard shortcuts | `~/.config/proteus/keybinds.json` + `~/.config/hypr/proteus-keybinds.conf` |
| Mouse sensitivity / accel | json + `hyprctl` input:* (+ general conf `input` block) |
| Displays (list) | `hyprctl monitors -j` |
| Displays scale / mode / orientation | `hyprctl keyword monitor` + `proteus-monitors.conf` (recommended modes; confirm large jumps; 10s Revert; Identify flash) |
| Volume / mute / default sink | `pactl` |
| Input volume / mute / default source | `pactl` |
| Input level meter | short `parec` peak sample |
| Per-app volume / mute | `pactl list/set-sink-input-*` |
| Sound latency / buffer | `settings.json` `audioLatency` → `pw-metadata -n settings 0 clock.force-quantum` (256 / 512 / 1024) |
| Network (open editor) | NetworkManager UI / `nmtui` |
| Package updates / search | `pacman -Qu` / `-Ss` · apply `pkexec proteus-pkg` (polkit; terminal fallback) |

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
| **Appearance** (`style`) | Category → Accent, Background, Font | `settings.json`, Theme, wallpaper | `shipped` |
| **Desktop** (`desktop`) | Category → Gaps, Borders & rounding, Motion, Dock | json + hyprctl + `proteus-general.conf` | `shipped` |
| **Displays** (`displays`) | Per-monitor scale + mode (Apply); conf escape hatch | hyprctl + `proteus-monitors.conf` | `partial` |
| **Sound** (`sound`) | Output + input volume/mute, devices, peak meter, per-app volume, latency/buffer, test tone | pactl + `parec` + `pw-metadata` | `partial` |
| **Network** (`network`) | Device status + open editor; later Bluetooth, VPN | nmcli / nmtui (+ later) | `partial` |
| **Peripherals** (`peripherals`) | Category → Keyboard, Mouse; later touchpad / tablet | keybinds + input hyprctl | `shipped` |
| **Power** | Battery, sleep, lid (laptop-primary) | systemd / UPower | `planned` |
| **Users** | Accounts, login; session actions peel here from About | accounts / loginctl | `planned` |
| **Online accounts** | Mail, contacts, cloud storage providers | TBD (not inventing mail/contacts apps here) | `planned` |
| **Date & time** | Clock, timezone, locale | timedatectl / locale | `planned` |
| **Privacy** | Permissions when adaptive apps exist | app permissions model | `planned` |
| **Software** (`packages`) | Category → Updates, Search (propose → confirm → polkit) | `pacman` + `services/proteus-pkg` | `partial` |
| **About** (`system`) | Hardware caps, lock / logout / reboot / shutdown (until Users exists) | probe + hypr / systemctl / loginctl | `partial` |

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
`canGoBack` / `backLabel` for the header button.

---

## 4. Appearance hub

Click **Appearance** in the sidebar → content heading is **Appearance**, body is
the sub-settings list:

| Sub-setting | Role |
|-------------|------|
| Accent color | Bar, dock, borders |
| Background | Image pick + fit mode |
| Font | UI family + size |

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
terminal, workspaces, etc. (`env/proteus-keybinds.conf` template).

---

## 6. Desktop + Displays

Desktop: click sidebar → heading **Desktop** + sub-settings list (Gaps,
Borders & rounding, Motion, Dock), then leaf pages.

| Pane | Live apply | On-disk fragment | Guest seed |
|------|------------|------------------|----------|
| Desktop | `hyprctl keyword` (gaps, border, rounding, animations, accent) | `proteus-general.conf` | `vm/guest/install-desktop-conf.sh` |
| Displays | Scale + mode + orientation via `hyprctl keyword monitor` | Live `monitor =` lines in `proteus-monitors.conf` | same |

Templates: `env/proteus-general.conf`, `env/proteus-monitors.conf`. Nested
`env/hyprland.conf` sources both plus keybinds.

---

## 7. Growth

Next category / depth order:

1. **Power** — battery / sleep (laptop)  
2. **Users** — peel session actions from About  
3. **Online accounts** — mail / contacts / cloud providers  
4. **Date & time** — clock, timezone, locale  
5. **Privacy** — when adaptive apps need permissions  
6. **Network** — Bluetooth / VPN under Network  
7. **Peripherals** — touchpad / tablet  
8. **Displays** — fix Revert (parked); then drag layout for multi-monitor  
9. **Software** — deeper UX (progress stream, remove/orphan); mutator shipped  

Virt / container setup stays a **separate app**, not a Settings growth item.

---

## 8. UX locks

- Calm chrome: discoverability without permanent label clutter  
- Accent = selection/action only  
- Legibility floor: prefs must not produce unreadable UI  
- `Super+,` opens Settings (global shortcut + Hyprland bind)  
- Host posture reuses this app; does not invent a second control center  
