---
doc: facts
role: reference
audience: coding agents, contributors
last_updated: "2026-08-08"
doc_status: active
scope: On-disk truth paths; iced / shell-core vs services mutators
related:
  - CONFIG-SCHEMA.md
  - ARCHITECTURE.md
  - STACK.md
  - CURRENT.md
---

# Proteus — system facts

Truth lives on **disk / CLI**. UI (iced shell + Settings) and
`proteus-shell-core` are façades over these paths. Prefer this map before
inventing a second store.

## Paths

| Path | Owner (write) | Readers |
|------|---------------|---------|
| `~/.config/proteus/settings.json` | iced Settings / shell-core `settings-write` | Shell chrome, Settings, tokens |
| `~/.config/proteus/keybinds.json` | Settings / compositor | Session Super chords (overrides; defaults in `binds.rs`) |
| `~/.config/proteus/displays.json` | Settings Displays / `proteus-settings-apply` | Compositor modeset at start + live `output` |
| `~/.config/proteus/permissions.json` | `proteus-permissions.py` / Privacy panes (0600) | Gating, Ask prompt, portal sync, capture enforce — **not** in settings.json; see [CONFIG-SCHEMA.md](./CONFIG-SCHEMA.md) |
| `~/.local/share/proteus/auth/pin` | `proteus-pin.py` / `check-unlock.py` via `proteus_auth.py` (0600) | Lock unlock PIN hash — **not** in settings.json |
| `~/.cache/proteus/beacon-files.json` | `beacon-file-index.py` (rebuild/search) | Beacon Files home path cache |
| `~/.config/proteus/hw-probe.json` | `proteus-hw-probe` / shell-core cache | Gating, Settings About |
| `~/.config/proteus/hw.env` | `install/hardware/*` | GPU session envs (`NVD_BACKEND`, `LIBVA_*`, …); sourced by `proteus-session` (+ mirrored to `environment.d/90-proteus-hw.conf`) |
| `~/.config/proteus/session.env` | operator | Optional session overrides (e.g. `PROTEUS_DRM_TRANSFORM`); sourced after `hw.env` |
| `~/.config/proteus/compositor-engine` | install / session | `smithay` / `compositor` (alias `compositor-next`); `hyprland` refused |
| `~/.config/proteus/root` | `install/config.sh` | Session self-locate when env unset |
| `~/.config/proteus/posture` | `proteus-posture` | Hard-switch Fact (`desktop` \| `console` \| `host`); mid-session flips may set `PROTEUS_SKIP_SESSION_LOCK=1` outside managed sessions |
| `~/.config/proteus/host-chrome` | `proteus-posture host` (defaults `none`) / `--chrome` / `proteus-host-seat attach\|detach` | Host **seat chrome** Fact (`full` \| `none`); `none` = no seat / quiet wallpaper; `full` = ops UI attached |
| `~/.config/proteus/console-session-mode` | `proteus-console-session` | Legacy preference (`seat` \| `session`); shipping `sessionEffective` is always `seat` unless `PROTEUS_FORCE_GAMESCOPE=1` |
| `~/.config/proteus/game-present` | install seed / operator / compositor | Owned present JSON (`scale_mode` \| `fps_limit` \| `filter` \| `engine`); ctl `dispatch game-present` |
| `~/.config/proteus/gamescope-flags` | install seed / operator | Legacy nest argv for FORCE `proteus-gamescope` (default `-f`); override with `PROTEUS_GAMESCOPE_FLAGS` |
| `/run/user/$UID/proteus-console-seat.log` | `proteus-console-seat` | Console seat map/fullscreen trail (runtime) |
| `~/.local/share/proteus/backgrounds/` | wallpaper daily/album flows | `proteus-bg` / wallpaper runner |
| `~/.config/hypr/proteus-*.conf` | — | **Retired** (Hyprland purged; may linger on old disks — ignore) |

Seed templates: [`env/`](../../env/) — see [`env/README.md`](../../env/README.md).
Guest installers that **place** facts: [`install/machine/`](../../install/machine/).

## Ownership (hard)

| Module | Owns | Must not |
|--------|------|----------|
| **shell-core** | Typed facts R/W, schema keys, tokens (`env/chrome/`), gating, `proteus-open`, serve stream | Drawing chrome |
| **proteus-ui** | Shared iced theme + widgets from tokens | System facts |
| **Shell (`proteus-shell`)** | Presence chrome; reads facts / IPC | Sole copy of system truth |
| **Settings (sibling iced)** | Preference + maintenance IA | Drawing bar/dock |
| **Compositor** | Windowing; loads displays/keybinds Facts | Product identity |
| **Workloads** | Host glance + iced app via `proteus-workloads.py` | Auto-resolver · Portainer-style Settings UI |
| **Accounts** | Online-accounts vault + PKCE via `proteus-accounts` | OAuth secrets in `settings.json` |

## UI vs services

| Kind | Stack | Rule |
|------|-------|------|
| Preference / chrome state | iced + shell-core | One Config schema; mutate via facts writers or thin helpers |
| Read-only discovery | Python OK (`services/proteus-hw-probe`) | JSON out; no privileged write |
| Privileged mutation | Rust CLI (`proteus-pkg`, `proteus-logind`, `proteus-battery-threshold`, `proteus-greetd`, …) + polkit | Settings proposes → confirm → helper |
| Online accounts seats | Rust CLI `proteus-accounts` (user vault; no polkit) | Tokens outside `settings.json` |
| Hot-path read (mixer) | Rust resident `proteus-audio-mix serve` (+ Python fallback) | Dump+peaks while Mixer open |
| Power mode (PPD) | `powerprofilesctl` / `power-profiles-daemon` | Eco = `power-saver` |
| Battery charge limits | `proteus-battery-threshold` → sysfs when present | Fail closed on unsupported hardware |

**Do not** add silent Python helpers for privileged mutation. **Do not** grow a
second `settings-*.json` per posture.

## Layout (code)

```
services/proteus-shell-core/   # facts · tokens · gating · proteus-open · serve
services/proteus-ui/           # shared iced kit
shell/                         # proteus-shell chrome
compositor/                    # proteus-compositor
../ProteusSettings             # proteus-settings-next
../ProteusWorkloads            # proteus-workloads
```

Schema key groups: [CONFIG-SCHEMA.md](./CONFIG-SCHEMA.md).
