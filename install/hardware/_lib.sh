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

# Normalize one hardware env block line → stdout (KEY=VALUE or comment/blank).
# Accepts native KEY=VALUE and legacy Hypr `env = KEY,VALUE`.
proteus_hw_env_normalize_line() {
  local line="${1:-}"
  if [[ "${line}" =~ ^[[:space:]]*env[[:space:]]*=[[:space:]]*([^,[:space:]]+)[[:space:]]*,[[:space:]]*(.*)$ ]]; then
    printf '%s=%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    return 0
  fi
  printf '%s\n' "${line}"
}

# Offline gate for normalize (no user home / root).
proteus_hw_env_selftest() {
  local fail=0 got
  check() {
    local want="$1" input="$2" label="$3"
    got="$(proteus_hw_env_normalize_line "${input}")"
    if [[ "${got}" != "${want}" ]]; then
      echo "proteus_hw_env_selftest FAIL ${label}: got=${got} want=${want}" >&2
      fail=1
    fi
  }
  check "NVD_BACKEND=direct" "env = NVD_BACKEND,direct" "nvidia nvd"
  check "LIBVA_DRIVER_NAME=nvidia" "env = LIBVA_DRIVER_NAME,nvidia" "nvidia libva"
  check "__GLX_VENDOR_LIBRARY_NAME=nvidia" "env = __GLX_VENDOR_LIBRARY_NAME,nvidia" "nvidia glx"
  check "AMD_VULKAN_ICD=RADV" "env = AMD_VULKAN_ICD,RADV" "amd"
  check "LIBVA_DRIVER_NAME=iHD" "env = LIBVA_DRIVER_NAME,iHD" "intel"
  check "FOO=bar" "FOO=bar" "native"
  check "# comment" "# comment" "comment"
  [[ "${fail}" -eq 0 ]] || return 1
  echo "proteus_hw_env_selftest: OK"
}

# Append GPU/session env once (idempotent marker).
# Writes ~/.config/proteus/hw.env — sourced by proteus-session before compositor.
# Also mirrors KEY=VALUE into ~/.config/environment.d/90-proteus-hw.conf when
# systemd user environment.d is available (harmless if unused).
proteus_hw_session_envs() {
  local marker="$1"
  local block="$2"
  local user home conf envd line
  user="$(proteus_session_user)"
  home="$(getent passwd "${user}" | cut -d: -f6)"
  [[ -n "${home}" ]] || return 0
  conf="${home}/.config/proteus/hw.env"
  proteus_as_user mkdir -p "${home}/.config/proteus"
  if [[ -f "${conf}" ]] && grep -qF "${marker}" "${conf}" 2>/dev/null; then
    return 0
  fi
  {
    echo ""
    echo "# ${marker}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
      proteus_hw_env_normalize_line "${line}"
    done <<<"${block}"
  } | proteus_as_user tee -a "${conf}" >/dev/null

  # Best-effort systemd user env drop-in (KEY=VALUE only; skip comments).
  envd="${home}/.config/environment.d/90-proteus-hw.conf"
  proteus_as_user mkdir -p "${home}/.config/environment.d"
  if [[ ! -f "${envd}" ]] || ! grep -qF "${marker}" "${envd}" 2>/dev/null; then
    {
      echo "# ${marker} (from install/hardware → also in ~/.config/proteus/hw.env)"
      while IFS= read -r line || [[ -n "${line}" ]]; do
        line="$(proteus_hw_env_normalize_line "${line}")"
        [[ "${line}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] || continue
        printf '%s\n' "${line}"
      done <<<"${block}"
    } | proteus_as_user tee -a "${envd}" >/dev/null
  fi
}

# Back-compat name — callers should prefer proteus_hw_session_envs.
proteus_hw_hypr_envs() {
  proteus_hw_session_envs "$@"
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
