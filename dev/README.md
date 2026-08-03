# scripts/ — runners, tools, smoke gates

| Path | Role |
|------|------|
| `smoke-all.sh` | Entry point — runs every gate in `smoke/` (guest gates skip unless SSH `:2222` / `PROTEUS_GUEST=1`) |
| `smoke/*-smoke.sh` | Fail-closed gates: layout · config schema · app manifest · chrome tokens · software · power/logind · accounts · audio-mix · hw-probe · install · session · qs-version · guest QS · guest software |
| `run-nested.sh` | Nested Hyprland shell test on host |
| `run-desktop.sh` | Bare desktop surface via `qs -p shell` |
| `generate-wallpapers.py` | Regenerate `shell/assets/wallpaper-*.jpg` |

New gate → add under `smoke/` (repo root is `../..`) and register it in
`smoke-all.sh`. Gate table with one-line purposes:
[CURRENT.md §6](../docs/proteus/CURRENT.md).
