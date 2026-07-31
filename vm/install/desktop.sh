#!/usr/bin/env bash
# desktop — optional default apps (chromium, files, viewers, …)
# Default ON for dogfood. Skip with: PROTEUS_INSTALL_DESKTOP=0
# Also skipped if listed in PROTEUS_INSTALL_SKIP=desktop
set -euo pipefail
# shellcheck source=helpers.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

if [[ "${PROTEUS_INSTALL_DESKTOP:-1}" == "0" ]]; then
  proteus_log "desktop: skipped (PROTEUS_INSTALL_DESKTOP=0)"
  exit 0
fi

PROTEUS_ROOT="$(proteus_install_root)"
LIST="${PROTEUS_ROOT}/vm/install/proteus-desktop.packages"

proteus_log "desktop kit (browser=chromium)"

# Split syncable vs AUR-only so a missing official package (e.g. localsend on
# vanilla Arch) does not fail the whole desktop kit.
mapfile -t DESK_PKGS < <(proteus_read_pkg_list "${LIST}")
SYNC_PKGS=()
AUR_PKGS=()
for pkg in "${DESK_PKGS[@]}"; do
  if pacman -Si "${pkg}" >/dev/null 2>&1 || pacman -Q "${pkg}" >/dev/null 2>&1; then
    SYNC_PKGS+=("${pkg}")
  else
    AUR_PKGS+=("${pkg}")
  fi
done

if [[ "${#SYNC_PKGS[@]}" -gt 0 ]]; then
  TMP_LIST="$(mktemp)"
  printf '%s\n' "${SYNC_PKGS[@]}" > "${TMP_LIST}"
  proteus_pacman_from_list "${TMP_LIST}"
  rm -f "${TMP_LIST}"
fi

for pkg in "${AUR_PKGS[@]}"; do
  if pacman -Q "${pkg}" >/dev/null 2>&1; then
    continue
  fi
  # LocalSend: either AUR name provides /usr/bin/localsend
  if [[ "${pkg}" == "localsend" || "${pkg}" == "localsend-bin" ]]; then
    if pacman -Q localsend >/dev/null 2>&1 || pacman -Q localsend-bin >/dev/null 2>&1; then
      proteus_log "LocalSend already installed (localsend or localsend-bin)"
      continue
    fi
  fi
  if command -v yay >/dev/null 2>&1; then
    proteus_log "AUR via yay: ${pkg}"
    proteus_as_user yay -S --noconfirm --needed "${pkg}" || \
      proteus_log "warn: yay failed for ${pkg} — install later (keep VM open; needs sudo)"
  elif command -v paru >/dev/null 2>&1; then
    proteus_log "AUR via paru: ${pkg}"
    proteus_as_user paru -S --noconfirm --needed "${pkg}" || \
      proteus_log "warn: paru failed for ${pkg} — install later (keep VM open; needs sudo)"
  else
    proteus_log "skip ${pkg} (not in repos; no yay/paru) — Settings → Network → LocalSend shows install honesty"
  fi
done

if command -v xdg-settings >/dev/null 2>&1; then
  proteus_as_user xdg-settings set default-web-browser chromium.desktop 2>/dev/null || true
fi

proteus_log "desktop OK"
