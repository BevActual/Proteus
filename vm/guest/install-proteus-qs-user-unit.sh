#!/usr/bin/env bash
# Install optional systemd --user unit for proteus-qs (does not enable by default).
# Hyprland exec-once remains the default dogfood SoT until you opt in.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
UNIT_SRC="${ROOT}/env/systemd/user/proteus-qs.service"
[[ -f "${UNIT_SRC}" ]] || { echo "missing ${UNIT_SRC}" >&2; exit 1; }

# Target session user when run via sudo
if [[ "${EUID}" -eq 0 ]]; then
  USER_NAME="${SUDO_USER:-${PROTEUS_USER:-}}"
  [[ -n "${USER_NAME}" && "${USER_NAME}" != "root" ]] || {
    echo "install-proteus-qs-user-unit: run as session user, or sudo with SUDO_USER set" >&2
    exit 1
  }
  USER_HOME="$(getent passwd "${USER_NAME}" | cut -d: -f6)"
  UNIT_DIR="${USER_HOME}/.config/systemd/user"
  install -d -o "${USER_NAME}" -g "${USER_NAME}" "${UNIT_DIR}"
  # Rewrite PROTEUS_ROOT in a copy for this install tree
  sed "s|/mnt/proteus|${ROOT}|g" "${UNIT_SRC}" > "${UNIT_DIR}/proteus-qs.service"
  chown "${USER_NAME}:${USER_NAME}" "${UNIT_DIR}/proteus-qs.service"
  chmod 644 "${UNIT_DIR}/proteus-qs.service"
  if command -v systemctl >/dev/null 2>&1; then
    sudo -u "${USER_NAME}" XDG_RUNTIME_DIR="/run/user/$(id -u "${USER_NAME}")" \
      systemctl --user daemon-reload 2>/dev/null || true
  fi
  echo "Installed ${UNIT_DIR}/proteus-qs.service (not enabled)"
  echo "Opt-in: sudo -u ${USER_NAME} systemctl --user enable --now proteus-qs.service"
  echo "Then comment out proteus-qs exec-once in ${USER_HOME}/.config/hypr/hyprland.conf"
else
  UNIT_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/systemd/user"
  install -d "${UNIT_DIR}"
  sed "s|/mnt/proteus|${ROOT}|g" "${UNIT_SRC}" > "${UNIT_DIR}/proteus-qs.service"
  chmod 644 "${UNIT_DIR}/proteus-qs.service"
  systemctl --user daemon-reload 2>/dev/null || true
  echo "Installed ${UNIT_DIR}/proteus-qs.service (not enabled)"
  echo "Opt-in: systemctl --user enable --now proteus-qs.service"
  echo "Then comment out proteus-qs exec-once in ~/.config/hypr/hyprland.conf"
fi
