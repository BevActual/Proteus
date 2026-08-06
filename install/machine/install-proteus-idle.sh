#!/usr/bin/env bash
# install-proteus-idle.sh — install proteus-idle helper + user unit (idempotent).
set -euo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)"
# shellcheck source=../helpers.sh
source "${ROOT}/install/helpers.sh"

USER_NAME="$(proteus_session_user)"
USER_HOME="$(getent passwd "${USER_NAME}" 2>/dev/null | cut -d: -f6 || echo "/home/${USER_NAME}")"
SCRIPTS="${ROOT}/shell/scripts"
UNIT_SRC="${ROOT}/install/machine/assets/proteus-idle.service"
UNIT_DIR="${USER_HOME}/.config/systemd/user"

proteus_install_helper "${SCRIPTS}/proteus-idle"

if [[ ! -f "${UNIT_SRC}" ]]; then
  echo "install-proteus-idle: missing ${UNIT_SRC}" >&2
  exit 1
fi

as_user() {
  if [[ "${EUID}" -eq 0 && "${USER_NAME}" != "root" ]]; then
    sudo -u "${USER_NAME}" -- "$@"
  else
    "$@"
  fi
}

as_user mkdir -p "${UNIT_DIR}"
as_user install -m 644 "${UNIT_SRC}" "${UNIT_DIR}/proteus-idle.service"

# Point ExecStart at resolved helper if present on PATH.
if command -v proteus-idle >/dev/null 2>&1; then
  IDLE_BIN="$(command -v proteus-idle)"
elif [[ -x /usr/local/bin/proteus-idle ]]; then
  IDLE_BIN=/usr/local/bin/proteus-idle
else
  IDLE_BIN="${SCRIPTS}/proteus-idle"
fi
as_user sed -i "s|^ExecStart=.*|ExecStart=${IDLE_BIN}|" "${UNIT_DIR}/proteus-idle.service"

as_user systemctl --user daemon-reload 2>/dev/null || true
as_user systemctl --user enable --now proteus-idle.service 2>/dev/null \
  || echo "install-proteus-idle: note — enable --now skipped (no user bus yet)"

echo "Installed proteus-idle → ${IDLE_BIN}; user unit → ${UNIT_DIR}/proteus-idle.service"
