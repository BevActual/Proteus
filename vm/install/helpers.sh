#!/usr/bin/env bash
# Shared helpers for vm/install/* (sourced; do not set -e here).

proteus_install_root() {
  if [[ -n "${PROTEUS_ROOT:-}" && -d "${PROTEUS_ROOT}/vm/install" ]]; then
    printf '%s' "${PROTEUS_ROOT}"
    return 0
  fi
  if [[ -d /mnt/proteus/vm/install ]]; then
    printf '%s' /mnt/proteus
    return 0
  fi
  echo "proteus-install: set PROTEUS_ROOT or mount /mnt/proteus" >&2
  return 1
}

proteus_log() {
  local line="==> $*"
  echo "${line}"
  if [[ -n "${PROTEUS_INSTALL_LOG:-}" ]]; then
    printf '%s %s\n' "$(date -Iseconds 2>/dev/null || date)" "${line}" >>"${PROTEUS_INSTALL_LOG}" 2>/dev/null || true
  fi
}

proteus_root() {
  if [[ "${EUID}" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

proteus_session_user() {
  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    printf '%s' "${SUDO_USER}"
  elif [[ -n "${PROTEUS_USER:-}" ]]; then
    printf '%s' "${PROTEUS_USER}"
  elif [[ "${USER:-}" != "root" && -n "${USER:-}" ]]; then
    printf '%s' "${USER}"
  else
    printf '%s' andrew
  fi
}

proteus_as_user() {
  local u
  u="$(proteus_session_user)"
  if [[ "${EUID}" -eq 0 && "${u}" != "root" ]]; then
    sudo -u "${u}" -- "$@"
  else
    "$@"
  fi
}

# Install a helper onto PATH. Symlink when the tree is live under /mnt/proteus
# (dogfood tracks the share — cannot go stale); install a copy otherwise.
# Also links a per-user fallback under ~/.local/bin.
proteus_install_helper() {
  local src="$1"
  local name dest user_name user_home
  name="$(basename "${src}")"
  dest="/usr/local/bin/${name}"
  [[ -f "${src}" ]] || return 0
  proteus_root install -d /usr/local/bin
  if [[ "${src}" == /mnt/proteus/* ]]; then
    proteus_root ln -sfn "${src}" "${dest}"
    proteus_log "linked ${dest} -> ${src}"
  else
    proteus_root install -m 755 "${src}" "${dest}"
    proteus_log "installed ${dest}"
  fi
  user_name="$(proteus_session_user)"
  user_home="$(getent passwd "${user_name}" 2>/dev/null | cut -d: -f6 || true)"
  [[ -n "${user_home}" ]] || user_home="/home/${user_name}"
  if [[ -d "${user_home}" ]]; then
    proteus_as_user mkdir -p "${user_home}/.local/bin" 2>/dev/null || true
    proteus_as_user ln -sfn "${src}" "${user_home}/.local/bin/${name}" 2>/dev/null \
      || proteus_as_user install -m 755 "${src}" "${user_home}/.local/bin/${name}" 2>/dev/null \
      || true
  fi
}

# Load package names from a list file (comments/blank ignored).
proteus_read_pkg_list() {
  local list="$1"
  [[ -f "${list}" ]] || {
    echo "proteus-install: missing package list ${list}" >&2
    return 1
  }
  grep -vE '^\s*(#|$)' "${list}" | sed 's/[[:space:]]*$//'
}

# pacman -S --needed from a list file (no-op if every pkg already installed).
proteus_pacman_from_list() {
  local list="$1"
  local -a pkgs=()
  local -a missing=()
  local pkg
  mapfile -t pkgs < <(proteus_read_pkg_list "${list}")
  if [[ "${#pkgs[@]}" -eq 0 ]]; then
    echo "proteus-install: empty package list ${list}" >&2
    return 1
  fi
  if command -v pacman >/dev/null 2>&1; then
    for pkg in "${pkgs[@]}"; do
      pacman -Q "${pkg}" >/dev/null 2>&1 || missing+=("${pkg}")
    done
    if [[ "${#missing[@]}" -eq 0 ]]; then
      proteus_log "pacman skip — all ${#pkgs[@]} already installed ($(basename "${list}"))"
      return 0
    fi
    proteus_log "pacman -S --needed (${#missing[@]}/${#pkgs[@]} missing from $(basename "${list}"))"
  else
    proteus_log "pacman -S --needed (${#pkgs[@]} from $(basename "${list}"))"
  fi
  proteus_root pacman -Sy --noconfirm archlinux-keyring || true
  proteus_root pacman -S --noconfirm --needed "${pkgs[@]}"
}

# Skip stage if named in PROTEUS_INSTALL_SKIP=preflight,packaging,...
proteus_stage_skipped() {
  local stage="$1"
  local skip="${PROTEUS_INSTALL_SKIP:-}"
  [[ -n "${skip}" ]] || return 1
  local IFS=','
  local s
  for s in ${skip}; do
    s="${s// /}"
    [[ "${s}" == "${stage}" ]] && return 0
  done
  return 1
}

# Preferred guest status dir; overridable. Resolved path cached after ensure.
proteus_status_dir_preferred() {
  if [[ -n "${PROTEUS_INSTALL_STATUS_DIR:-}" ]]; then
    printf '%s' "${PROTEUS_INSTALL_STATUS_DIR}"
  elif [[ "${EUID}" -eq 0 ]]; then
    printf '%s' /var/lib/proteus/install
  else
    printf '%s' "${XDG_CACHE_HOME:-${HOME}/.cache}/proteus-install"
  fi
}

proteus_status_dir_fallback() {
  if [[ -n "${XDG_CACHE_HOME:-}" ]]; then
    printf '%s' "${XDG_CACHE_HOME}/proteus-install"
  elif [[ -n "${HOME:-}" && -w "${HOME}" ]]; then
    printf '%s' "${HOME}/.cache/proteus-install"
  elif [[ -n "${TMPDIR:-}" ]]; then
    printf '%s' "${TMPDIR%/}/proteus-install"
  else
    printf '%s' /tmp/proteus-install
  fi
}

proteus_status_dir() {
  if [[ -n "${PROTEUS_INSTALL_STATUS_RESOLVED:-}" ]]; then
    printf '%s' "${PROTEUS_INSTALL_STATUS_RESOLVED}"
    return 0
  fi
  proteus_status_dir_preferred
}

proteus_status_ensure() {
  local dir fb
  if [[ -n "${PROTEUS_INSTALL_STATUS_RESOLVED:-}" ]]; then
    mkdir -p "${PROTEUS_INSTALL_STATUS_RESOLVED}" 2>/dev/null || true
    return 0
  fi
  dir="$(proteus_status_dir_preferred)"
  if mkdir -p "${dir}" 2>/dev/null; then
    export PROTEUS_INSTALL_STATUS_RESOLVED="${dir}"
    return 0
  fi
  if [[ "${EUID}" -ne 0 ]]; then
    if proteus_root mkdir -p "${dir}" 2>/dev/null; then
      export PROTEUS_INSTALL_STATUS_RESOLVED="${dir}"
      return 0
    fi
  fi
  for fb in \
    "$(proteus_status_dir_fallback)" \
    "${TMPDIR:-/tmp}/proteus-install" \
    "${PROTEUS_ROOT:-/tmp}/.proteus-install-status"
  do
    if mkdir -p "${fb}" 2>/dev/null; then
      export PROTEUS_INSTALL_STATUS_RESOLVED="${fb}"
      export PROTEUS_INSTALL_STATUS_DIR="${fb}"
      proteus_log "status dir fallback → ${fb}"
      return 0
    fi
  done
  echo "proteus-install: cannot create status dir" >&2
  return 1
}

proteus_stage_done_mark() {
  local stage="$1"
  local dir
  proteus_status_ensure
  dir="$(proteus_status_dir)"
  if ! tee "${dir}/${stage}.done" >/dev/null <<<"$(date -Iseconds 2>/dev/null || date)" 2>/dev/null; then
    proteus_root tee "${dir}/${stage}.done" >/dev/null <<<"$(date -Iseconds 2>/dev/null || date)" 2>/dev/null \
      || proteus_log "warn: could not write ${dir}/${stage}.done"
  fi
}

proteus_stage_already_done() {
  local stage="$1"
  # Only honor resume markers when PROTEUS_INSTALL_RESUME=1
  [[ "${PROTEUS_INSTALL_RESUME:-0}" == "1" ]] || return 1
  proteus_status_ensure 2>/dev/null || true
  [[ -f "$(proteus_status_dir)/${stage}.done" ]]
}

# Best-effort refresh: bring every repo package from a list current (--needed).
# Skips packages not in repos (AUR names) and logs failures without aborting —
# used by the PROTEUS_INSTALL_UPDATE=1 pass after stages.
proteus_pacman_refresh_list() {
  local list="$1"
  local pkg
  command -v pacman >/dev/null 2>&1 || return 0
  while IFS= read -r pkg; do
    [[ -n "${pkg}" ]] || continue
    if ! pacman -Si "${pkg}" >/dev/null 2>&1 && ! pacman -Q "${pkg}" >/dev/null 2>&1; then
      proteus_log "update skip ${pkg} (not in repos — AUR/manual)"
      continue
    fi
    proteus_root pacman -S --needed --noconfirm "${pkg}" >/dev/null 2>&1 \
      || proteus_log "warn: update failed for ${pkg}"
  done < <(proteus_read_pkg_list "${list}")
}

# True if every package in a list is installed (pacman -Q).
proteus_pkgs_installed() {
  local list="$1"
  local pkg
  while IFS= read -r pkg; do
    [[ -n "${pkg}" ]] || continue
    pacman -Q "${pkg}" >/dev/null 2>&1 || return 1
  done < <(proteus_read_pkg_list "${list}")
  return 0
}
