#!/usr/bin/env bash
# apply-console-kit — install console dogfood packages + helpers (idempotent).
# Usage (guest): sudo bash /mnt/proteus/vm/guest/apply-console-kit.sh
# Then: proteus-posture console
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GUEST="${ROOT}/vm/guest"
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

echo "==> apply-console-kit (user=${USER_NAME} root=${ROOT})"

# Packages (already listed in proteus-desktop.packages)
if command -v pacman >/dev/null 2>&1; then
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

# Helpers on PATH
as_root install -d /usr/local/bin
for s in proteus-posture proteus-guide set-hypr-profile.sh; do
  if [[ -f "${GUEST}/${s}" ]]; then
    as_root install -m 755 "${GUEST}/${s}" "/usr/local/bin/${s}"
    echo "  installed /usr/local/bin/${s}"
  fi
done
for s in proteus-console-launch proteus-terminal proteus-qs proteus-webapp; do
  if [[ -f "${SCRIPTS}/${s}" ]]; then
    as_root install -m 755 "${SCRIPTS}/${s}" "/usr/local/bin/${s}"
    echo "  installed /usr/local/bin/${s}"
  fi
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
command -v proteus-posture >/dev/null && echo "  proteus-posture: $(command -v proteus-posture)" || echo "  proteus-posture: MISSING"
command -v proteus-console-launch >/dev/null && echo "  proteus-console-launch: $(command -v proteus-console-launch)" || echo "  proteus-console-launch: MISSING"
command -v proteus-guide >/dev/null && echo "  proteus-guide: $(command -v proteus-guide)" || echo "  proteus-guide: MISSING"
command -v proteus-webapp >/dev/null && echo "  proteus-webapp: $(command -v proteus-webapp)" || echo "  proteus-webapp: MISSING"
command -v steam >/dev/null && echo "  steam: $(command -v steam)" || echo "  steam: MISSING"
command -v retroarch >/dev/null && echo "  retroarch: $(command -v retroarch)" || echo "  retroarch: MISSING"
echo "==> apply-console-kit done"
echo "    Enter console: proteus-posture console"
