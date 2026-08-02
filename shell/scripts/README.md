# shell/scripts/ — helpers invoked by chrome / keybinds

| Script | Role | Status |
|--------|------|--------|
| `proteus-terminal` | Ghostty launcher; VM OpenGL 4.3 workaround | **shipped** |
| `proteus-screenshot` | grim + slurp + satty annotate | **interim** |
| `proteus-clipboard` | cliphist + fuzzel picker | **interim** — Beacon Clipboard mode preferred |
| `proteus-colorpick` | hyprpicker → clipboard | **interim** |
| `check-unlock.py` / `proteus-pin.py` / `proteus_auth.py` | Lock unlock (PAM password or hashed PIN) + PIN set/clear | **shipped** |
| `proteus-pick-media` | Console Media seat file picker (zenity / kdialog) | **shipped** |
| `proteus-qs` | Chrome supervisor (flock / backoff / `--restart` waits for prior flock) | **shipped** |
| `proteus-workspace` | Spaces dispatcher (synced / per-display bands; `settings.json` `workspaceMode`) | **shipped** |
| `privacy-indicators.py` | Mic / camera / screen-in-use probe → JSON (+ `apps[]`) for menu-bar + Privacy → In use now | **shipped** |
| `proteus-permissions.py` | `permissions.json` store + Flatpak override list/set + activity wrapper | **shipped** |
| `proteus-defaults.py` | Default apps list/set (`xdg-mime` / gio) for Settings → Desktop → Default apps | **shipped** |
| `beacon-file-index.py` | Beacon Files home index (`~/.cache/proteus/beacon-files.json`) + search; fd preferred | **shipped** |
| `check-password.py` | PAM-only password check (legacy; lock uses `check-unlock.py`) | shipped |
| `fetch-*.py`, `audio-peak.py`, … | Existing runtime helpers | shipped |

First-party Proteus chrome (capture, clipboard, terminal, files) will replace
the interim wrappers; keep package deps light and swap the bind target later.
Overlay install symlinks these into `/usr/local/bin/`.
