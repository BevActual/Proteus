#!/usr/bin/env bash
# Create the Proteus guest qcow2 disk (default 40G).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DISK_DIR="${ROOT}/vm/disks"
DISK="${DISK_DIR}/proteus.qcow2"
SIZE="${1:-40G}"

if ! command -v qemu-img >/dev/null 2>&1; then
  echo "qemu-img not found." >&2
  echo "Install on Arch:  sudo pacman -S qemu-img" >&2
  echo "Or the fuller set: sudo pacman -S qemu-desktop" >&2
  exit 1
fi

mkdir -p "${DISK_DIR}"

if [[ -f "${DISK}" ]]; then
  echo "Disk already exists: ${DISK}"
  qemu-img info "${DISK}"
  echo
  echo "Remove it first if you want to recreate, e.g.:"
  echo "  rm ${DISK}"
  exit 0
fi

echo "Creating ${DISK} (${SIZE}) …"
qemu-img create -f qcow2 "${DISK}" "${SIZE}"
qemu-img info "${DISK}"
echo "Done."
