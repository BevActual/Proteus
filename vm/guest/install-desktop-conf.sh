#!/usr/bin/env bash
# Seed proteus-general.conf + proteus-monitors.conf and source them from hyprland.conf.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HYPR_DIR="${HOME}/.config/hypr"
HYPR="${HYPR_DIR}/hyprland.conf"

mkdir -p "${HYPR_DIR}"

seed() {
  local src="$1" dest="$2"
  if [[ ! -f "${dest}" ]]; then
    install -m 644 "${src}" "${dest}"
    echo "Installed default ${dest}"
  else
    echo "Keeping existing ${dest}"
  fi
}

seed "${ROOT}/env/proteus-general.conf" "${HYPR_DIR}/proteus-general.conf"
seed "${ROOT}/env/proteus-monitors.conf" "${HYPR_DIR}/proteus-monitors.conf"

ensure_source() {
  local needle="$1" comment="$2"
  if [[ -f "${HYPR}" ]] && ! grep -q "${needle}" "${HYPR}"; then
    printf '\n# %s\nsource = ~/.config/hypr/%s\n' "${comment}" "${needle}" >> "${HYPR}"
    echo "Added source ${needle} to ${HYPR}"
  fi
}

if [[ -f "${HYPR}" ]]; then
  ensure_source "proteus-monitors.conf" "Proteus displays (Settings → Displays)"
  ensure_source "proteus-general.conf" "Proteus desktop (Settings → Desktop)"
else
  echo "No ${HYPR} yet — Settings will add source lines on apply"
fi

if command -v hyprctl >/dev/null 2>&1; then
  hyprctl reload >/dev/null 2>&1 || true
fi

echo "Desktop/Displays hypr fragments ready"
