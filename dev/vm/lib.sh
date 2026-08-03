#!/usr/bin/env bash
# dev/vm/lib.sh — shared paths for Proteus QEMU harness
# Artifacts live outside the repo (modular cache). Source from other dev/vm/*.sh:
#   # shellcheck source=lib.sh
#   source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
#
# Override: PROTEUS_VM_CACHE=/path/to/cache
# (Do not set -e here — this file is sourced.)

# When sourced, BASH_SOURCE[0] is lib.sh
_PROTEUS_VM_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROTEUS_ROOT="$(cd "${_PROTEUS_VM_LIB_DIR}/../.." && pwd)"
PROTEUS_VM_DIR="${PROTEUS_ROOT}/vm"

# Default: XDG cache; fall back to ~/.cache
_xdg_cache="${XDG_CACHE_HOME:-${HOME}/.cache}"
PROTEUS_VM_CACHE="${PROTEUS_VM_CACHE:-${_xdg_cache}/proteus-vm}"

PROTEUS_VM_ISO_DIR="${PROTEUS_VM_CACHE}/iso"
PROTEUS_VM_DISK_DIR="${PROTEUS_VM_CACHE}/disks"
PROTEUS_VM_BOOT_DIR="${PROTEUS_VM_CACHE}/boot"
PROTEUS_VM_VARS_DIR="${PROTEUS_VM_CACHE}/vars"
PROTEUS_VM_RUNTIME_DIR="${PROTEUS_VM_CACHE}/runtime"

PROTEUS_VM_ISO="${PROTEUS_VM_ISO_DIR}/archlinux-x86_64.iso"
PROTEUS_VM_DISK="${PROTEUS_VM_DISK_DIR}/proteus.qcow2"
PROTEUS_VM_VARS="${PROTEUS_VM_VARS_DIR}/proteus_VARS.fd"
PROTEUS_VM_KERNEL="${PROTEUS_VM_BOOT_DIR}/vmlinuz-linux"
PROTEUS_VM_INITRD="${PROTEUS_VM_BOOT_DIR}/initramfs-linux.img"
PROTEUS_VM_QMP_SOCK="${PROTEUS_VM_RUNTIME_DIR}/qmp.sock"
PROTEUS_VM_SERIAL_SOCK="${PROTEUS_VM_RUNTIME_DIR}/serial.sock"

proteus_vm_ensure_dirs() {
  mkdir -p \
    "${PROTEUS_VM_ISO_DIR}" \
    "${PROTEUS_VM_DISK_DIR}" \
    "${PROTEUS_VM_BOOT_DIR}" \
    "${PROTEUS_VM_VARS_DIR}" \
    "${PROTEUS_VM_RUNTIME_DIR}"
}

# One-shot: move legacy in-repo artifacts into the cache (no overwrite).
proteus_vm_migrate_legacy() {
  local legacy name
  proteus_vm_ensure_dirs

  _migrate_dir() {
    local src="$1" dest="$2"
    [[ -d "${src}" ]] || return 0
    # Skip empty / placeholder-only dirs
    local found=0
    shopt -s nullglob dotglob
    for f in "${src}"/*; do
      [[ "$(basename "${f}")" == ".gitkeep" ]] && continue
      found=1
      break
    done
    shopt -u nullglob dotglob
    [[ "${found}" -eq 1 ]] || return 0

    echo "proteus-vm: migrating ${src} → ${dest}"
    mkdir -p "${dest}"
    shopt -s nullglob
    for f in "${src}"/*; do
      name="$(basename "${f}")"
      [[ "${name}" == ".gitkeep" ]] && continue
      if [[ -e "${dest}/${name}" ]]; then
        echo "  skip (exists in cache): ${name}"
      else
        if mv "${f}" "${dest}/${name}"; then
          echo "  moved: ${name}"
        else
          echo "proteus-vm: FAIL moving ${f} → ${dest}/${name}" >&2
          return 1
        fi
      fi
    done
    shopt -u nullglob
  }

  _migrate_dir "${PROTEUS_VM_DIR}/iso" "${PROTEUS_VM_ISO_DIR}" || return 1
  _migrate_dir "${PROTEUS_VM_DIR}/disks" "${PROTEUS_VM_DISK_DIR}" || return 1
  _migrate_dir "${PROTEUS_VM_DIR}/boot" "${PROTEUS_VM_BOOT_DIR}" || return 1
  _migrate_dir "${PROTEUS_VM_DIR}/vars" "${PROTEUS_VM_VARS_DIR}" || return 1

  # Legacy socks/logs under dev/vm/
  mkdir -p "${PROTEUS_VM_RUNTIME_DIR}"
  for name in qmp.sock serial.sock; do
    if [[ -e "${PROTEUS_VM_DIR}/${name}" && ! -e "${PROTEUS_VM_RUNTIME_DIR}/${name}" ]]; then
      if mv "${PROTEUS_VM_DIR}/${name}" "${PROTEUS_VM_RUNTIME_DIR}/${name}"; then
        echo "proteus-vm: migrated ${name} → runtime/"
      else
        echo "proteus-vm: FAIL migrating ${name}" >&2
        return 1
      fi
    fi
  done
  for name in qemu-run.log qemu-install.log auto-install.log; do
    if [[ -e "${PROTEUS_VM_DIR}/${name}" && ! -e "${PROTEUS_VM_RUNTIME_DIR}/${name}" ]]; then
      if mv "${PROTEUS_VM_DIR}/${name}" "${PROTEUS_VM_RUNTIME_DIR}/${name}"; then
        echo "proteus-vm: migrated ${name} → runtime/"
      else
        echo "proteus-vm: FAIL migrating ${name}" >&2
        return 1
      fi
    fi
  done

  # Drop empty legacy dirs (never delete non-empty)
  for d in iso disks boot vars; do
    local legacy="${PROTEUS_VM_DIR}/${d}"
    [[ -d "${legacy}" ]] || continue
    if [[ -z "$(find "${legacy}" -mindepth 1 ! -name '.gitkeep' -print -quit)" ]]; then
      rm -rf "${legacy}"
      echo "proteus-vm: removed empty legacy dev/vm/${d}/"
    fi
  done
}
