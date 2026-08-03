#!/usr/bin/env bash
# Shared GPU helpers (sourced by hardware/*.sh).
# shellcheck source=../helpers.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/helpers.sh"

proteus_hw_is_virt() {
  if command -v systemd-detect-virt >/dev/null 2>&1; then
    local v
    v="$(systemd-detect-virt 2>/dev/null || echo none)"
    [[ "${v}" != "none" && -n "${v}" ]] && return 0
  fi
  if lspci 2>/dev/null | grep -qiE 'Virtio.*(VGA|GPU|Display)|QEMU|Bochs|VMware SVGA'; then
    return 0
  fi
  return 1
}

proteus_hw_lspci_vga() {
  lspci 2>/dev/null | grep -iE 'VGA|3D|Display' || true
}

# Append Hyprland env block once (idempotent marker).
proteus_hw_hypr_envs() {
  local marker="$1"
  local block="$2"
  local user home conf
  user="$(proteus_session_user)"
  home="$(getent passwd "${user}" | cut -d: -f6)"
  [[ -n "${home}" ]] || return 0
  conf="${home}/.config/hypr/proteus-hw.conf"
  proteus_as_user mkdir -p "${home}/.config/hypr"
  if [[ -f "${conf}" ]] && grep -qF "${marker}" "${conf}" 2>/dev/null; then
    return 0
  fi
  {
    echo ""
    echo "# ${marker}"
    printf '%s\n' "${block}"
  } | proteus_as_user tee -a "${conf}" >/dev/null

  # Ensure hyprland.conf sources it
  local hypr="${home}/.config/hypr/hyprland.conf"
  if [[ -f "${hypr}" ]] && ! grep -q 'proteus-hw.conf' "${hypr}" 2>/dev/null; then
    {
      echo ""
      echo "# GPU / hardware envs (install/hardware)"
      echo "source = ~/.config/hypr/proteus-hw.conf"
    } | proteus_as_user tee -a "${hypr}" >/dev/null
  fi
}

proteus_hw_kernel_headers() {
  # Match installed kernel meta-package → headers
  local k
  k="$(pacman -Qqs '^linux(-zen|-lts|-hardened)?$' 2>/dev/null | head -1 || true)"
  if [[ -z "${k}" ]]; then
    k=linux
  fi
  printf '%s-headers' "${k}"
}
