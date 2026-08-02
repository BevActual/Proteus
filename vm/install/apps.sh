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

# Interim capture helpers on PATH (first-party chrome will replace).
# proteus_install_helper symlinks when the tree is live at /mnt/proteus.
SCRIPTS="${PROTEUS_ROOT}/shell/scripts"
for s in proteus-screenshot proteus-clipboard proteus-colorpick proteus-terminal \
         proteus-workspace \
         proteus-console-launch proteus-console-seat proteus-console-capabilities \
         proteus-console-session \
         proteus-permissions.py privacy-indicators.py \
         proteus-calendar-events.py proteus-calendar-mutate.py \
         proteus-mail-glance.py proteus-mail-send.py proteus-contacts-glance.py \
         proteus-headscale.py \
         proteus-workloads.py \
         proteus-defaults.py beacon-file-index.py \
         proteus-pin.py check-unlock.py; do
  proteus_install_helper "${SCRIPTS}/${s}"
done

# Hard posture switch + Guide-button listener + soft profile helper (console)
for s in proteus-posture proteus-guide set-hypr-profile.sh; do
  proteus_install_helper "${GUEST}/${s}"
done

proteus_root bash "${GUEST}/install-settings-app.sh"
proteus_root bash "${GUEST}/install-workloads-app.sh"
# Idempotent: refresh NoDisplay stubs even if Settings install was a no-op
proteus_root bash "${GUEST}/hide-system-apps.sh"
proteus_root bash "${GUEST}/install-proteus-qs-user-unit.sh" || {
  echo "apps: note — proteus-qs user-unit install skipped" >&2
}
proteus_root bash "${GUEST}/install-lock-pam.sh" || {
  echo "apps: note — install-lock-pam skipped or failed (lock falls back to login PAM)" >&2
}

proteus_log "apps OK (user=${USER_NAME} SUDO_USER=${SUDO_USER:-})"
