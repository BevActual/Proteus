# env/hypr/ — Hyprland seeds

| File | Role |
|------|------|
| `hyprland.conf` | Nested compositor template (`SHELL_DIR_PLACEHOLDER`) |
| `proteus-general.conf` | Default gaps/borders/motion fragment |
| `proteus-keybinds.conf` | Default bind fragment |
| `proteus-monitors.conf` | Default monitors stub |
| `proteus-profile.conf` | Active posture profile pointer (`source` → `profiles/*.conf`) |
| `profiles/desktop.conf` | Desktop tiling posture fragment |
| `profiles/media.conf` | Media lean-back stub |

Copied to `~/.config/hypr/` by `run-nested.sh` / `vm/install` / `vm/guest/install-*.sh`.
Settings owns general / keybinds / monitors. Switch posture profile:

```bash
bash vm/guest/set-hypr-profile.sh desktop   # or media
# hyprctl reload (script attempts this)
```
