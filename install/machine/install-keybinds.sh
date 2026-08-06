#!/usr/bin/env bash
# install-keybinds.sh — seed ~/.config/proteus/keybinds.json (owned compositor binds).
# Hyprland proteus-keybinds.conf path retired (env/hypr deleted).
set -euo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)"
SRC="${ROOT}/env/settings/keybinds.defaults.json"
DEST_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/proteus"
DEST="${DEST_DIR}/keybinds.json"

if [[ ! -f "${SRC}" ]]; then
  echo "install-keybinds: SKIP (missing ${SRC})"
  exit 0
fi

mkdir -p "${DEST_DIR}"
if [[ ! -f "${DEST}" ]]; then
  install -m 644 "${SRC}" "${DEST}"
  echo "Installed default ${DEST}"
else
  echo "Keeping existing ${DEST}"
fi
echo "Keybinds Fact ready → ${DEST} (compositor defaults + optional overrides)"
