---
doc: compositor
role: architecture
audience: architects, contributors, coding agents
last_updated: "2026-07-30"
doc_status: active
scope: Engines under hard-switch postures; Hyprland + Quickshell; profiles, capabilities, limits
related:
  - ARCHITECTURE.md
  - POSTURES.md
  - STACK.md
  - SETTINGS-IA.md
  - CURRENT.md
status_legend:
  shipped: In code today
  partial: Present; gaps remain
  planned: Designed; not in code
---

# Compositor & shell runtime — Hyprland + Quickshell

Proteus **owns the product thinking**. Hyprland, Quickshell, and (for
**console**) a game-scoped compositor are **engines** under hard-switch
postures — not the brand and not every posture. Focus set: **desktop ·
console · host** ([POSTURES.md](./POSTURES.md)).

## Document map

| Section | Contents |
|---------|----------|
| [1. Roles](#1-roles) | Who does what |
| [2. Hyprland](#2-hyprland) | Adapt, don’t become |
| [3. Quickshell](#3-quickshell) | Strengths + limits to fold in |
| [4. Profiles on disk](#4-profiles-on-disk) | Intended conf layout |
| [5. Capabilities](#5-capabilities) | Facts that drive posture + features |
| [6. HARD RULES](#6-hard-rules) | Locks |
| [7. Status](#7-status) | What’s real today |

---

## 1. Roles

| Piece | Role |
|-------|------|
| **Proteus** | Identity, postures, Settings, capability model |
| **Hyprland** | Windowing / input / display for postures that need a Wayland compositor |
| **Quickshell** | Chrome that *expresses* posture (bars, dock, overlays; Settings today) |

```
capabilities + role  →  hard-switch posture  →  engines + QS chrome + Settings primary panes
```

| Focus posture | Typical engines |
|---------------|-----------------|
| **desktop** | Hyprland + full QS shell |
| **console** | Game-scoped compositor (Gamescope-class or equivalent) + sparse QS (or lean chrome) |
| **host** | Little/no DE; UI on demand — still Proteus ([POSTURES.md](./POSTURES.md) § Host vs hypervisor) |

Soft hypr **profile reload alone is not a posture flip** for console/host.

---

## 2. Hyprland

### Do

- Desktop **profiles** (tiling, gaps, …) as fragments under Hyprland
- Settings as the friendly editor; **files remain SoT**
- Capability-gated features (animations, blur, multi-mon, gestures)
- Fail soft: hide or degrade Settings controls when a capability is missing
- Plan **console** as a different compositor scope — not “Hyprland media.conf +
  bigger buttons”

### Don’t (early)

- Fork Hyprland to invent Proteus
- Encode product philosophy only in opaque plugins with no Settings story
- Assume every posture needs a full Hyprland desktop (**host** / parked home may not)
- Sell soft profile reload as **console** or **host**

**Pattern already shipping:** Keyboard → `proteus-keybinds.conf` → `hyprctl reload`.
Extend the same pattern to general/monitors/animations fragments.

---

## 3. Quickshell

Quickshell is a **shell toolkit** (bars, widgets, lockscreens, greeters, tray,
compositor IPC) — not an application framework and not a compositor.

### Lean into (built-ins)

Hyprland workspaces/toplevels/dispatch/global shortcuts · `DesktopEntries` ·
`Process` / `FileView` · PipeWire · tray · MPRIS · UPower · Bluetooth ·
notifications · Pam / Greetd (lock/greeter later) · hot reload (VM 9p dogfood).

Prefer these for OS facts before inventing daemons.

### Limits to fold into Proteus

| Limitation | Fold |
|------------|------|
| **Shell ≠ app platform** | Chrome + Settings in QS; product apps → Tauri ([STACK.md](./STACK.md)) |
| **Hyprland-shaped integrations** | Best backend for **desktop** — not universal; **console** uses a game-scoped path |
| **Output / session fragility** | Crashes reported on monitor hotplug, TTY switch, KVM, sleep — **v1:** `shell/scripts/proteus-qs` backoff loop from Hyprland `exec-once`; never keep sole truth in QS memory |
| **Session start hygiene** | `vm/guest/proteus-session` prefers `start-hyprland`; hypr seed `exec-once` = qs/bg/cliphist only (no terminal); `hide-system-apps` from apps + post-install; host `session-smoke` / `install-smoke` |
| **Young / moving target** | **v1:** record `quickshell --version` in `qs-guest-smoke` / `qs-version-smoke` (do **not** `IgnorePkg`-pin rolling Arch); after `pacman -Syu` re-run `PROTEUS_GUEST=1 ./scripts/smoke-all.sh`; ISO pin later |
| **QML is programming** | Shared modules; Rust helpers for messy IO |
| **Settings as second `quickshell -p`** | OK now; files are SoT; revisit Tauri Settings if lifecycle hurts |
| **Not a virt/ops UI kit** | Host console ≠ Portainer in a panel |
| **Touch / phone / VR** | Device-class / parked-posture work — desktop `PanelWindow` patterns won’t port for free |

### Owns vs does not own

```
Quickshell owns:     presence chrome, lock/greeter (later), transient overlays,
                     Settings panes that are “system looking at you”

Quickshell does not: Host product console, rich Bevington apps,
                     cluster/ops UI, being the only copy of system truth
```

Do **not** fork Quickshell — wrap it; upstream bugs when we hit them.

---

## 4. Profiles on disk

`partial` — desktop profile + active pointer `shipped`; `media.conf` (console
alias) / host / home stubs `shipped`. Hard-switch sessions for console/host
still `planned`. Keyboard + Desktop fragments `shipped`; Displays layout canvas
`partial` (drag + full-snapshot Revert):

```
~/.config/hypr/
  hyprland.conf                 # sources below
  proteus-keybinds.conf         # Settings → Keyboard  (shipped)
  proteus-general.conf          # gaps, borders, rounding, animations  (shipped)
  proteus-monitors.conf         # Displays list stub  (partial)
  proteus-profile.conf          # active posture pointer → profiles/*.conf  (shipped)
  profiles/
    desktop.conf                # shipped (tiling defaults)
    media.conf                  # stub — legacy name for **console** (rename later)
    host.conf                   # stub (ops / lean later)
    home.conf                   # stub — parked posture only
```

Today’s helper is **soft only**: `vm/guest/set-hypr-profile.sh
desktop|console|media|host|home` (`console` ≡ `media`). Settings → About
(`HyprProfile.qml`) soft-selects the same pointer. Intended product flip =
**hard switch** (engines + shell), not profile reload alone — see
[POSTURES.md](./POSTURES.md) § Hard switches.

Nested template today: `env/hypr/hyprland.conf` sources `proteus-monitors.conf`,
`proteus-general.conf`, `proteus-keybinds.conf`, and `proteus-profile.conf`.

---

## 5. Capabilities

Capabilities are **session/machine facts** — the device environment inside a
posture. Full product table: [POSTURES.md](./POSTURES.md) § Device environments
+ § Capabilities.

| Capability | Influences |
|------------|------------|
| `display` / `headless` | Whether Hyprland + QS start at all |
| `tiling` / `multi_monitor` | Hyprland profile, Displays pane |
| `touch` / `pointer` / `remote` / `gamepad` | Chrome targets, keybind set |
| `mic` / `speaker` | Voice surfaces; meeting mode |
| `vitals` / `haptics` | Parked wearable chrome without assuming a watch face |
| `qs_hyprland` / `qs_pipewire` | Which Settings backends light up |
| `display_hotplug_fragile` | Respawn policy; degrade live rearrange |
| `libvirt` / `containers` / `home_control` | Host / parked-home eligibility |
| `game_scope` | Console game-scoped compositor path (*planned*) |
| `battery` | Power panes (UPower via QS later) |

Resolver (planned): probe → capability set → hard-switch posture → engines +
Settings. Stub today: `PROTEUS_SURFACE=` (posture only); soft hypr profiles.

Rule: **missing `display` does not invent a new posture** — it disables
compositor chrome for that unit.

---

## 6. HARD RULES

1. **Hyprland is a backend** — Proteus defines posture; hypr conf expresses it.  
2. **Quickshell is chrome (+ Settings for now)** — not the app platform.  
3. **SoT on disk / CLI** — QS restart must not lose config.  
4. **Respawn the shell** — `proteus-qs` flock/backoff/`--restart` (optional
   systemd `--user` unit); assume hotplug/TTY pain until proven otherwise.  
5. **No Hyprland/QS forks** early — profile, wrap, contribute upstream.  
6. **Not every posture needs Hyprland** — **host** defaults lean/headless; ops UI
   is **on demand**; **console** uses a game-scoped compositor path — still the
   same product ([POSTURES.md](./POSTURES.md)).
7. **Soft profile reload ≠ posture flip** for console/host — hard switches only.

---

## 7. Status

| Item | Status |
|------|--------|
| Guest Hyprland + QS shell | `shipped` |
| Settings → keybinds → hypr conf | `shipped` |
| Settings → gaps/borders via hyprctl | `shipped` |
| Per-posture hypr profiles | `partial` — desktop + media(console alias)/host/home stubs + soft `set-hypr-profile.sh` + Settings About picker |
| Console / host hard switches | `planned` — engine + shell session flip |
| QS respawn / crash policy | `partial` — `proteus-qs` flock/backoff/`--restart`; optional `proteus-qs.service` user unit (hypr exec-once still default) |
| Capability resolver | `planned` |
| Pin QS version in guest docs/ISO | `partial` — version **recorded** in smoke; IgnorePkg/ISO pin Out |
| Greeter/lock in QS | `partial` — lock screen shipped (PAM); greetd/tuigreet still login |
