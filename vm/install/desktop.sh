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
proteus_pacman_from_list "${LIST}"

if command -v xdg-settings >/dev/null 2>&1; then
  proteus_as_user xdg-settings set default-web-browser chromium.desktop 2>/dev/null || true
fi

proteus_log "desktop OK"
