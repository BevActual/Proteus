# AGENTS.md

Proteus agent entry (federated homes · lock **e**). **This repo** = adaptive
host OS (shell, Settings, postures, VM harness).

**Company loop SoT** stays in the sibling Mobius repo — do not invent a second
full PLAYBOOK or queue here. Override sibling paths with `MOBIUS_ROOT` /
`ROWENA_ROOT` / `MERIDIAN_ROOT` / `PROTEUS_ROOT` when needed.

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
| Hyprland + Quickshell | [docs/proteus/COMPOSITOR.md](docs/proteus/COMPOSITOR.md) |
| Languages / stack | [docs/proteus/STACK.md](docs/proteus/STACK.md) |
| Settings IA | [docs/proteus/SETTINGS-IA.md](docs/proteus/SETTINGS-IA.md) |
| Chrome / design lock | [docs/proteus/CHROME.md](docs/proteus/CHROME.md) · [`Theme.qml`](shell/shared/Theme.qml) |
| System facts / schema | [docs/proteus/FACTS.md](docs/proteus/FACTS.md) · [CONFIG-SCHEMA.md](docs/proteus/CONFIG-SCHEMA.md) |
| Honest status | [docs/proteus/CURRENT.md](docs/proteus/CURRENT.md) |
| Ecosystem seat | [docs/shared/ECOSYSTEM.md](docs/shared/ECOSYSTEM.md) |
| VM dogfood | [vm/README.md](vm/README.md) |

| Sibling | Entry |
|---------|--------|
| Mobius (loop SoT) | [`../Mobius/AGENTS.md`](../Mobius/AGENTS.md) · [`../Mobius/docs/ISSUES.md`](../Mobius/docs/ISSUES.md) |
| Meridian (hub) | [`../Meridian/AGENTS.md`](../Meridian/AGENTS.md) |
| Rowena (writing) | [`../Rowena/AGENTS.md`](../Rowena/AGENTS.md) |

## Product kickoffs

- **`vm`** — boot guest: `./vm/run.sh`; provision: `./vm/provision.sh`; artifacts in `PROTEUS_VM_CACHE`; overlay `vm/install/`; helpers `vm/guest/`; install path SoT: [docs/proteus/INSTALL.md](docs/proteus/INSTALL.md).
- **`nested`** — host quick shell test: `./scripts/run-nested.sh`.
- **`probe`** — Wave A hardware JSON: `./services/proteus-hw-probe/proteus-hw-probe` · smoke: `./scripts/smoke/hw-probe-smoke.sh`
- **`smoke`** — host suite: `./scripts/smoke-all.sh` (layout · widget-layout-resolve · ipc-contract · config-schema · config-roundtrip · app-manifest · chrome-tokens · software-reliability · power-logind · accounts · lock-pin · permissions · desktop · beacon · audio-mix-serve · hw-probe · install · session · posture-hard · console · qs-version; guest `qs-guest` + `software-guest` if SSH `:2222` or `PROTEUS_GUEST=1`)
- **`settings`** — work in `apps/proteus-settings/` + `shell/shared` (symlink).
- **`shell`** — Quickshell chrome only; do not grow product apps here ([STACK.md](docs/proteus/STACK.md)).
- **`loop` / `standing` / …** — follow **Mobius** `AGENTS.md`; Proteus items may be queued there with home: Proteus.

## Gates (honest)

| Change | Gate |
|--------|------|
| Shell / Settings | Dogfood in VM or nested; `./scripts/smoke-all.sh`; update CURRENT if behavior ships |
| Layout / schema / install | `./scripts/smoke/layout-smoke.sh` · `./scripts/smoke/config-schema-smoke.sh` · `./scripts/smoke/install-smoke.sh` |
| Guest scripts | Run on guest; don’t leave keybinds under `/root` when using sudo |
| Docs-only | Keep POSITIONING/CURRENT status legends honest |

## Out (do not invent here)

Meridian hub HTTP API, Mobius referee/queue SoT, Rowena vault/editor, a second
hypervisor distro, seven marketed postures before desktop·console·host are proven,
forking Hyprland/Quickshell, Electron as default app stack.
