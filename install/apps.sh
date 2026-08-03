#!/usr/bin/env bash
# apps — Settings launcher, keybinds, desktop conf, PAM lock, capture bins
set -euo pipefail
# shellcheck source=helpers.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

PROTEUS_ROOT="$(proteus_install_root)"
# Install-time mutators (install-*.sh / apply-*.sh). Runtime PATH helpers live
# in shell/scripts alongside every other helper — see SCRIPTS below.
MACHINE="${PROTEUS_ROOT}/install/machine"
USER_NAME="$(proteus_session_user)"

# Machine mutators key off SUDO_USER for per-user home. When invoked as root
# without sudo (or via `sudo env`), ensure SUDO_USER matches the session user.
export PROTEUS_USER="${USER_NAME}"
if [[ "${EUID}" -eq 0 ]]; then
  if [[ -z "${SUDO_USER:-}" || "${SUDO_USER}" == "root" ]]; then
    export SUDO_USER="${USER_NAME}"
  fi
fi

# Migration: the layout split moved runtime helpers out of the old dev/vm/guest
# path, so an install from before it has dangling /usr/local/bin symlinks.
# proteus_install_helper re-points everything it still installs, but a broken
# symlink left behind by a removed helper would shadow PATH forever.
prune_dangling_helpers() {
  local link
  for link in /usr/local/bin/proteus-* /usr/local/bin/set-hypr-profile.sh; do
    [[ -L "${link}" ]] || continue
    [[ -e "${link}" ]] && continue   # resolves fine — leave it
    proteus_root rm -f "${link}" 2>/dev/null || true
    proteus_log "pruned dangling helper symlink ${link}"
  done
}
prune_dangling_helpers

# Every runtime PATH helper — capture bins, console seats, session/posture, and
# the soft profile helper. proteus_install_helper symlinks into the live tree.
SCRIPTS="${PROTEUS_ROOT}/shell/scripts"
for s in proteus-screenshot proteus-clipboard proteus-colorpick proteus-terminal \
         proteus-workspace \
         proteus-console-launch proteus-console-seat proteus-console-capabilities \
         proteus-console-session proteus-console-gs-session proteus-console-focus \
         proteus-console-games.py \
         proteus-permissions.py privacy-indicators.py \
         proteus-calendar-events.py proteus-calendar-mutate.py \
         proteus-mail-glance.py proteus-mail-send.py \
         proteus-contacts-glance.py proteus-contacts-mutate.py \
         proteus-headscale.py \
         proteus-workloads.py proteus-host-metrics.py \
         proteus-defaults.py beacon-file-index.py \
         proteus-snapshot proteus-cli-surface \
         proteus-pin.py check-unlock.py \
         proteus-session proteus-posture proteus-host-seat proteus-guide \
         proteus-bg set-hypr-profile.sh; do
  proteus_install_helper "${SCRIPTS}/${s}"
done

proteus_root bash "${MACHINE}/install-settings-app.sh"
proteus_root bash "${MACHINE}/install-workloads-app.sh"
# Idempotent: refresh NoDisplay stubs even if Settings install was a no-op
proteus_root bash "${MACHINE}/hide-system-apps.sh"
proteus_root bash "${MACHINE}/install-proteus-qs-user-unit.sh" || {
  echo "apps: note — proteus-qs user-unit install skipped" >&2
}
proteus_root bash "${MACHINE}/install-lock-pam.sh" || {
  echo "apps: note — install-lock-pam skipped or failed (lock falls back to login PAM)" >&2
}

proteus_log "apps OK (user=${USER_NAME} SUDO_USER=${SUDO_USER:-})"
