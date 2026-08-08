# scripts/ — runners, tools, smoke gates

| Path | Role |
|------|------|
| `smoke-all.sh` | **Desktop spine** entry — shellcheck · doc-links · layout · ipc · config-schema · chrome-tokens · shell-core · shell · compositor · owned-dogfood · settings-next · settings-backing · install · session · guest `owned-guest` (SSH / `PROTEUS_GUEST=1`) |
| `smoke/*-smoke.sh` | Individual gates. Console/host/software-guest + retired QML leaf stubs are **not** in `smoke-all` until desktop is rock solid — run them directly when needed |
| `smoke/_guest_ssh.sh` | Shared guest SSH helpers (`proteus_guest_ssh_*`) for owned-guest / dogfood |
| `run-nested.sh` | Nested compositor (winit) + iced chrome on host — primary shell quick-test |
| `run-desktop.sh` | Thin alias → `run-nested.sh` (Quickshell path retired) |
| `generate-wallpapers.py` | Regenerate `shell/assets/wallpaper-*.jpg` |

New **desktop** gate → add under `smoke/` and register it in `smoke-all.sh`.
Posture/console/host gates stay as scripts until re-enabled. Gate table:
[CURRENT.md §6](../docs/proteus/CURRENT.md).
