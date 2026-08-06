# env/ — the default environment Proteus ships

Config templates, app manifests and design tokens that define what Proteus looks
like out of the box. **Not install-only.** Three different consumers read this
tree, which is why it is not folded into `install/`:

| Consumer | Reads | When |
|----------|-------|------|
| **Runtime** | `apps/catalog.json` via `proteus-shell-core` gating; `hypr/profiles/*` via `shell/scripts/set-hypr-profile.sh` | while Proteus is running — including during a posture flip |
| **Installer** | `hypr/` · `ghostty/` · `fastfetch/` · `bash/` · `systemd/` | `install/config.sh` seeds them into `$HOME` on first install |
| **Dev harness** | `hypr/` · `ghostty/` · `fastfetch/` · `bash/` | `dev/run-nested.sh` seeds a nested session; smoke gates assert template content |

| Path | Role |
|------|------|
| `hypr/` | Hyprland template + `proteus-*.conf` fragments + posture `profiles/` |
| `apps/` | App capability manifests (`catalog.json` · `schema.json`) for shell-core gate |
| `chrome/` | Sibling chrome token export (JSON + CSS vars) |
| `ghostty/` | Minimal Ghostty seed (no opacity/blur) |
| `fastfetch/` | P monogram + modules on shell start |
| `bash/proteus-bashrc.sh` | Run fastfetch when Ghostty opens. Named `bash/`, not `shell/`, because `shell/` at the repo root means the owned iced chrome crate |
| `systemd/user/` | (empty) — Quickshell user unit retired |

## No tooling here

`env/` is data the product ships. Anything that *generates* that data is
maintainer tooling and lives in `dev/` — `dev/gen-helix-logo.py` rewrites
`fastfetch/proteus-helix.txt`, and nothing at install or runtime invokes it; the
committed `.txt` is the shipped artefact.

## Two things that must not move

- **`apps/` is resolved at runtime** as `PROTEUS_ROOT + "/env/apps/…"`
  ([proteus-shell-core](../services/proteus-shell-core)). `env/` has to stay adjacent to
  `shell/`; relocating it breaks the shell, not just the installer.
- **`chrome/` is a published cross-repo contract** — sibling products consume the
  token export ([CHROME.md](../docs/proteus/CHROME.md)). Its path is an external
  interface, not an internal detail.

## vs `install/`

`install/` is the overlay installer (VM + bare metal). `env/` is the *content*
that installer seeds and that the running product keeps reading.
