#!/usr/bin/env bash
# nvidia — proprietary / open DKMS only on bare metal with an NVIDIA GPU
set -euo pipefail
# shellcheck source=_lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"

if [[ "${PROTEUS_HW_VIRT:-0}" == "1" ]] || proteus_hw_is_virt; then
  echo "hardware/nvidia: virt guest — skip (use host nested for NVIDIA)"
  exit 0
fi

if ! proteus_hw_lspci_vga | grep -qi nvidia; then
  echo "hardware/nvidia: no NVIDIA VGA — skip"
  exit 0
fi

echo "hardware/nvidia: NVIDIA GPU detected"

# Default to open DKMS (Turing+ / GSP). Older Maxwell/Pascal/Volta: see ArchWiki NVIDIA;
# we do not auto-pull 580xx to keep the overlay light and avoid AUR.
HEADERS="$(proteus_hw_kernel_headers)"
PACKAGES=(
  "${HEADERS}"
  nvidia-open-dkms
  nvidia-utils
  libva-nvidia-driver
)

echo "hardware/nvidia: installing ${PACKAGES[*]}"
if ! proteus_root pacman -S --noconfirm --needed "${PACKAGES[@]}"; then
  echo "hardware/nvidia: WARN pacman failed — see https://wiki.archlinux.org/title/NVIDIA" >&2
  exit 0
fi

proteus_root tee /etc/modprobe.d/nvidia.conf >/dev/null <<'EOF'
options nvidia_drm modeset=1
EOF

proteus_root mkdir -p /etc/mkinitcpio.conf.d
proteus_root tee /etc/mkinitcpio.conf.d/nvidia.conf >/dev/null <<'EOF'
MODULES+=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)
EOF

if command -v mkinitcpio >/dev/null 2>&1; then
  proteus_root mkinitcpio -P || true
fi

proteus_hw_hypr_envs "proteus-hw-nvidia" "env = NVD_BACKEND,direct
env = LIBVA_DRIVER_NAME,nvidia
env = __GLX_VENDOR_LIBRARY_NAME,nvidia"

echo "hardware/nvidia: OK (reboot recommended)"
echo "  Older GPUs without GSP: install nvidia-580xx-dkms manually (ArchWiki)."
