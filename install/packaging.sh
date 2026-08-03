#!/usr/bin/env bash
# packaging — light pacman set from proteus-base.packages
set -euo pipefail
# shellcheck source=helpers.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

PROTEUS_ROOT="$(proteus_install_root)"
LIST="${PROTEUS_ROOT}/install/proteus-base.packages"

if ! command -v pacman >/dev/null 2>&1; then
  echo "packaging: pacman not found (run on Arch guest)" >&2
  exit 1
fi

proteus_pacman_from_list "${LIST}"
# Optional verify tool for lock PAM (non-fatal)
proteus_root pacman -S --noconfirm --needed pamtester 2>/dev/null || true

# Session services the base list expects (idempotent)
for unit in NetworkManager.service bluetooth.service power-profiles-daemon.service; do
  if proteus_root systemctl enable "${unit}" 2>/dev/null; then
    proteus_log "enabled ${unit}"
  fi
done

proteus_log "packaging OK"
