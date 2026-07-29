# proteus-pkg

Privileged pacman mutator for Proteus Settings. Settings confirms the action in-app, then runs:

```bash
pkexec /usr/local/libexec/proteus-pkg <sync|upgrade|install|remove|orphans> [package]
```

## Commands

| Action | pacman |
|--------|--------|
| `sync` | `pacman -Sy --noconfirm` |
| `upgrade` | `pacman -Syu --noconfirm` |
| `install <pkg>` | `pacman -S --noconfirm --needed -- <pkg>` |
| `remove <pkg>` | `pacman -Rns --noconfirm -- <pkg>` |
| `orphans` | `pacman -Rns --noconfirm -- $(pacman -Qdtq)` (no-op if empty) |

Package names are validated (`[a-zA-Z0-9@.+_-]+`). Must run as root (via `pkexec`).
Stdout/stderr from pacman are flushed line-by-line so Settings can show live progress.

## Build / install

```bash
cd services/proteus-pkg && cargo build --release
# guest / host install (copies target/release + polkit policy):
sudo ../../vm/guest/install-proteus-pkg.sh
# or via settings install (runs the above when a release binary exists):
sudo ../../vm/guest/install-settings-app.sh
```

Polkit policy: `org.bevington.proteus.pkg.policy` → `/usr/share/polkit-1/actions/`.

Settings resolves `/usr/local/libexec/proteus-pkg` first, then a repo `target/release` build, then falls back to a terminal + `sudo pacman` if nothing is found.

## STACK

Privileged mutators are Rust CLIs (+ polkit), not Python. See `docs/proteus/STACK.md`.
