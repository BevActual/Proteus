#!/usr/bin/env bash
# console — console posture kit: multilib, seats (Steam / RetroArch + cores),
# Gamescope, pad udev rules, seat helpers on PATH, console.conf seed, and
# posture-fact ↔ hypr-profile drift fix.
# Skip with: PROTEUS_INSTALL_SKIP=console
set -euo pipefail
# shellcheck source=helpers.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

PROTEUS_ROOT="$(proteus_install_root)"
MACHINE="${PROTEUS_ROOT}/install/machine"
SCRIPTS="${PROTEUS_ROOT}/shell/scripts"
LIST="${PROTEUS_ROOT}/install/proteus-console.packages"
USER_NAME="$(proteus_session_user)"
USER_HOME="$(getent passwd "${USER_NAME}" 2>/dev/null | cut -d: -f6 || true)"
[[ -n "${USER_HOME}" ]] || USER_HOME="/home/${USER_NAME}"
export PROTEUS_USER="${USER_NAME}"

# 1. multilib — steam + lib32 GL live there
enable_multilib() {
  local conf=/etc/pacman.conf
  [[ -f "${conf}" ]] || {
    proteus_log "console: no pacman.conf — skip multilib"
    return 0
  }
  if grep -q '^\[multilib\]' "${conf}"; then
    proteus_log "multilib already enabled"
    return 0
  fi
  if grep -q '^#\[multilib\]' "${conf}"; then
    proteus_log "enabling [multilib] in pacman.conf"
    proteus_root sed -i '/^#\[multilib\]/,/^#Include = \/etc\/pacman.d\/mirrorlist/{s/^#//}' "${conf}"
  else
    proteus_log "appending [multilib] to pacman.conf"
    proteus_root bash -c 'printf "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n" >>/etc/pacman.conf'
  fi
  proteus_root pacman -Sy --noconfirm
}

# 2. Packages — per-package best-effort: a missing mirror package (libretro
# core, lib32 on odd mirrors) must not fail the stage; seats show honesty.
# AUR-only names (game-devices-udev) fall back to yay/paru like desktop.sh.
if command -v pacman >/dev/null 2>&1; then
  enable_multilib
  while IFS= read -r pkg; do
    [[ -n "${pkg}" ]] || continue
    pacman -Q "${pkg}" >/dev/null 2>&1 && continue
    if pacman -Si "${pkg}" >/dev/null 2>&1; then
      if proteus_root pacman -S --needed --noconfirm "${pkg}" 2>&1 | tail -4; then
        proteus_log "console pkg ${pkg} OK"
      else
        proteus_log "warn: ${pkg} not installed (mirror/multilib) — console shows honesty"
      fi
    elif command -v yay >/dev/null 2>&1; then
      proteus_log "AUR via yay: ${pkg}"
      proteus_as_user yay -S --noconfirm --needed "${pkg}" \
        || proteus_log "warn: yay failed for ${pkg} — install later (needs interactive sudo)"
    elif command -v paru >/dev/null 2>&1; then
      proteus_log "AUR via paru: ${pkg}"
      proteus_as_user paru -S --noconfirm --needed "${pkg}" \
        || proteus_log "warn: paru failed for ${pkg} — install later (needs interactive sudo)"
    else
      proteus_log "warn: ${pkg} not in repos and no yay/paru — skipped"
    fi
  done < <(proteus_read_pkg_list "${LIST}")
else
  proteus_log "console: pacman missing — skip packages"
fi

# 3. Helpers on PATH + console.conf seed (idempotent; packages owned above)
if [[ -f "${MACHINE}/apply-console-kit.sh" ]]; then
  proteus_root env PROTEUS_SKIP_CONSOLE_PACKAGES=1 \
    PROTEUS_USER="${USER_NAME}" SUDO_USER="${USER_NAME}" \
    bash "${MACHINE}/apply-console-kit.sh" \
    || proteus_log "warn: apply-console-kit failed"
fi

# 4. Posture fact ≠ hypr profile drift fix (the "console launches desktop
# chrome" bug class): re-point proteus-profile.conf at the fact's profile.
FACT_FILE="${USER_HOME}/.config/proteus/posture"
POINTER="${USER_HOME}/.config/hypr/proteus-profile.conf"
if [[ -f "${FACT_FILE}" && -f "${POINTER}" ]]; then
  fact="$(tr -d '[:space:]' < "${FACT_FILE}" 2>/dev/null || true)"
  case "${fact}" in
    desktop|console|host|home)
      if ! grep -q "profiles/${fact}\.conf" "${POINTER}" 2>/dev/null; then
        proteus_log "posture fact (${fact}) ≠ hypr profile pointer — re-syncing"
        proteus_as_user env HOME="${USER_HOME}" PROTEUS_ROOT="${PROTEUS_ROOT}" \
          bash "${SCRIPTS}/set-hypr-profile.sh" "${fact}" \
          || proteus_log "warn: profile re-sync failed"
      fi
      ;;
    *) ;;
  esac
fi

proteus_log "console OK (user=${USER_NAME})"
