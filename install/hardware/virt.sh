#!/usr/bin/env bash
# virt — QEMU/KVM / virtio dogfood GPU (no proprietary drivers)
set -euo pipefail
# shellcheck source=_lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"

if ! proteus_hw_is_virt; then
  echo "hardware/virt: not a VM — skip"
  exit 0
fi

echo "hardware/virt: virtualized GPU — ensuring virtio/mesa stack"
proteus_root pacman -S --noconfirm --needed mesa vulkan-virtio 2>/dev/null || \
  proteus_root pacman -S --noconfirm --needed mesa || true

proteus_hw_hypr_envs "proteus-hw-virt" "# Virtio / QEMU — no NVIDIA proprietary stack
# Prefer nested host dogfood if VirGL is painful: PROTEUS_VM_GL=0 or ./dev/run-nested.sh"

echo "hardware/virt: OK (skip nvidia/amd discrete installs on this machine)"
# Signal siblings via env for this bootstrap process tree
export PROTEUS_HW_VIRT=1
