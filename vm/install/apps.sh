#!/usr/bin/env bash
# apps — Settings launcher, keybinds, desktop conf, PAM lock, capture bins
set -euo pipefail
# shellcheck source=helpers.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

PROTEUS_ROOT="$(proteus_install_root)"
GUEST="${PROTEUS_ROOT}/vm/guest"
USER_NAME="$(proteus_session_user)"

# Guest mutators key off SUDO_USER for per-user home. When invoked as root
# without sudo (or via `sudo env`), ensure SUDO_USER matches the session user.
export PROTEUS_USER="${USER_NAME}"
if [[ "${EUID}" -eq 0 ]]; then
  if [[ -z "${SUDO_USER:-}" || "${SUDO_USER}" == "root" ]]; then
    export SUDO_USER="${USER_NAME}"
  fi
fi

# Interim capture helpers on PATH (first-party chrome will replace)
SCRIPTS="${PROTEUS_ROOT}/shell/scripts"
for s in proteus-screenshot proteus-clipboard proteus-colorpick proteus-terminal; do
  if [[ -f "${SCRIPTS}/${s}" ]]; then
    proteus_root install -m 755 "${SCRIPTS}/${s}" "/usr/local/bin/${s}"
    proteus_log "installed /usr/local/bin/${s}"
  fi
done

proteus_root bash "${GUEST}/install-settings-app.sh"
proteus_root bash "${GUEST}/install-lock-pam.sh" || {
  echo "apps: note — install-lock-pam skipped or failed (lock falls back to login PAM)" >&2
}

proteus_log "apps OK (user=${USER_NAME} SUDO_USER=${SUDO_USER:-})"
