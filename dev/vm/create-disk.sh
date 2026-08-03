#!/usr/bin/env bash
# Create the Proteus guest qcow2 disk (default 40G) under PROTEUS_VM_CACHE/disks/
set -euo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
proteus_vm_migrate_legacy
proteus_vm_ensure_dirs

DISK_DIR="${PROTEUS_VM_DISK_DIR}"
DISK="${PROTEUS_VM_DISK}"
SIZE="${1:-40G}"

if ! command -v qemu-img >/dev/null 2>&1; then
  echo "qemu-img not found." >&2
  echo "Install on Arch:  sudo pacman -S qemu-img" >&2
  echo "Or the fuller set: sudo pacman -S qemu-desktop" >&2
  exit 1
fi

if [[ -f "${DISK}" ]]; then
  echo "Disk already exists: ${DISK}"
  qemu-img info "${DISK}"
  echo
  echo "Remove it first if you want to recreate, e.g.:"
  echo "  rm ${DISK}"
  exit 0
fi

echo "Cache: ${PROTEUS_VM_CACHE}"
echo "Creating ${DISK} (${SIZE}) …"
qemu-img create -f qcow2 "${DISK}" "${SIZE}"
qemu-img info "${DISK}"
echo "Done."
