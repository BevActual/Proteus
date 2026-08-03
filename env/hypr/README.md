# env/hypr/ — Hyprland seeds

| File | Role |
|------|------|
| `hyprland.conf` | Nested compositor template (`SHELL_DIR_PLACEHOLDER`) |
| `proteus-general.conf` | Default gaps/borders/motion fragment |
| `proteus-keybinds.conf` | Default bind fragment |
| `proteus-monitors.conf` | Default monitors stub |
| `proteus-profile.conf` | Active posture profile pointer (`source` → `profiles/*.conf`) |
| `profiles/desktop.conf` | Desktop tiling posture fragment |
| `profiles/console.conf` | Console kiosk rules (fullscreen apps) |
| `profiles/host.conf` | Host ops stub |
| `profiles/home.conf` | Home hub stub |

Copied to `~/.config/hypr/` by `run-nested.sh` / `install` / `install/machine/install-*.sh`.
Settings owns general / keybinds / monitors.

Soft profile pointer:

```bash
bash shell/scripts/set-hypr-profile.sh desktop   # or console|host|home
# hyprctl reload (script attempts this)
```

Hard console posture flip (chrome + Fact + profile):

```bash
bash shell/scripts/proteus-posture console
bash shell/scripts/proteus-posture desktop
```
