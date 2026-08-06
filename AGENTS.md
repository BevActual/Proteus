# AGENTS.md

Proteus agent entry (federated homes · lock **e**). **This repo** = adaptive
host OS (shell, Settings, postures, VM harness).

**Company loop SoT** stays in the sibling Mobius repo — do not invent a second
full PLAYBOOK or queue here. Override sibling paths with `MOBIUS_ROOT` /
`ROWENA_ROOT` / `MERIDIAN_ROOT` / `PROTEUS_ROOT` / `PROTEUS_WORKLOADS_ROOT` /
`PROTEUS_SETTINGS_ROOT` when needed.

| Concern | Where |
|---------|--------|
| Company queue / Track / Cards | [`../Mobius/docs/ISSUES.md`](../Mobius/docs/ISSUES.md) |
| Kickoffs (`loop`, `standing`, …) | [`../Mobius/AGENTS.md`](../Mobius/AGENTS.md) |
| Thin local queue pointer | [docs/ISSUES.md](docs/ISSUES.md) |
| Positioning / field | [docs/proteus/POSITIONING.md](docs/proteus/POSITIONING.md) |
| Architecture / HARD RULES | [docs/proteus/ARCHITECTURE.md](docs/proteus/ARCHITECTURE.md) |
| Postures (host vs hypervisor) | [docs/proteus/POSTURES.md](docs/proteus/POSTURES.md) |
| Adaptive apps / environment | [docs/proteus/APPLICATIONS.md](docs/proteus/APPLICATIONS.md) |
| Hardware / sensors / modules | [docs/proteus/HARDWARE.md](docs/proteus/HARDWARE.md) |
| Hyprland + owned chrome | [docs/proteus/COMPOSITOR.md](docs/proteus/COMPOSITOR.md) |
| Languages / stack | [docs/proteus/STACK.md](docs/proteus/STACK.md) |
| Owned-stack endgame (sequencing) | [docs/proteus/OWNED-STACK.md](docs/proteus/OWNED-STACK.md) |
| Settings IA | [docs/proteus/SETTINGS-IA.md](docs/proteus/SETTINGS-IA.md) |
| Chrome / design lock | [docs/proteus/CHROME.md](docs/proteus/CHROME.md) · [`proteus-ui`](services/proteus-ui) |
| System facts / schema | [docs/proteus/FACTS.md](docs/proteus/FACTS.md) · [CONFIG-SCHEMA.md](docs/proteus/CONFIG-SCHEMA.md) |
| Honest status | [docs/proteus/CURRENT.md](docs/proteus/CURRENT.md) |
| Ecosystem seat | [docs/shared/ECOSYSTEM.md](docs/shared/ECOSYSTEM.md) |
| VM dogfood | [dev/vm/README.md](dev/vm/README.md) |

| Sibling | Entry |
|---------|--------|
| Mobius (loop SoT) | [`../Mobius/AGENTS.md`](../Mobius/AGENTS.md) · [`../Mobius/docs/ISSUES.md`](../Mobius/docs/ISSUES.md) |
| Meridian (hub) | [`../Meridian/AGENTS.md`](../Meridian/AGENTS.md) |
| Rowena (writing) | [`../Rowena/AGENTS.md`](../Rowena/AGENTS.md) |
| ProteusWorkloads (iced Workloads app) | [`../ProteusWorkloads/AGENTS.md`](../ProteusWorkloads/AGENTS.md) |
| ProteusSettings (iced Settings app) | [`../ProteusSettings/AGENTS.md`](../ProteusSettings/AGENTS.md) |

## Product kickoffs

- **`install`** — overlay (VM + bare metal): `install/bootstrap.sh`; helpers `install/machine/`; runtime helpers `shell/scripts/`; SoT: [docs/proteus/INSTALL.md](docs/proteus/INSTALL.md).
- **`vm`** — boot guest: `./dev/vm/run.sh`; provision: `./dev/vm/provision.sh`; artifacts in `PROTEUS_VM_CACHE`; overlay `install/`; helpers `install/machine/`; install path SoT: [docs/proteus/INSTALL.md](docs/proteus/INSTALL.md).
- **`nested`** — host quick shell test: `./dev/run-nested.sh` (compositor-next winit; Hyprland purged).
- **`probe`** — Wave A hardware JSON: `./services/proteus-hw-probe/proteus-hw-probe` · smoke: `./dev/smoke/hw-probe-smoke.sh`
- **`smoke`** — host suite: `./dev/smoke-all.sh` (shellcheck · doc-links · layout · ipc-contract · config-schema · chrome-tokens · shell-core · shell · shell-owned-dogfood · settings-next · install · session · …; guest `owned-guest` + `software-guest` + `console-guest` + `host-guest` if SSH `:2222` or `PROTEUS_GUEST=1`). QML leaf smokes are retired stubs.
- **`settings`** — iced sibling `../ProteusSettings` (`proteus-settings-next`) via `proteus-settings` only; QML Settings deleted.
- **`shell`** — owned iced session in `shell/` (`proteus-shell`) via `proteus-chrome` only; faces under `shell/src/faces/` (desktop shipping; console/host thin stubs to rebuild). Quickshell chrome retired.
- **`loop` / `standing` / …** — follow **Mobius** `AGENTS.md`; Proteus items may be queued there with home: Proteus.

## Gates (honest)

| Change | Gate |
|--------|------|
| Shell / Settings | Dogfood in VM or nested; `./dev/smoke-all.sh`; update CURRENT if behavior ships |
| Layout / schema / install | `./dev/smoke/layout-smoke.sh` · `./dev/smoke/config-schema-smoke.sh` · `./dev/smoke/install-smoke.sh` |
| Guest scripts | Run on guest; don’t leave keybinds under `/root` when using sudo |
| Docs-only | Keep POSITIONING/CURRENT status legends honest |

## Out (do not invent here)

Meridian hub HTTP API, Mobius referee/queue SoT, Rowena vault/editor, a second
hypervisor distro, seven marketed postures before desktop·console·host are proven,
forking Hyprland/Quickshell (owned replacements land per
[OWNED-STACK.md](docs/proteus/OWNED-STACK.md) — replace behind contracts, never
carry patches; no rung starts before the one below passes its gates), Electron
as default app stack.
