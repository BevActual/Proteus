#!/usr/bin/env bash
# Host: bring an empty Proteus VM from ISO/disk → overlay → snapshot hint.
#
# This does NOT fully unattended-install Arch in one click (that still needs
# live ISO + guest-install / auto-install). It orchestrates the dogfood path:
#
#   1. Ensure ISO + qcow exist (download/create if missing)
#   2. Tell you how to finish base Arch if the disk is empty
#   3. Wait for SSH and run ./vm/bootstrap.sh (overlay)
#   4. Print snapshot command
#
# Usage:
#   ./vm/provision.sh              # wait SSH → overlay (fails fast if disk empty)
#   ./vm/provision.sh prepare      # ISO + disk only
#   ./vm/provision.sh overlay      # bootstrap only (alias)
#   PROTEUS_INSTALL_DESKTOP=0 ./vm/provision.sh
#   PROTEUS_PROVISION_FORCE=1 ./vm/provision.sh   # overlay even if disk looks empty
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "${ROOT}/vm/lib.sh"
proteus_vm_migrate_legacy || true
proteus_vm_ensure_dirs

MODE="${1:-overlay}"

prepare() {
  echo "vm/provision: cache=${PROTEUS_VM_CACHE}"
  if [[ ! -e "${PROTEUS_VM_ISO}" ]]; then
    echo "vm/provision: fetching Arch ISO …"
    "${ROOT}/vm/download-iso.sh"
  else
    echo "vm/provision: ISO OK (${PROTEUS_VM_ISO})"
  fi
  if [[ ! -f "${PROTEUS_VM_DISK}" ]]; then
    echo "vm/provision: creating disk …"
    "${ROOT}/vm/create-disk.sh"
  else
    local sz
    sz="$(qemu-img info --output=json "${PROTEUS_VM_DISK}" 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin).get("actual-size",0))' 2>/dev/null || echo 0)"
    echo "vm/provision: disk OK (${PROTEUS_VM_DISK}, actual≈${sz} bytes)"
  fi
}

# True when qcow looks freshly created / never installed (~200KiB).
disk_looks_empty() {
  [[ -f "${PROTEUS_VM_DISK}" ]] || return 0
  local sz
  sz="$(qemu-img info --output=json "${PROTEUS_VM_DISK}" 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin).get("actual-size",0))' 2>/dev/null || echo 0)"
  [[ "${sz}" =~ ^[0-9]+$ ]] && [[ "${sz}" -lt 1048576 ]]
}

overlay() {
  prepare
  if disk_looks_empty && [[ "${PROTEUS_PROVISION_FORCE:-0}" != "1" ]]; then
    echo
    echo "vm/provision: disk looks empty — refusing overlay (would hang on SSH)."
    echo "Finish base Arch first:"
    echo "  ./vm/run.sh install"
    echo "  # in live ISO: mount 9p, then:"
    echo "  #   bash /mnt/proteus/vm/guest-install.sh"
    echo "  # reboot into disk: ./vm/run.sh"
    echo "  # then: ./vm/provision.sh"
    echo
    echo "Override (only if SSH already works): PROTEUS_PROVISION_FORCE=1 ./vm/provision.sh"
    exit 1
  fi
  echo "vm/provision: running overlay via SSH …"
  exec "${ROOT}/vm/bootstrap.sh"
}

case "${MODE}" in
  prepare) prepare ;;
  overlay|bootstrap|"") overlay ;;
  -h|--help|help)
    sed -n '2,20p' "$0"
    ;;
  *)
    echo "Unknown mode: ${MODE} (prepare|overlay)" >&2
    exit 1
    ;;
esac
