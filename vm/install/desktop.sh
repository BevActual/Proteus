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

# Bootstrap an AUR helper when the desktop kit needs one and none exists.
# Without this, Settings → Software → AUR is permanently honesty-gated off and
# every AUR seat below is skipped. yay-bin is a prebuilt package, so makepkg
# only repackages it — no Go toolchain, no -s (deps are already installed).
proteus_bootstrap_aur_helper() {
  command -v yay >/dev/null 2>&1 && return 0
  command -v paru >/dev/null 2>&1 && return 0
  if ! command -v git >/dev/null 2>&1 || ! command -v makepkg >/dev/null 2>&1; then
    proteus_log "AUR helper: git/base-devel missing — skip bootstrap"
    return 1
  fi
  local user_name user_home build
  user_name="$(proteus_session_user)"
  user_home="$(getent passwd "${user_name}" 2>/dev/null | cut -d: -f6 || true)"
  [[ -n "${user_home}" && -d "${user_home}" ]] || return 1
  build="${user_home}/.cache/proteus-aur-bootstrap"

  proteus_log "AUR helper: bootstrapping yay-bin"
  proteus_as_user rm -rf "${build}" 2>/dev/null || true
  proteus_as_user mkdir -p "${build}" 2>/dev/null || true
  if ! proteus_as_user git clone --depth 1 https://aur.archlinux.org/yay-bin.git "${build}/yay-bin" 2>/dev/null; then
    proteus_log "warn: AUR helper clone failed (offline?) — AUR seats will be skipped"
    return 1
  fi
  if ! proteus_as_user bash -c "cd '${build}/yay-bin' && makepkg --noconfirm --nodeps" 2>/dev/null; then
    proteus_log "warn: yay-bin makepkg failed — AUR seats will be skipped"
    return 1
  fi
  local built
  built="$(find "${build}/yay-bin" -maxdepth 1 -name 'yay-bin-*.pkg.tar.*' 2>/dev/null | head -1)"
  if [[ -z "${built}" ]]; then
    proteus_log "warn: yay-bin package not produced — AUR seats will be skipped"
    return 1
  fi
  if proteus_root pacman -U --noconfirm "${built}"; then
    proteus_log "AUR helper: yay installed"
    proteus_as_user rm -rf "${build}" 2>/dev/null || true
    return 0
  fi
  proteus_log "warn: pacman -U yay-bin failed — AUR seats will be skipped"
  return 1
}

if [[ "${#AUR_PKGS[@]}" -gt 0 ]]; then
  proteus_bootstrap_aur_helper || true
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

# Desktop video UI — Celluloid (mpv stays for console / yt-dlp).
CELLULOID_DESKTOP=""
for cand in io.github.celluloid_player.Celluloid.desktop celluloid.desktop; do
  if [[ -f "/usr/share/applications/${cand}" ]]; then
    CELLULOID_DESKTOP="${cand}"
    break
  fi
done
if [[ -n "${CELLULOID_DESKTOP}" ]]; then
  DEFAULTS="${PROTEUS_ROOT}/shell/scripts/proteus-defaults.py"
  if [[ -f "${DEFAULTS}" ]]; then
    proteus_as_user python3 "${DEFAULTS}" set video "${CELLULOID_DESKTOP}" 2>/dev/null \
      || proteus_log "warn: could not set video default via proteus-defaults"
  else
    proteus_as_user xdg-mime default "${CELLULOID_DESKTOP}" video/mp4 2>/dev/null || true
  fi
fi

proteus_log "desktop OK"
