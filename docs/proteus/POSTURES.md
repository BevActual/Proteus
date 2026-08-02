---
doc: postures
role: architecture
audience: architects, contributors, coding agents
last_updated: "2026-07-30"
doc_status: active
scope: Focus postures (hard switches); parked later jobs; host vs home vs hypervisor; resolver
related:
  - POSITIONING.md
  - ARCHITECTURE.md
  - COMPOSITOR.md
  - STACK.md
  - APPLICATIONS.md
  - HARDWARE.md
  - CURRENT.md
status_legend:
  shipped: In code today
  partial: Stub or partial
  planned: Designed; not in code
  parked: Thesis only — not in proof order
  legacy: Old loader / profile name; map to focus posture
---

# Postures — hardware + intended use

A **posture** is the machine’s current **job**, driven by capabilities and
intent — not a CSS breakpoint and not a separate distro.

**Focus set (prove these):** `desktop` · `console` · `host`

Each focus posture is a **hard switch**: compositor/engine scope + shell job +
clear enter/exit — not a chrome skin or hypr fragment alone. Soft activity
overlays (`focus`, `present`, …) may sit *on* a posture later; they are not the
product story.

**Parked (thesis only):** `home` · `wearable` · `xr` · `vehicle` — do not market
or schedule until the focus three are undeniable.

**Four layers (do not collapse):**

| Layer | Meaning | Example |
|-------|---------|---------|
| **Device class** | What physical kind of machine is this? | `phone`, `laptop`, `tv`, `watch`, `server`, `hub` |
| **Posture** | What job is this machine doing? | `console`, `host`, `desktop` |
| **Device environment (kit)** | What hardware *this unit* actually has | TV + remote vs HTPC + gamepad |
| **Capabilities** | Normalized flags from kit + session | `display`, `gamepad`, `libvirt` |

**Phone** is a **device class**, not a posture. A pocket computer usually brings
`touch` + `battery` + cellular; apps/chrome **adapt** — see
[APPLICATIONS.md](./APPLICATIONS.md).

Same posture, different kits → different chrome and Settings panes, **same
identity**.

Apps are **one identity** that shape to the environment; they are not enabled
on every class/posture by default ([APPLICATIONS.md](./APPLICATIONS.md)).

Compositor engines: [COMPOSITOR.md](./COMPOSITOR.md).

> **Loader today:** `PROTEUS_SURFACE=desktop|console` (+ legacy `couch`→console);
> phone/vr/watch stubs remain. Hard console flip: `proteus-posture`. Soft profile:
> `set-hypr-profile.sh` → `profiles/console.conf`. See [§ Loader map](#9-loader-map-code-today).

## Document map

| Section | Contents |
|---------|----------|
| [1. Focus postures](#1-focus-postures) | Desktop · console · host |
| [2. Hard switches](#2-hard-switches) | What “mode change” means |
| [3. Device environments](#3-device-environments) | Variation within a posture |
| [4. Host vs home](#4-host-vs-home) | Lab box vs house brain (home parked) |
| [5. Host vs hypervisor](#5-host-vs-hypervisor) | Critical distinction |
| [6. Soft overlays](#6-soft-overlays) | Activity modes — not postures |
| [7. Shared vs varies](#7-shared-vs-varies) | Spine contract |
| [8. Capabilities](#8-capabilities) | Normalized flags |
| [9. Resolver](#9-resolver) | How posture + kit compose |
| [10. Loader map (code today)](#10-loader-map-code-today) | Legacy env / profile names |
| [11. Parked postures](#11-parked-postures) | Later jobs |
| [12. Proof order](#12-proof-order) | Discipline |
| [13. Non-goals](#13-non-goals) | Scope guards |

---

## 1. Focus postures

| Posture | Job | Chrome / engines | Status |
|---------|-----|------------------|--------|
| **desktop** | Create / windowed work (desk + laptop) | Full shell (bar, dock, Beacon); Hyprland tiling backend | `partial` — primary spine |
| **console** | Lean-back consume + play (TV, film, games) | Sparse ConsoleShell — tvOS-style shelf Home (cinematic Featured tracks focus, curated shelves, Library = full catalog), lean sheets; Hyprland kiosk + **supervised seat** (`proteus-console-seat`); **per-title Gamescope** when Vulkan usable; Guide / Super+Home | `partial` — Phase 1 seat/capabilities + console-smoke / INSTALL honesty shipped; full Gamescope *session* later |
| **host** | Operate the box (VMs, containers, services, updates) | Default lean/headless; **UI on demand** (local or remote) — not a DE clone; little/no creative chrome | `partial` (HostShell + `proteus-posture host` + `host.conf`) |

**Naming:** **Console** is the locked product name for lean-back. Legacy docs /
files may still say `media` / `couch` — treat them as aliases until renamed.

**Phone / tablet:** **device classes**, not postures. Do not invent a locked
“phone” posture. App adaptation: [APPLICATIONS.md](./APPLICATIONS.md).

Legacy loader `PROTEUS_SURFACE=phone` remains a stub only.

---

## 2. Hard switches

A focus posture change is a **session-level job flip**:

1. **Compositor / engine scope** changes (e.g. desktop Hyprland ↔ console
   game-scoped session ↔ host with little/no DE).
2. **Shell chrome** changes (full desktop QS ↔ sparse console shell ↔ host ops
   UI on demand or none).
3. **Enter / exit is intentional** — clear transition, not a mid-workflow theme
   toggle. Facts on disk (`settings.json`, …) survive; primary panes and input
   grammar follow the job.

Soft hypr profile reload alone is **not** enough for console or host. Profile
fragments may still express desktop tuning; they do not define the product flip.

Soft helper: `vm/guest/set-hypr-profile.sh desktop|console|media|host|home`
(`media` ≡ `console` → `profiles/console.conf`); Settings → About soft select
via `HyprProfile.qml` (soft≠hard). **Hard console switch:**
`vm/guest/proteus-posture console|desktop|host` — Fact + chrome restart + profile;
Beacon / Control Center / `Super+Shift+C` enter; console Desktop tile exits.
CC / Quick Settings prefer the **live tree** helper (`$PROTEUS_ROOT/vm/guest/…`)
over a stale `/usr/local` copy. Posture flips set
`PROTEUS_SKIP_SESSION_LOCK=1` so chrome does not re-lock mid-session (cold boot
still honors `lockOnSessionStart`). `proteus-qs --restart` waits for the flock
so a flip cannot leave a blank session with no chrome.

---

## 3. Device environments

Hardware kits **vary inside** a posture. Do not invent a new posture for every
SKU — invent **capability profiles**.

### Illustrative kits (focus)

| Posture | Kit A | Kit B | Kit C |
|---------|-------|-------|-------|
| **desktop** | Laptop (battery, single panel) | Desk (multi-mon, pointer) | Portable + touch |
| **console** | TV + remote | HTPC + gamepad | Projector + phone-as-remote |
| **host** | Headless rack / NUC | Host with local console display | Host + home radios (`home_control` — may later offer parked **home**) |

### What changes with the kit

| Same (posture) | Varies (capabilities → UI) |
|----------------|----------------------------|
| Job / Settings category emphasis | Whether Quickshell / which compositor run |
| Product identity | Which panes and chrome widgets exist |
| Config schema | Input grammar (touch, remote, voice, gamepad) |

Examples:

- Host **headless** → no desktop chrome; ops via SSH/web or a paired session.
- Host **with display** → same host job + local calm ops UI (not creative
  desktop unless the user also hard-switches to **desktop**).
- Console **with gamepad** → game-first grammar; console **with remote** →
  lean-back film/TV grammar — same posture.

#### Host: headless vs UI (same posture)

| Kit / access | Capabilities (typical) | What runs |
|--------------|------------------------|-----------|
| **Headless by default** | `headless` (or no local seat), `libvirt` / `containers`, … | Daemons always; no chrome until requested |
| **Terminal access** | SSH / serial / console TTY | Operator stays in the shell — no UI required |
| **UI on demand** | `display` and/or remote graphical session | Calm ops chrome / Settings **when someone asks for it** |
| **Host + home radios** | above + `home_control` | May later offer parked **home** on the same box |

**Access is not a fork of the product.** Prefer staying in **host** when UI
appears over silently becoming **desktop**.

Rule: **posture selects the job template; capabilities select the skin and
which engines start.**

---

## 4. Host vs home

**Home** is **parked** — not in the focus three. Kept here so the distinction
does not collapse into “server.”

| | **host** | **home** (parked) |
|--|----------|-------------------|
| **Job** | This machine’s lab/ops role | Orchestrate the house |
| **User feeling** | “My server / always-on box” | “My house brain / control panel” |
| **Primary panes** | Workloads, storage, network, updates | Devices, scenes, rooms, automations |
| **May share hardware** | Yes | Yes — home UI can be a later posture *on* a host |

Do not collapse smart-home into “just host” or erase host for CasaOS-only vibes.

---

## 5. Host vs hypervisor

| | Hypervisor / appliance (Proxmox, ESXi, …) | Proteus **host** posture |
|--|--|--|
| **Identity** | “I’m a virtualization product” | “I’m Proteus; this box is in host mode” |
| **Primary UI** | Datacenter console | Same Settings grammar + calm ops chrome |
| **Other postures** | Irrelevant | Same product family (**desktop**, **console**, …) |
| **Success** | Guests up, storage healthy | Box trustworthy *and* still Proteus |
| **Install** | Dedicated appliance image | Same base; role/posture hard-switches |
| **Virt / containers** | The product | A **capability** of the posture |

**One-liner:**

> A hypervisor *is* the virtualization layer as the OS.  
> Proteus host *uses* virtualization (and containers, packages, services) as
> tools while OS identity stays Proteus.

### Host must not be

- Proxmox with a prettier shell  
- Hyprland rice that embeds Portainer in the dock  
- A second ISO that forks the product  

Host chrome: **boring-trustworthy**. Stack when built: Tauri and/or Settings
panes ([STACK.md](./STACK.md)) — not Portainer-in-Quickshell.

---

## 6. Soft overlays

Activity environments (focus, present, meeting, …) are **optional overlays on a
posture**, not top-level postures and **not** substitutes for hard switches:

| Overlay | Typical posture | Intent |
|---------|-----------------|--------|
| **focus** | desktop | Hide chrome/noise; deep work |
| **present** | desktop (or console) | Clean screen, suppress toasts |
| **meeting** | desktop | Mic/cam affordances, DND |

Do **not** use a soft overlay for “game mode” — that is **console** (hard
switch). A desktop-only “fullscreen this title” affordance may exist later; it
is not the console job.

---

## 7. Shared vs varies

| Shared | Varies by posture |
|--------|-------------------|
| Config schema (`settings.json`) | Chrome layout |
| Theme tokens | Input grammar (pointer / touch / remote / gamepad) |
| Settings app + category IA | Which panes are **primary** |
| Session actions | Default density / focus |
| Keybind catalog (where input exists) | Which compositor / whether QS runs |

**Also varies by capability kit** (not only posture): chrome density, whether a
compositor starts, which Settings panes are enabled — see §3 / §8.

---

## 8. Capabilities

Coarse flags apps/OS use. **Full module catalog + baselines per device class:**
[HARDWARE.md](./HARDWARE.md).

Capabilities are **normalized flags** from hardware + session. They describe
*this device environment* inside a posture.

### Sensing / body

| Flag | Meaning |
|------|---------|
| `vitals` | HR / SpO₂ / similar streams |
| `imu` | Motion / orientation |
| `haptics` | Vibration feedback |

### I/O surfaces

| Flag | Meaning |
|------|---------|
| `display` | Local pixel output (any size) |
| `touch` / `pointer` / `remote` / `gamepad` | Input grammar |
| `mic` / `speaker` | Audio I/O (voice puck, calls) |
| `camera` | Local camera / passthrough |

### Compute / role

| Flag | Meaning |
|------|---------|
| `tiling` / `multi_monitor` | Desktop compositor features |
| `libvirt` / `containers` | Host workloads app (not Settings) |
| `home_control` | Speaks to house devices / hubs (parked **home** eligibility) |
| `headless` | No local interactive display session |
| `battery` | Portable power profile |
| `qs_hyprland` / `qs_pipewire` | Shell/audio engines available |
| `display_hotplug_fragile` | Plan QS respawn / degrade rearrange |
| `game_scope` *(planned)* | Console game-scoped compositor path available |

Compositor notes: [COMPOSITOR.md](./COMPOSITOR.md) § Capabilities.

---

## 9. Resolver

`planned`

```
hardware probe + role hint + user sticky
        ↓
  capability set (this device environment)
        ↓
  posture template (job) + hard-switch session
        ↓
  engines: Hyprland? game-scoped compositor? QS chrome? headless?
  Settings: which panes enabled / primary
```

Until then: `PROTEUS_SURFACE` legacy stub ([§10](#10-loader-map-code-today)) —
posture only, no capability profile; hypr profile helper is soft-only.

---

## 10. Loader map (code today)

| Focus posture | `PROTEUS_SURFACE` today | Hypr profile file | Notes |
|---------------|-------------------------|-------------------|--------|
| desktop | `desktop` | `profiles/desktop.conf` | Default |
| console | `console` (`couch` alias) | `profiles/console.conf` | Hard flip: `proteus-posture` (skip re-lock); shelf Home + Library/Search destinations + lean sheets |
| host | `host` | `profiles/host.conf` | Hard flip: `proteus-posture host`; lean HostShell (bar · CC · Beacon · lock); no workloads app yet |

| Parked / other | `PROTEUS_SURFACE` | Notes |
|----------------|-------------------|--------|
| wearable (parked) | `watch` | Stub only |
| xr (parked) | `vr` | Stub only |
| home (parked) | — | `profiles/home.conf` stub only |
| vehicle (parked) | — | No stub |
| *(unassigned)* | `phone` | Placeholder; not a posture |

---

## 11. Parked postures

Not in proof order. Do not schedule chrome or hard switches until focus three
are real.

| Posture | Job | Notes |
|---------|-----|--------|
| **home** | House brain / scenes / devices | Often on host hardware later |
| **wearable** | Micro / glance | Kit variance via capabilities |
| **xr** | Spatial / headset | Hard switch — see below |
| **vehicle** | Eyes-up, locked task set | Last — safety / partner gravity |

### Parked sketch — **xr** (not scheduled)

Same rule as console/host: **hard switch**, not a desktop skin in a headset.
Hardware (HMD, hands, eye/passthrough) is **delegated to the spatial job**.

#### Compute lanes — dumb peripheral vs all-in-one

VR/AR is splitting into two shipping shapes. Proteus should treat them as
**device environments** under the same **xr** posture — not two products:

| Lane | What the headset is | Where compute lives | Fit |
|------|---------------------|---------------------|-----|
| **1 · Dumb / tethered** | Display + sensors (+ optional light SoC) | **Host** — PC, phone, compute brick; optional mixed (encode on host, track on HMD) | Glasses-friendly; reuses Proteus **host** / desktop box as the brain — same pattern as streaming games to a headset today |
| **2 · All-in-one** | Integrated compute + sensors + radios | On the HMD | Easier for large headsets; harder for glasses (thermals, weight, battery) |

**Routing:** session resolver picks a **render/control path** (local SoC vs
stream-from-host vs split). Identity stays Proteus; the headset is often a
**capability kit** (`display` stereo, `imu`, hands, passthrough) attached to a
host or self-hosted. Do not fork “Proteus VR OS” vs “Proteus PC OS.”

Dumb lane strengthens **host** as first-class: always-on box or phone brick
runs the job; HMD is the spatial seat. All-in-one is the same posture with
compute on-kit. Mixed compute (tracking on glass, heavies on brick) is lane 1
with a sharper split — still one spine.

**Early test path (lane 1):** stream the Proteus **xr** session from a PC (or
host brick) to a Quest-class headset — OS/job runs on the computer; the headset
supplies display + built-in sensors / controllers for navigation and presence.
That is the practical dogfood loop before all-in-one or custom glasses: prove
shell HUD, Place/Follow, and hub contracts over a streamed seat, not by
rewriting the OS onto the HMD’s store runtime.

Likely layers when built:

| Layer | Role |
|-------|------|
| **Shell HUD** | Persistent system chrome (status, launcher affordance, Settings escape) — sparse, gaze/hand safe |
| **Spatial apps** | Windows / volumes in 3D space (shared spine, environment-shaped) |
| **Immersive / MR** | Full environment or passthrough mixed reality (Vision-Pro-class) |
| **Workspaces (two jobs)** | See below — not flat virtual-desktop clones |

#### Workspaces in XR — two functions

Do not collapse these into one metaphor:

| Kind | Sticks to | Feel | Example |
|------|-----------|------|---------|
| **Place workspace** | A room / persistent space | You walk into a job | Day: work-focused layout (docs, calendar, deep apps). Evening: chill layout (media, soft chrome) in the *same physical room* or a different saved place |
| **Follow workspace** | The person (on the move) | Iron Man / small-field carousel | Maps, music, messages orbit in a tight cone; appear when useful, dismiss or fade when you need spatial awareness — **never** block vision by default |

Place workspaces own **density and which apps live in the space**. Follow
workspaces own **glanceable companions** with aggressive hide/show and a narrow
FOV budget (carousel / radial around the user, not wall-sized panels in
passthrough).

#### Clutter valve — shell hub, not more panels

When companions multiply, they **collapse into the shell**, not into a forest of
Follow tiles:

| Surface | Job | Default |
|---------|-----|---------|
| **HUD** | Quick glanceable system facts (time, status, alerts) | Always sparse; never a full app |
| **Glanceable hub** | Shelved Follow apps / companions in one shell affordance | Collapsed; expand on intent |
| **Expanded hub / stage** | Flat spatial windows *or* vision-enriching XR overlays | Only while needed; dismiss returns to hub |

Apps may present as **flat windows** (readable, desktop-familiar) or as **MR
overlays** that enrich passthrough (directions on the street, captions, anchors)
— still one app identity, environment-shaped. The hub is the permission gate:
nothing stays in the FOV carousel unless the user (or a tight policy) promoted
it; everything else lives collapsed in the shell until expanded.

#### Hub clusters — activity kits (not new postures)

Hub contents are **grouped and swapped by job-in-the-moment**, not a flat junk
drawer of every app:

| Cluster / kit | Feel | Typical tools |
|---------------|------|----------------|
| **Everyday** | Casual carry | Messages, music, maps glance, clock |
| **Hike / trail** | Outdoors awareness | Maps/topo, weather, vitals, SOS — sparse FOV |
| **Task kits** | High-stakes or domain | Search-and-rescue, field medicine, etc. — curated tools only; noise banned |

Switching cluster is a **hub profile** (sticky or scene-triggered), still inside
**xr** — not a new locked posture per profession. Same hard-switch OS; different
**permission set** for what may enter HUD / Follow / expanded stage. Extreme
kits (battlefield, surgery) are the same pattern with stricter defaults: fewer
slots, stronger hide-for-awareness, explicit promote.

Capability kits on device ([§ Device environments](#3-device-environments))
still decide what *can* run; hub clusters decide what is *ready at a glance*
right now.

**Platform, not a kit catalog.** Proteus ships **defaults + contracts**
(guidelines, docs, APIs / manifests for what may enter HUD / Follow / expanded
stage, FOV and awareness rules). People and orgs **author their own clusters**
(everyday, hike, SAR, …). First-party kits are examples and hard defaults for
safety/awareness — not an exhaustive profession taxonomy. Same adaptive-app
idea: one identity, environment-shaped; availability and promote rules are the
product ([APPLICATIONS.md](./APPLICATIONS.md)).

Shared with the rest of Proteus: one app identity, environment-shaped; Settings /
facts still the bridge. Soft “focus mode” on desktop is not a substitute for
either workspace kind.

Do not prototype XR chrome on the desktop spine. Prove **desktop · console ·
host** first; XR inherits the hard-switch contract when its turn comes.

---

## 12. Proof order

1. **Desktop** spine undeniable (chrome + Settings + facts on disk)  
2. **Console** hard switch (game-scoped compositor + sparse shell) *or* **host**
   hard switch (lean/ops) — pick by dogfood wedge  
3. The remaining focus posture of the three  
4. Only then consider parked jobs (**home** first among them)

Do not market seven devices. Market **desk, console, host**. Prove hard
switches until each is obvious. Vary kits via capabilities, not extra postures.

---

## 13. Non-goals

- Soft chrome skins sold as posture flips  
- Cluster HA / Ceph / live migration as day-one host scope  
- Competing with Proxmox before host identity exists  
- Per-posture fork of settings files  
- Treating `PROTEUS_SURFACE` or soft hypr profile reload as the final architecture  
- Forking Hyprland or Quickshell to “become” the product  
- Turning focus/present/meeting into top-level postures  
- Using a soft “game-boost” overlay instead of **console**  
- Overloading **wearable** to mean phone  
- Treating **phone** as a locked posture instead of a device class  
- Collapsing **home** and **host** into one vague “server” SKU  
- One posture per hardware SKU  
- Forking apps per posture/device when one adaptive app can honor an environment contract  
- Marketing or building parked postures before the focus three  
