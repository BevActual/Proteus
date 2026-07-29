# Terminal appearance seeds (Ghostty + fastfetch DNA helix)
# Copied to ~/.config by vm/install/config.sh

| Path | Role |
|------|------|
| `ghostty/config` | Minimal Ghostty seed (no opacity/blur) |
| `fastfetch/` | **P** monogram + modules on shell start |
| `shell/proteus-bashrc.sh` | Run fastfetch when an interactive shell starts |

Launch via **`proteus-terminal`** (not bare `ghostty`): on QEMU/virtio the guest
often only exposes OpenGL 4.2 while Ghostty needs 4.3 — the wrapper sets a Mesa
version override (or `PROTEUS_TERMINAL_SOFTGL=1` for llvmpipe).
