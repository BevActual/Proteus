---
doc: positioning
role: external-summary
audience: contributors, partners, future public copy
last_updated: "2026-07-26"
doc_status: active
scope: Product thesis, field comparison, differentiator, non-goals
related:
  - ARCHITECTURE.md
  - POSTURES.md
  - COMPOSITOR.md
  - STACK.md
  - CURRENT.md
  - ../shared/ECOSYSTEM.md
---

# Proteus — positioning

**Bevington Systems** — an adaptive Linux environment that reshapes itself to
**where you are** and **what this machine’s job is**.

| Detail | Document |
|--------|----------|
| Architecture | [ARCHITECTURE.md](./ARCHITECTURE.md) |
| Postures (incl. host) | [POSTURES.md](./POSTURES.md) |
| What’s built | [CURRENT.md](./CURRENT.md) |

## Document map

| Section | Contents |
|---------|----------|
| [1. What it is](#1-what-it-is) | One paragraph |
| [2. North star](#2-north-star) | Hybrid UX lock |
| [3. What it is not](#3-what-it-is-not) | Boundaries |
| [4. Field](#4-field) | Convergence · platforms · ops |
| [5. Differentiator](#5-differentiator) | Role-adaptive Linux |
| [6. Proof order](#6-proof-order) | How we earn the thesis |
| [7. Taglines](#7-taglines) | Optional copy |

---

## 1. What it is

**Proteus** is a single Arch-based environment (Quickshell chrome + Hyprland +
a real Settings control center) that changes **posture** — desktop, media,
wearable, XR, vehicle, home controller, or **host** — without shipping seven
distros. Posture means **hardware capabilities + intended use**, not just
screen size.

---

## 2. North star

> **Linux under the hood, Mac in the hand.**  
> Settings is the bridge: every elegant control maps to an inspectable,
> overrideable system fact.

- **Defaults** feel calm and predictable (dock, launcher, Style, Keyboard).
- **Power** stays Linux-native (real conf files, CLI, packages, virt).
- **One spine** across postures; chrome and primary panes change, identity does not.

---

## 3. What it is not

- Not “yet another Hyprland rice” as the product story
- Not a Proxmox/CasaOS competitor whose only job is VMs
- Not an Apple/Google-style family of forked OSes
- Not five device SKUs marketed as one slogan
- Not a reimplementation of Meridian (models) or Mobius (agent loop)

---

## 4. Field

### Classic personal convergence

| Player | Idea | vs Proteus |
|--------|------|------------|
| Lomiri / Ubuntu Touch | One Linux shell; phone↔desktop | Same personal slogan; no VR/watch/**host** thesis |
| KDE Plasma + Mobile | Shared tech, related shells | Family of products more than one adaptive identity |
| Samsung DeX / Continuum | Phone becomes desktop when docked | Ecosystem-locked; niche or dead |
| SteamOS (Deck) | Handheld ↔ desktop mode | Best modern posture flip — gaming-only |

**Verdict:** “Shell on phone and desktop” is a known, hard, partially occupied
lane. Most attempts stalled on apps, drivers, and focus — not the slogan.

### Big platforms

Apple / Google / Microsoft validate **adaptation** as the UX problem, but solve
it with **ecosystem gravity + separate SKUs**. Proteus plays Linux/indie rules:
**one base, reshape in place.**

### Ops / home-lab

| Player | Idea | vs Proteus |
|--------|------|------------|
| Ubuntu Server / RHEL | Same family, different install mindset | Soft fork of role |
| Proxmox, TrueNAS, Unraid | Appliance OS for VMs/storage | Excellent ops — not a personal surface OS |
| CasaOS, Umbrel, StartOS | Friendly home-lab dashboards | Ops UX, not multi-posture personal OS |

**Verdict:** Almost nobody sells one consumer-grade adaptive OS whose postures
include both “I’m at a desk” and “this box runs VMs/containers.”

```
                  Personal postures          Host / ops role
Lomiri / Plasma        strong                     empty
SteamOS                niche (game)               empty
Proxmox / CasaOS       empty                      strong
Apple family           strong (forked)            empty
Proteus (disciplined)  strong                     strong
Proteus (unfocused)    “another shell”            “Portainer rice”
```

---

## 5. Differentiator

**Crowded:** shell that works on phone and desktop.  
**Open:** unified OS identity that changes **job** — desk, living room, house,
or host — without seven distros.

Differentiator is not Hyprland + Quickshell. It is:

> **Posture = hardware + intended use**, with **host** and **home** as
> first-class jobs — not afterthought ISOs.

Those tools are **backends** under compositor postures
([COMPOSITOR.md](./COMPOSITOR.md)). Hypervisor **tech** (KVM, containers) may
power host mode. A **hypervisor product** (Proxmox et al.) *is* virtualization
as the OS. Locked set: [POSTURES.md](./POSTURES.md).

App/chrome languages: [STACK.md](./STACK.md).

---

## 6. Proof order

1. **Desktop spine** undeniable (chrome + Settings + facts on disk) — *in progress*
2. **Media** *or* **host** as second real posture  
3. **Home** hub UI (often on host hardware); then wearable / XR / vehicle  

Do not market seven devices. Market **one system that changes job**, and prove
postures few until each is obvious.

---

## 7. Taglines

- One system. Many jobs.
- Linux under the hood. Mac in the hand.
- Same OS at the desk, on the couch, or as the host.
