# shell/scripts/ — helpers invoked by chrome / keybinds

| Script | Role | Status |
|--------|------|--------|
| `proteus-screenshot` | grim + slurp + satty annotate | **interim** |
| `proteus-clipboard` | cliphist + fuzzel picker | **interim** |
| `proteus-colorpick` | hyprpicker → clipboard | **interim** |
| `fetch-*.py`, `audio-peak.py`, … | Existing runtime helpers | shipped |

First-party Proteus chrome (capture, clipboard, terminal, files) will replace
the interim wrappers; keep package deps light and swap the bind target later.
Overlay install symlinks these into `/usr/local/bin/`.
