#!/usr/bin/env bash
# intel — Vulkan + media driver for Intel GPUs (bare metal)
set -euo pipefail
# shellcheck source=_lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"

if [[ "${PROTEUS_HW_VIRT:-0}" == "1" ]] || proteus_hw_is_virt; then
  echo "hardware/intel: virt guest — skip"
  exit 0
fi

if ! proteus_hw_lspci_vga | grep -qi intel; then
  echo "hardware/intel: no Intel VGA — skip"
  exit 0
fi

echo "hardware/intel: Intel GPU detected"
proteus_root pacman -S --noconfirm --needed mesa vulkan-intel intel-media-driver libva-utils || {
  echo "hardware/intel: WARN pacman failed" >&2
  exit 0
}

proteus_hw_hypr_envs "proteus-hw-intel" "# Intel — ANV / media
env = LIBVA_DRIVER_NAME,iHD"

echo "hardware/intel: OK"
