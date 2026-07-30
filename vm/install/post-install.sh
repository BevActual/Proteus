#!/usr/bin/env bash
# post-install — status + next steps
set -euo pipefail
# shellcheck source=helpers.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

USER_NAME="$(proteus_session_user)"
proteus_status_ensure
STATUS="$(proteus_status_dir)"

# Refresh launcher NoDisplay stubs (Settings-covered tools + Quickshell)
if [[ -n "${PROTEUS_ROOT:-}" && -f "${PROTEUS_ROOT}/vm/guest/hide-system-apps.sh" ]]; then
  proteus_root bash "${PROTEUS_ROOT}/vm/guest/hide-system-apps.sh" \
    || proteus_log "note: hide-system-apps failed (non-fatal)"
fi

proteus_log "overlay complete for user ${USER_NAME}"
{
  echo "user=${USER_NAME}"
  echo "finished=$(date -Iseconds 2>/dev/null || date)"
  echo "root=${PROTEUS_ROOT:-}"
  echo "desktop=${PROTEUS_INSTALL_DESKTOP:-1}"
} >"${STATUS}/complete"

# Soft verify: base packages present when pacman exists
if command -v pacman >/dev/null 2>&1 && [[ -n "${PROTEUS_ROOT:-}" ]]; then
  if proteus_pkgs_installed "${PROTEUS_ROOT}/vm/install/proteus-base.packages"; then
    proteus_log "verify: base packages installed"
  else
    proteus_log "verify: some base packages missing (re-run packaging)"
  fi
fi

cat <<EOF

Next:
  1. Reboot the guest (or: sudo systemctl restart greetd)
  2. Unlock the Proteus lock screen with the user password
  3. On the host, snapshot when healthy:
       ./vm/run.sh snapshot hyprland-base

Dogfood:
  ssh -p 2222 ${USER_NAME}@127.0.0.1
  PROTEUS_GUEST=1 ./scripts/smoke-all.sh

Status: ${STATUS}/complete
Log:    ${PROTEUS_INSTALL_LOG:-}

Re-run overlay (idempotent pacman --needed):
  sudo bash /mnt/proteus/vm/install/bootstrap.sh
Resume after interrupt:
  sudo PROTEUS_INSTALL_RESUME=1 bash /mnt/proteus/vm/install/bootstrap.sh
Single stage:
  sudo PROTEUS_INSTALL_ONLY=desktop bash /mnt/proteus/vm/install/bootstrap.sh

EOF
