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
#   ./vm/provision.sh status       # read-only checklist (ISO/disk/SSH/last overlay)
#   PROTEUS_INSTALL_DESKTOP=0 ./vm/provision.sh
#   PROTEUS_PROVISION_FORCE=1 ./vm/provision.sh   # overlay even if disk looks empty
#
# Install path SoT: docs/proteus/INSTALL.md
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
    sz="$(qemu-img info -U --output=json "${PROTEUS_VM_DISK}" 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin).get("actual-size",0))' 2>/dev/null || echo 0)"
    echo "vm/provision: disk OK (${PROTEUS_VM_DISK}, actual≈${sz} bytes)"
  fi
}

# True when qcow looks freshly created / never installed (~200KiB).
disk_looks_empty() {
  [[ -f "${PROTEUS_VM_DISK}" ]] || return 0
  local sz
  sz="$(qemu-img info -U --output=json "${PROTEUS_VM_DISK}" 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin).get("actual-size",0))' 2>/dev/null || echo 0)"
  [[ "${sz}" =~ ^[0-9]+$ ]] && [[ "${sz}" -lt 1048576 ]]
}

overlay() {
  prepare
  if disk_looks_empty && [[ "${PROTEUS_PROVISION_FORCE:-0}" != "1" ]]; then
    echo
    echo "vm/provision: disk looks empty — refusing overlay (would hang on SSH)."
    echo "Finish base Arch first (docs/proteus/INSTALL.md — happy path):"
    echo "  ./vm/run.sh install              # boot live ISO + disk"
    echo "  # in live ISO: bash /mnt/proteus/vm/guest-install.sh"
    echo "  ./vm/run.sh                      # reboot into the installed disk"
    echo "  ssh-copy-id -p 2222 andrew@127.0.0.1   # once — bootstrap is publickey-only"
    echo "  ./vm/provision.sh                # SSH → overlay"
    echo
    echo "Inspect first: ./vm/provision.sh status"
    echo "Override (only if SSH already works): PROTEUS_PROVISION_FORCE=1 ./vm/provision.sh"
    exit 1
  fi
  echo "vm/provision: running overlay via SSH …"
  exec "${ROOT}/vm/bootstrap.sh"
}

# Read-only checklist — never execs bootstrap, never hangs on SSH.
status() {
  local host port user sz verdict
  host="${PROTEUS_GUEST_HOST:-127.0.0.1}"
  port="${PROTEUS_GUEST_PORT:-${PROTEUS_VM_SSH_PORT:-2222}}"
  user="${PROTEUS_GUEST_USER:-andrew}"

  echo "vm/provision: status (read-only)"
  echo "  cache:  ${PROTEUS_VM_CACHE}"

  if [[ -e "${PROTEUS_VM_ISO}" ]]; then
    echo "  ISO:    OK (${PROTEUS_VM_ISO})"
  else
    echo "  ISO:    MISSING — ./vm/provision.sh prepare"
  fi

  if [[ -f "${PROTEUS_VM_DISK}" ]]; then
    sz="$(qemu-img info -U --output=json "${PROTEUS_VM_DISK}" 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin).get("actual-size",0))' 2>/dev/null || echo 0)"
    if disk_looks_empty; then
      verdict="EMPTY (base Arch never installed — ./vm/run.sh install + guest-install.sh)"
    else
      verdict="installed"
    fi
    echo "  disk:   ${PROTEUS_VM_DISK} (actual≈${sz} bytes, ${verdict})"
  else
    echo "  disk:   MISSING — ./vm/provision.sh prepare"
  fi

  if timeout 3 bash -c "exec 3<>/dev/tcp/${host}/${port}" 2>/dev/null; then
    echo "  SSH:    port ${host}:${port} open"
    if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
        -o ConnectTimeout=3 -o BatchMode=yes -o PreferredAuthentications=publickey \
        -p "${port}" "${user}@${host}" 'echo OK' >/dev/null 2>&1; then
      echo "  auth:   publickey OK (${user}@${host})"
      echo "  last overlay log (guest tail):"
      ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
          -o ConnectTimeout=3 -o BatchMode=yes -o PreferredAuthentications=publickey \
          -p "${port}" "${user}@${host}" \
          'tail -n 5 /var/log/proteus-install.log 2>/dev/null || echo "(no /var/log/proteus-install.log yet)"' \
        2>/dev/null | sed 's/^/    /'
    else
      echo "  auth:   FAIL publickey — ssh-copy-id -p ${port} ${user}@${host}"
    fi
  else
    echo "  SSH:    port ${host}:${port} closed (guest down? ./vm/run.sh)"
  fi

  echo "  next:   docs/proteus/INSTALL.md (happy path + failure table)"
}

case "${MODE}" in
  prepare) prepare ;;
  overlay|bootstrap|"") overlay ;;
  status) status ;;
  -h|--help|help)
    sed -n '2,22p' "$0"
    ;;
  *)
    echo "Unknown mode: ${MODE} (prepare|overlay|status)" >&2
    exit 1
    ;;
esac
