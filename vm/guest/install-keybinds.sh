#!/usr/bin/env bash
# Ensure Hyprland sources Proteus keybinds (Settings → Keyboard).
# Safe to run repeatedly on the guest or nested host.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC="${ROOT}/env/hypr/proteus-keybinds.conf"
HYPR_DIR="${HOME}/.config/hypr"
HYPR="${HYPR_DIR}/hyprland.conf"
DEST="${HYPR_DIR}/proteus-keybinds.conf"

mkdir -p "${HYPR_DIR}"

if [[ ! -f "${DEST}" ]]; then
  install -m 644 "${SRC}" "${DEST}"
  echo "Installed default ${DEST}"
else
  echo "Keeping existing ${DEST}"
fi

if [[ -f "${HYPR}" ]]; then
  if ! grep -q 'proteus-keybinds.conf' "${HYPR}"; then
    printf '\n# Proteus keyboard shortcuts (Settings → Keyboard)\nsource = ~/.config/hypr/proteus-keybinds.conf\n' >> "${HYPR}"
    echo "Added source line to ${HYPR}"
  fi
  # Comment out legacy inline binds that duplicate the catalog (first-time migration)
  if grep -qE '^bind = SUPER, Return,' "${HYPR}" 2>/dev/null; then
    tmp="$(mktemp)"
    awk '
      /^bind = SUPER, Return,/ { print "# migrated to proteus-keybinds.conf: " $0; next }
      /^bind = SUPER, Q,/ { print "# migrated to proteus-keybinds.conf: " $0; next }
      /^bind = SUPER SHIFT, E,/ { print "# migrated to proteus-keybinds.conf: " $0; next }
      /^bind = SUPER, F,/ { print "# migrated to proteus-keybinds.conf: " $0; next }
      /^bind = SUPER, SPACE,/ { print "# migrated to proteus-keybinds.conf: " $0; next }
      /^bind = SUPER, D,/ { print "# migrated to proteus-keybinds.conf: " $0; next }
      /^bind = SUPER, [1-6],/ { print "# migrated to proteus-keybinds.conf: " $0; next }
      /^bind = SUPER SHIFT, [1-6],/ { print "# migrated to proteus-keybinds.conf: " $0; next }
      /^bind = SUPER, comma,/ { print "# migrated to proteus-keybinds.conf: " $0; next }
      { print }
    ' "${HYPR}" > "${tmp}"
    mv "${tmp}" "${HYPR}"
    echo "Commented legacy duplicate binds in ${HYPR}"
  fi
else
  echo "No ${HYPR} yet — source will be added when Settings applies binds"
fi

if command -v hyprctl >/dev/null 2>&1; then
  hyprctl reload >/dev/null 2>&1 || true
fi

echo "Keybinds ready → ${DEST}"
