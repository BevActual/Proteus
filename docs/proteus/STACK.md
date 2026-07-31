---
doc: stack
role: reference
audience: contributors, coding agents
last_updated: "2026-07-29"
doc_status: active
scope: Languages and runtimes by layer — what to build in what
related:
  - ARCHITECTURE.md
  - COMPOSITOR.md
  - SETTINGS-IA.md
  - APPLICATIONS.md
  - CURRENT.md
  - ../shared/ECOSYSTEM.md
---

# Proteus — language / stack

Do **not** pick one language for the whole OS. Split by layer.
Adaptive app behavior (one identity, environment-shaped): [APPLICATIONS.md](./APPLICATIONS.md).

## Document map

| Section | Contents |
|---------|----------|
| [1. Rule](#1-rule) | One-liner |
| [2. By layer](#2-by-layer) | Default stack table |
| [3. Why not all-X](#3-why-not-all-x) | Rejected monocultures |
| [4. New work defaults](#4-new-work-defaults) | Practical choice guide |
| [5. Sibling alignment](#5-sibling-alignment) | Rowena / Meridian |
| [6. Exceptions log](#6-exceptions-log) | Blessed deviations |

---

## 1. Rule

> **If it’s the OS looking at you → QML (Quickshell).**  
> **If it’s a product window the user runs → Tauri (TypeScript + Rust).**  
> **If it’s a daemon/CLI that mutates the system → Rust.**  
> **Hardware / environment probes may be Python** until promoted to Rust
> (explicit exception — see §2).

---

## 2. By layer

| What you’re building | Stack | Why |
|----------------------|-------|-----|
| Shell chrome (bar, dock, launcher, overlays) | **QML / Quickshell** | Wayland layer-shell; Hyprland integrations |
| System control center (`proteus-settings`) | **QML / Quickshell** *(today)* | Same tokens/spine; may revisit Tauri if FloatingWindow lifecycle hurts |
| **Hardware / env probes** (read-only discovery → JSON) | **Python** *(blessed)* | Fast to iterate; `proteus-hw-probe` Wave A. **Rust rewrite candidate** when schema stabilizes or we need a single static binary on guests |
| System helpers that **mutate** state (apply config, pacman wrappers, privileged ops) | **Rust** small CLIs (+ bash when tiny) | Thin, smokeable; keeps QML dumb (Meridian habit). Examples: `services/proteus-pkg`, `services/proteus-logind` + polkit, `services/proteus-accounts` (user-scoped OAuth vault) |
| Hot-path session helpers (mixer dump/peaks, …) | **Rust** resident CLI (`serve`) | Spawned while Settings leaf open; NDJSON to QML. Example: `services/proteus-audio-mix` |
| First-party Proteus apps (Files, Host console, …) | **TypeScript + Tauri (Rust)** | Matches **Rowena**; not shell chrome |
| Host / ops backends (libvirt, containers, status) | **Rust** services or existing Linux tools behind a thin API | Trust + long-running; UI is Tauri or Settings |

Truth stays on **disk / CLI** regardless of UI stack ([ARCHITECTURE.md](./ARCHITECTURE.md) HARD RULES).

Do **not** grow silent Python helpers for privileged mutation — that stays Rust (or tiny bash). Probes are the documented Python lane.

---

## 3. Why not all-X

| Monoculture | Problem |
|-------------|---------|
| All QML | Great for DE chrome; poor match to Rowena; weak default for rich product apps |
| All Electron | Heavy; fights “elegant Linux”; diverges from Tauri siblings |
| All Rust GUI (egui/iced) | Fine for tools; wrong default for Mac-smooth Settings + multi-posture chrome |
| Fork Quickshell into an app framework | Fights upstream intent; see [COMPOSITOR.md](./COMPOSITOR.md) |

---

## 4. New work defaults

1. New **Settings pane** → QML module + optional helper (Python probe / Rust mutator / resident serve)
2. New **Proteus app** → Tauri + TS, theme aligned with Proteus tokens
3. New **mutating system capability** → Rust CLI that Settings/apps call
4. New **read-only discovery** → Python probe OK (log in §6 if long-lived)
5. Prefer **built-in Quickshell integrations** (PipeWire, tray, UPower, …) before new daemons — until the fact is privileged, multi-consumer, or a hot poll path (then Rust `serve`)
6. New **hot-path poll** (mixer peaks/dump, …) → Rust resident helper while the leaf is open; keep mutations thin

---

## 5. Sibling alignment

| Product | Stack reminder |
|---------|----------------|
| **Rowena** | Tauri + TypeScript (+ Rust) |
| **Meridian** | Rust crates / hub listen |
| **Mobius** | Docs + TS/JS packages / scripts |
| **Proteus** | Quickshell chrome + Tauri apps + Rust mutators + Python probes |

Proteus apps should feel like Bevington software running *on* Proteus — not a
second DE written only in QML. Prefer **one adaptive app** per product
([APPLICATIONS.md](./APPLICATIONS.md)), not per-device forks.

---

## 6. Exceptions log

| Exception | Status | Notes |
|-----------|--------|-------|
| `services/proteus-hw-probe` in Python | `blessed` | Read-only Wave A probe; Rust rewrite when schema/packaging demands it |
| Trivial one-liner bash from QML (`hyprctl`, `pactl`) | `blessed` | Not “helpers” — direct apply |
| Settings still Quickshell (not Tauri) | `blessed` for now | Revisit if FloatingWindow lifecycle hurts |