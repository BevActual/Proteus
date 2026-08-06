# env/settings — Settings hub catalog

`catalog.json` is the Settings hub gating data…

Also: `keybinds.defaults.json` — seed for `~/.config/proteus/keybinds.json`
(owned compositor binds; see compositor-next `binds.rs`). Install via
`install/machine/install-keybinds.sh`.


| Consumer | How |
|----------|-----|
| `services/proteus-shell-core` | FileView load (shell **and** Settings app processes); `paneAvailable` / `paneBlockReason` |
| `services/proteus-shell-core` | `gate pane <id>` — cargo-tested twin of the QML gating |
| `shell/scripts/proteus-cli-surface` | Derives the per-posture command surface from `backsCli` |

Shape: `hubs[]` with `id` / `label` / `status` (mirrors
[CURRENT.md](../../docs/proteus/CURRENT.md) §3) / `requires` / `requiresAny`
(hard capability gates) / optional `postures` (hard; omit or `[]` = all) /
`backsFacts` + `backsCli` (ARCHITECTURE HARD RULE 2 audit trail), plus
`minimalPaneAllow` — panes kept when Focus `paneDensity=minimal`
(`privacy-*` leaves always stay).

Gates: `dev/smoke/shell-core-smoke.sh` (extraction + gating parity via
`dev/fixtures/gate-matrix.json`) · `dev/smoke/settings-backing-smoke.sh`
(HARD RULE 2 resolution) · `dev/smoke/posture-hard-smoke.sh` (posture data).
