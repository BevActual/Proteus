#!/usr/bin/env bash
# amd — Vulkan/Mesa extras for AMD GPUs (bare metal)
set -euo pipefail
# shellcheck source=_lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"

if [[ "${PROTEUS_HW_VIRT:-0}" == "1" ]] || proteus_hw_is_virt; then
  echo "hardware/amd: virt guest — skip"
  exit 0
fi

if ! proteus_hw_lspci_vga | grep -qiE 'AMD|ATI|Advanced Micro Devices'; then
  echo "hardware/amd: no AMD VGA — skip"
  exit 0
fi

echo "hardware/amd: AMD GPU detected"
proteus_root pacman -S --noconfirm --needed mesa vulkan-radeon libva-mesa-driver mesa-vdpau || {
  echo "hardware/amd: WARN pacman failed" >&2
  exit 0
}

proteus_hw_hypr_envs "proteus-hw-amd" "# AMD — Mesa / RADV
env = AMD_VULKAN_ICD,RADV"

echo "hardware/amd: OK"
