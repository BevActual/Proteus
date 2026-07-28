# env/ — host / nested session seeds

Templates and default Hyprland fragments for **nested** Proteus
(`scripts/run-nested.sh`) and as copy-sources for a host session.

| File | Role |
|------|------|
| `hyprland.conf` | Nested compositor template (`SHELL_DIR_PLACEHOLDER`) |
| `proteus-general.conf` | Default gaps/borders/motion fragment |
| `proteus-keybinds.conf` | Default bind fragment |
| `proteus-monitors.conf` | Default monitors stub |

**vs `vm/guest/`:** guest scripts *install* session pieces onto the dogfood VM
(greetd, keybinds, Settings launcher, PAM lock, `proteus-bg`, …). `env/` does
not replace guest installers — it seeds the same *kinds* of facts for a quick
host nested run.

Settings still writes live truth under `~/.config/hypr/` and
`~/.config/proteus/` ([FACTS.md](../docs/proteus/FACTS.md)).
