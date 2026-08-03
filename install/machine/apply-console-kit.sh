#!/usr/bin/env bash
# apply-console-kit — install console dogfood packages + helpers (idempotent).
# Usage (guest): sudo bash /mnt/proteus/install/machine/apply-console-kit.sh
# Then: proteus-posture console
set -euo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)"
SCRIPTS="${ROOT}/shell/scripts"
USER_NAME="${SUDO_USER:-${PROTEUS_USER:-${USER:-andrew}}}"
USER_HOME="$(getent passwd "${USER_NAME}" 2>/dev/null | cut -d: -f6 || echo "/home/${USER_NAME}")"

as_root() {
  if [[ "${EUID}" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

as_user() {
  if [[ "${EUID}" -eq 0 && "${USER_NAME}" != "root" ]]; then
    sudo -u "${USER_NAME}" -- "$@"
  else
    "$@"
  fi
}

# Shared install helpers (proteus_install_helper: symlink when tree is live at
# /mnt/proteus so dogfood always tracks the share; otherwise install a copy).
export PROTEUS_USER="${USER_NAME}"
# shellcheck source=../install/helpers.sh
source "${ROOT}/install/helpers.sh"

install_helper() {
  proteus_install_helper "$1"
}

echo "==> apply-console-kit (user=${USER_NAME} root=${ROOT})"

# Packages — package SoT is install/proteus-console.packages (console stage
# enables multilib). Direct runs still get a best-effort install; the overlay
# console stage sets PROTEUS_SKIP_CONSOLE_PACKAGES=1 since it owns packages.
if [[ "${PROTEUS_SKIP_CONSOLE_PACKAGES:-0}" == "1" ]]; then
  echo "  packages: skipped (console stage owns them)"
elif command -v pacman >/dev/null 2>&1; then
  as_root pacman -S --needed --noconfirm gamescope python-evdev 2>&1 | tail -30
  # Steam / RetroArch — best-effort each (multilib / mirrors may omit steam)
  for pkg in steam retroarch; do
    if as_root pacman -S --needed --noconfirm "$pkg" 2>&1 | tail -8; then
      :
    else
      echo "apply-console-kit: ${pkg} not installed (enable multilib / check mirror) — seat shows honesty" >&2
    fi
  done
else
  echo "apply-console-kit: pacman missing — skip packages" >&2
fi

# Helpers on PATH — all runtime helpers live in shell/scripts.
for s in proteus-posture proteus-guide set-hypr-profile.sh \
         proteus-console-launch proteus-console-seat proteus-console-capabilities \
         proteus-console-session proteus-console-gs-session proteus-console-focus \
         proteus-terminal proteus-qs proteus-webapp; do
  install_helper "${SCRIPTS}/${s}"
done

# Seed console Hypr profile for the session user
as_user mkdir -p "${USER_HOME}/.config/hypr/profiles" "${USER_HOME}/.config/proteus"
if [[ -f "${ROOT}/env/hypr/profiles/console.conf" ]]; then
  as_user install -m 644 "${ROOT}/env/hypr/profiles/console.conf" \
    "${USER_HOME}/.config/hypr/profiles/console.conf"
  echo "  seeded ${USER_HOME}/.config/hypr/profiles/console.conf"
fi

echo "==> summary"
command -v gamescope >/dev/null && echo "  gamescope: $(command -v gamescope)" || echo "  gamescope: MISSING"
python3 -c 'import evdev' 2>/dev/null && echo "  python-evdev: ok" || echo "  python-evdev: MISSING"
if [[ -x "${SCRIPTS}/proteus-console-capabilities" ]]; then
  echo "  capabilities: $("${SCRIPTS}/proteus-console-capabilities" 2>/dev/null || echo '{}')"
fi
command -v proteus-posture >/dev/null && echo "  proteus-posture: $(command -v proteus-posture)" || echo "  proteus-posture: MISSING"
command -v proteus-console-launch >/dev/null && echo "  proteus-console-launch: $(command -v proteus-console-launch)" || echo "  proteus-console-launch: MISSING"
command -v proteus-console-seat >/dev/null && echo "  proteus-console-seat: $(command -v proteus-console-seat)" || echo "  proteus-console-seat: MISSING"
command -v proteus-console-capabilities >/dev/null && echo "  proteus-console-capabilities: $(command -v proteus-console-capabilities)" || echo "  proteus-console-capabilities: MISSING"
command -v proteus-console-session >/dev/null && echo "  proteus-console-session: $(command -v proteus-console-session)" || echo "  proteus-console-session: MISSING"
command -v proteus-guide >/dev/null && echo "  proteus-guide: $(command -v proteus-guide)" || echo "  proteus-guide: MISSING"
command -v proteus-webapp >/dev/null && echo "  proteus-webapp: $(command -v proteus-webapp)" || echo "  proteus-webapp: MISSING"
command -v steam >/dev/null && echo "  steam: $(command -v steam)" || echo "  steam: MISSING"
command -v retroarch >/dev/null && echo "  retroarch: $(command -v retroarch)" || echo "  retroarch: MISSING"
# Honesty: this script is helpers + best-effort pkgs — not the full console stage.
missing_pkgs=0
command -v steam >/dev/null 2>&1 || missing_pkgs=1
command -v retroarch >/dev/null 2>&1 || missing_pkgs=1
if [[ "${PROTEUS_SKIP_CONSOLE_PACKAGES:-0}" == "1" ]]; then
  echo "  kit mode: helpers/seed only (console stage owns packages)"
elif [[ "${missing_pkgs}" -eq 1 ]]; then
  echo "  kit mode: helpers OK; Steam/RetroArch/cores incomplete"
  echo "  full packages: sudo bash ${ROOT}/install/machine/install-console-software.sh"
  echo "                 (or overlay PROTEUS_INSTALL_ONLY=console — enables multilib)"
else
  echo "  kit mode: helpers + Steam/RetroArch present (cores/udev via console stage)"
fi
echo "==> apply-console-kit done"
echo "    Enter console: bash ${ROOT}/scripts/dogfood/dogfood-console.sh"
echo "                or: proteus-posture console"
