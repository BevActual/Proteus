#!/usr/bin/env bash
# Host: bring an empty Proteus VM from ISO/disk → overlay → snapshot hint.
#
# `fresh` drives the whole thing unattended (auto-install.py talks to the live
# ISO over QEMU's serial socket). The default modes orchestrate the dogfood path:
#
#   1. Ensure ISO + qcow exist (download/create if missing)
#   2. Tell you how to finish base Arch if the disk is empty
#   3. Wait for SSH and run ./dev/vm/bootstrap.sh (overlay)
#   4. Print snapshot command
#
# Usage:
#   ./dev/vm/provision.sh              # wait SSH → overlay (fails fast if disk empty)
#   ./dev/vm/provision.sh prepare      # ISO + disk only
#   ./dev/vm/provision.sh fresh        # UNPROVEN: prepare → unattended base Arch → overlay
#   ./dev/vm/provision.sh overlay      # bootstrap only (alias)
#   ./dev/vm/provision.sh status       # read-only checklist (ISO/disk/SSH/last overlay)
#   PROTEUS_INSTALL_DESKTOP=0 ./dev/vm/provision.sh
#   PROTEUS_PROVISION_FORCE=1 ./dev/vm/provision.sh   # overlay even if disk looks empty
#
# Install path SoT: docs/proteus/INSTALL.md
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib.sh
source "${ROOT}/dev/vm/lib.sh"
proteus_vm_migrate_legacy || true
proteus_vm_ensure_dirs

MODE="${1:-overlay}"

prepare() {
  echo "dev/vm/provision: cache=${PROTEUS_VM_CACHE}"
  if [[ ! -e "${PROTEUS_VM_ISO}" ]]; then
    echo "dev/vm/provision: fetching Arch ISO …"
    "${ROOT}/dev/vm/download-iso.sh"
  else
    echo "dev/vm/provision: ISO OK (${PROTEUS_VM_ISO})"
  fi
  if [[ ! -f "${PROTEUS_VM_DISK}" ]]; then
    echo "dev/vm/provision: creating disk …"
    "${ROOT}/dev/vm/create-disk.sh"
  else
    local sz
    sz="$(qemu-img info -U --output=json "${PROTEUS_VM_DISK}" 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin).get("actual-size",0))' 2>/dev/null || echo 0)"
    echo "dev/vm/provision: disk OK (${PROTEUS_VM_DISK}, actual≈${sz} bytes)"
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
    echo "dev/vm/provision: disk looks empty — refusing overlay (would hang on SSH)."
    echo "Finish base Arch first (docs/proteus/INSTALL.md — happy path):"
    echo "  ./dev/vm/run.sh install              # boot live ISO + disk"
    echo "  # in live ISO: bash /mnt/proteus/dev/vm/guest-install.sh"
    echo "  ./dev/vm/run.sh                      # reboot into the installed disk"
    echo "  ssh-copy-id -p 2222 andrew@127.0.0.1   # once — bootstrap is publickey-only"
    echo "  ./dev/vm/provision.sh                # SSH → overlay"
    echo
    echo "Inspect first: ./dev/vm/provision.sh status"
    echo "Override (only if SSH already works): PROTEUS_PROVISION_FORCE=1 ./dev/vm/provision.sh"
    exit 1
  fi
  echo "dev/vm/provision: running overlay via SSH …"
  exec "${ROOT}/dev/vm/bootstrap.sh"
}

# Read-only checklist — never execs bootstrap, never hangs on SSH.
status() {
  local host port user sz verdict
  host="${PROTEUS_GUEST_HOST:-127.0.0.1}"
  port="${PROTEUS_GUEST_PORT:-${PROTEUS_VM_SSH_PORT:-2222}}"
  user="${PROTEUS_GUEST_USER:-andrew}"

  echo "dev/vm/provision: status (read-only)"
  echo "  cache:  ${PROTEUS_VM_CACHE}"

  if [[ -e "${PROTEUS_VM_ISO}" ]]; then
    echo "  ISO:    OK (${PROTEUS_VM_ISO})"
  else
    echo "  ISO:    MISSING — ./dev/vm/provision.sh prepare"
  fi

  if [[ -f "${PROTEUS_VM_DISK}" ]]; then
    sz="$(qemu-img info -U --output=json "${PROTEUS_VM_DISK}" 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin).get("actual-size",0))' 2>/dev/null || echo 0)"
    if disk_looks_empty; then
      verdict="EMPTY (base Arch never installed — ./dev/vm/run.sh install + guest-install.sh)"
    else
      verdict="installed"
    fi
    echo "  disk:   ${PROTEUS_VM_DISK} (actual≈${sz} bytes, ${verdict})"
  else
    echo "  disk:   MISSING — ./dev/vm/provision.sh prepare"
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
    echo "  SSH:    port ${host}:${port} closed (guest down? ./dev/vm/run.sh)"
  fi

  echo "  next:   docs/proteus/INSTALL.md (happy path + failure table)"
}

# Fully unattended: prepare, boot the live ISO with a serial socket, drive
# guest-install.sh over it, then run the overlay.
#
# UNPROVEN — auto-install.py was written, never wired, and has not been run
# end-to-end since. The pieces line up (run.sh exposes PROTEUS_VM_SERIAL at the
# path auto-install.py reads; passwords match guest-install.sh) but nobody has
# watched it complete. Treat the first run as a test of this function, not of
# your tree, and expect to read dev/vm/auto-install.py when it stalls.
fresh() {
  local disk_state
  echo "==> fresh: prepare"
  prepare

  echo "==> fresh: booting live ISO with serial socket (background)"
  PROTEUS_VM_SERIAL=1 "${ROOT}/dev/vm/run.sh" install &
  local vm_pid=$!

  echo "==> fresh: driving guest-install.sh over serial (several minutes)"
  if ! python3 "${ROOT}/dev/vm/auto-install.py"; then
    echo "vm/provision: unattended base install FAILED" >&2
    echo "  serial log: ${PROTEUS_VM_RUNTIME_DIR}/auto-install.log" >&2
    echo "  fall back to the manual path in docs/proteus/INSTALL.md" >&2
    kill "${vm_pid}" 2>/dev/null || true
    return 1
  fi
  wait "${vm_pid}" 2>/dev/null || true

  echo "==> fresh: base Arch installed — boot the guest, then run the overlay:"
  echo "     ./dev/vm/run.sh &"
  echo "     ssh-copy-id -p 2222 ${PROTEUS_GUEST_USER:-andrew}@127.0.0.1"
  echo "     ./dev/vm/provision.sh overlay"
}

case "${MODE}" in
  prepare) prepare ;;
  fresh) fresh ;;
  overlay|bootstrap|"") overlay ;;
  status) status ;;
  -h|--help|help)
    sed -n '2,22p' "$0"
    ;;
  *)
    echo "Unknown mode: ${MODE} (prepare|fresh|overlay|status)" >&2
    exit 1
    ;;
esac
