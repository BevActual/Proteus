---
doc: postures
role: architecture
audience: architects, contributors, coding agents
last_updated: "2026-07-26"
doc_status: active
scope: Locked posture set; host vs home vs hypervisor; session modes; resolver
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
  legacy: Old loader name; map to locked posture
---

# Postures — hardware + intended use

A **posture** is the machine’s current **job**, driven by capabilities and
intent — not a CSS breakpoint and not a separate distro.

**Four layers (do not collapse):**

| Layer | Meaning | Example |
|-------|---------|---------|
| **Device class** | What physical kind of machine is this? | `phone`, `laptop`, `tv`, `watch`, `server`, `hub` |
| **Posture** | What job is this machine doing? | `media`, `home`, `host` |
| **Device environment (kit)** | What hardware *this unit* actually has | Band with vitals only vs watch with display |
| **Capabilities** | Normalized flags from kit + session | `display`, `vitals`, `mic`, `touch`, `libvirt` |

**Phone** is a **device class**, not a locked posture. A pocket computer usually
brings `touch` + `battery` + cellular, and apps/chrome **adapt** to that
environment — see [APPLICATIONS.md](./APPLICATIONS.md).

Same posture, different kits → different chrome and Settings panes, **same
identity**. A home controller with a screen is still `home`; one that is
speaker + mic only is still `home` — headless/voice chrome, not a new posture.

Apps are **one identity** that shape to the environment; they are not enabled
on every class/posture by default ([APPLICATIONS.md](./APPLICATIONS.md)).

**Locked postures:**  
`desktop` · `media` · `wearable` · `xr` · `vehicle` · `home` · `host`

Session modes (not postures): `focus` · `present` · `meeting` · … — sit *on*
desktop/media, etc.

Compositor engines: [COMPOSITOR.md](./COMPOSITOR.md).

> **Code stub today:** `PROTEUS_SURFACE=desktop|phone|vr|couch|watch` still loads
> placeholder QML. See [§ Loader map](#9-loader-map-code-today) until renamed.

## Document map

| Section | Contents |
|---------|----------|
| [1. Locked postures](#1-locked-postures) | The seven |
| [2. Device environments](#2-device-environments) | Variation within a posture |
| [3. Host vs home](#3-host-vs-home) | Lab box vs house brain |
| [4. Host vs hypervisor](#4-host-vs-hypervisor) | Critical distinction |
| [5. Session modes](#5-session-modes) | Activity overlays |
| [6. Shared vs varies](#6-shared-vs-varies) | Spine contract |
| [7. Capabilities](#7-capabilities) | Normalized flags |
| [8. Resolver](#8-resolver) | How posture + kit compose |
| [9. Loader map (code today)](#9-loader-map-code-today) | Legacy env names |
| [10. Proof order](#10-proof-order) | Discipline |
| [11. Non-goals](#11-non-goals) | Scope guards |

---

## 1. Locked postures

| Posture | Job | Chrome density | Status |
|---------|-----|----------------|--------|
| **desktop** | Create / windowed work (desk + laptop) | Full shell (bar, dock, launcher) | `partial` — primary |
| **media** | Lean-back consume + play (TV, film, games on the couch) | Sparse, remote/gamepad-friendly | `planned` (code stub: `couch`) |
| **wearable** | Micro / glance (watch-class) | Minimal | `planned` (code stub: `watch`) |
| **xr** | Spatial / headset | Immersive | `planned` (code stub: `vr`) |
| **vehicle** | Eyes-up, voice, locked task set | Automotive-safe, sparse | `planned` |
| **home** | Home environment controller (scenes, devices, house status) | Hub / panel UI — calm, glanceable | `planned` |
| **host** | Operate the box (VMs, containers, services, updates) | Default lean/headless; **UI on demand** (local or remote) — not a DE clone | `planned` |

**Phone / tablet:** **device classes**, not locked postures. They contribute
capabilities (`touch`, `battery`, …) and shape app/chrome density. Do not
overload **wearable** to mean phone. App adaptation:
[APPLICATIONS.md](./APPLICATIONS.md).

Legacy loader `PROTEUS_SURFACE=phone` remains a stub only — not part of the
locked posture set.

---

## 2. Device environments

Hardware kits **vary inside** a posture. Do not invent a new posture for every
SKU — invent **capability profiles**.

### Illustrative kits

| Posture | Kit A | Kit B | Kit C |
|---------|-------|-------|-------|
| **wearable** | Vitals band (HR, SpO₂) — no display | Watch with display + crown/touch | Display + mic/speaker (audio glance) |
| **home** | Headless hub (network only) | Wall tablet (display + touch) | Speaker / voice puck (mic + speaker, no screen) |
| **media** | TV + remote | HTPC + gamepad | Projector + phone-as-remote |
| **host** | Headless rack / NUC | Host with local console display | Host + home radios (also `home_control`) |
| **desktop** | Laptop (battery, single panel) | Desk (multi-mon, pointer) | Portable + touch |
| **xr** | Headset only | Headset + hand tracking | Headset + passthrough cameras |
| **vehicle** | Head unit display | Display + wheel controls | Voice-primary + minimal cluster |

### What changes with the kit

| Same (posture) | Varies (capabilities → UI) |
|----------------|----------------------------|
| Job / Settings category emphasis | Whether Quickshell/Hyprland run at all |
| Product identity (“I’m Proteus home”) | Which panes and chrome widgets exist |
| Config schema | Input grammar (touch, remote, voice, vitals stream) |

Examples:

- Wearable **without** `display` → no compositor shell; complications / haptics /
  companion glance only.  
- Wearable **with** `display` → tiny chrome; vitals widgets if `vitals` present.  
- Home **with** `display`+`touch` → panel UI.  
- Home **with** `mic`+`speaker` only → voice surface; Settings still reachable
  from another Proteus device on the same account/spine.  
- Host **headless** → no desktop chrome; ops via Settings-over-SSH/web or a
  paired desktop session.
- Host **with display** → same host job + local calm ops UI (not a full
  creative desktop unless the user also switches posture).

#### Host: headless vs UI (same posture)

| Kit / access | Capabilities (typical) | What runs |
|--------------|------------------------|-----------|
| **Headless by default** | `headless` (or no local seat), `libvirt` / `containers`, … | Daemons always; no chrome until requested |
| **Terminal access** | SSH / serial / console TTY | Operator stays in the shell — no UI required |
| **UI on demand** | `display` and/or remote graphical session | Calm ops chrome / Settings **when someone asks for it** |
| **Host + home radios** | above + `home_control` | May also offer **home** posture on the same box |

**Access is not a fork of the product.** Two operators on the same host:

- Remoter A: SSH only → terminal, scripts, `journalctl` — never starts QS/Hyprland.  
- Operator B: local seat or “open host UI” → brings up ops chrome to navigate workloads,
  storage, updates — still **host**, not **desktop**.

UI is an **optional session surface** on host (capability + intent), not a permanent
SKU. Defaults can stay headless for always-on boxes; “bring the UI up when you
want” is first-class.

Prefer staying in **host** when the UI appears over silently becoming **desktop**,
so lab machines don’t grow a rice DE by accident.

Rule: **posture selects the job template; capabilities select the skin and
which engines start.**

---

## 3. Host vs home

| | **host** | **home** |
|--|----------|----------|
| **Job** | This machine’s lab/ops role | Orchestrate the house |
| **User feeling** | “My server / always-on box” | “My house brain / control panel” |
| **Primary panes** | Workloads, storage, network, updates | Devices, scenes, rooms, automations |
| **May share hardware** | Yes — same always-on PC can run both | Yes — home UI can be a posture *on* a host |

They are **different jobs**. One box may offer both (capabilities: `libvirt` +
`home_control`), but do not collapse smart-home into “just host” or erase host
for CasaOS-only vibes.

---

## 4. Host vs hypervisor

| | Hypervisor / appliance (Proxmox, ESXi, …) | Proteus **host** posture |
|--|--|--|
| **Identity** | “I’m a virtualization product” | “I’m Proteus; this box is in host mode” |
| **Primary UI** | Datacenter console | Same Settings grammar + calm ops chrome |
| **Other postures** | Irrelevant | Same product family (desktop, media, home, …) |
| **Success** | Guests up, storage healthy | Box trustworthy *and* still Proteus |
| **Install** | Dedicated appliance image | Same base; role/posture flips |
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

## 5. Session modes

Activity environments users want (focus, present, meeting, …) are **modes on a
posture**, not top-level postures:

| Mode | Typical host posture | Intent |
|------|----------------------|--------|
| **focus** | desktop | Hide chrome/noise; deep work |
| **present** | desktop (or media) | Clean screen, suppress toasts |
| **meeting** | desktop | Mic/cam affordances, DND |
| **game-boost** | media or desktop | Optional compositor/gamepad emphasis |

---

## 6. Shared vs varies

| Shared | Varies by posture |
|--------|-------------------|
| Config schema (`settings.json`) | Chrome layout |
| Theme tokens | Input grammar (pointer / touch / remote / voice) |
| Settings app + category IA | Which panes are **primary** |
| Session actions | Default density / focus |
| Keybind catalog (where input exists) | Whether a full Hyprland+QS session runs |

**Also varies by capability kit** (not only posture): chrome density, whether a
compositor starts, which Settings panes are enabled — see §2 / §7.

---

## 7. Capabilities

Coarse flags apps/OS use. **Full module catalog + baselines per device class:**
[HARDWARE.md](./HARDWARE.md).

Capabilities are **normalized flags** from hardware + session. They describe
*this device environment* inside a posture. Modules (e.g. `sensor.hr`,
`input.touch`) map → capabilities (e.g. `vitals`, `touch`).

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
| `libvirt` / `containers` | Host workloads |
| `home_control` | Speaks to house devices / hubs |
| `headless` | No local interactive display session |
| `battery` | Portable power profile |
| `qs_hyprland` / `qs_pipewire` | Shell/audio engines available |
| `display_hotplug_fragile` | Plan QS respawn / degrade rearrange |

Compositor notes: [COMPOSITOR.md](./COMPOSITOR.md) § Capabilities.

---

## 8. Resolver

`planned`

```
hardware probe + role hint + user sticky
        ↓
  capability set (this device environment)
        ↓
  posture template (job) + session mode defaults
        ↓
  engines: Hyprland? QS chrome? voice-only? vitals agent?
  Settings: which panes enabled / primary
```

Until then: `PROTEUS_SURFACE` legacy stub ([§9](#9-loader-map-code-today)) —
posture only, no capability profile.

---

## 9. Loader map (code today)

| Locked posture | `PROTEUS_SURFACE` today | Notes |
|----------------|-------------------------|--------|
| desktop | `desktop` | Default |
| media | `couch` | Rename when shell lands |
| wearable | `watch` | Rename when shell lands |
| xr | `vr` | Rename when shell lands |
| vehicle | — | No stub yet |
| home | — | No stub yet |
| host | — | No stub yet |
| *(unassigned)* | `phone` | Placeholder only; not in locked set |

---

## 10. Proof order

1. **Desktop** spine undeniable  
2. **Media** *or* **host** as second real posture (pick by dogfood: living room vs lab)  
3. **Home** as hub UI (often on host hardware) — including headless vs panel kits  
4. **Wearable** / mobile story — including vitals-only vs display kits  
5. **XR**  
6. **Vehicle** last (safety / partner gravity)  

Do not market seven devices. Market **jobs**; prove few until each is obvious.
Vary kits via capabilities, not extra postures.

---

## 11. Non-goals

- Cluster HA / Ceph / live migration as day-one host scope  
- Competing with Proxmox before host identity exists  
- Per-posture fork of settings files  
- Treating `PROTEUS_SURFACE` as the final architecture  
- Forking Hyprland or Quickshell to “become” the product  
- Turning focus/present/meeting into top-level postures  
- Overloading **wearable** to mean phone  
- Treating **phone** as a locked posture instead of a device class  
- Collapsing **home** and **host** into one vague “server” SKU  
- One posture per hardware SKU (vitals band ≠ new posture; it’s `wearable` − `display` + `vitals`)  
- Forking apps per posture/device (“Rowena Phone” as a separate product) when one adaptive app can honor an environment contract  
