#!/usr/bin/env bash
# Launch Proteus inside a nested Hyprland window.
# Leaves your Omarchy session alone — close the nested window / Super+Shift+E to exit.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_DIR="${ROOT}/shell"
CONF_SRC="${ROOT}/env/hyprland.conf"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}/proteus-nested"
CONF_OUT="${RUNTIME_DIR}/hyprland.conf"

if ! command -v Hyprland >/dev/null 2>&1; then
  echo "Hyprland not found" >&2
  exit 1
fi

if ! command -v quickshell >/dev/null 2>&1; then
  echo "quickshell not found. Install it before nesting: https://quickshell.org/" >&2
  exit 1
fi

mkdir -p "${RUNTIME_DIR}"
sed "s|SHELL_DIR_PLACEHOLDER|${SHELL_DIR}|g" "${CONF_SRC}" > "${CONF_OUT}"

# Seed Hyprland fragments Settings owns
mkdir -p "${HOME}/.config/hypr"
if [[ ! -f "${HOME}/.config/hypr/proteus-keybinds.conf" ]]; then
  install -m 644 "${ROOT}/env/proteus-keybinds.conf" "${HOME}/.config/hypr/proteus-keybinds.conf"
fi
if [[ ! -f "${HOME}/.config/hypr/proteus-general.conf" ]]; then
  install -m 644 "${ROOT}/env/proteus-general.conf" "${HOME}/.config/hypr/proteus-general.conf"
fi
if [[ ! -f "${HOME}/.config/hypr/proteus-monitors.conf" ]]; then
  install -m 644 "${ROOT}/env/proteus-monitors.conf" "${HOME}/.config/hypr/proteus-monitors.conf"
fi

export PROTEUS_SURFACE="${PROTEUS_SURFACE:-desktop}"

echo "Starting nested Proteus Hyprland…"
echo "  config: ${CONF_OUT}"
echo "  shell:  ${SHELL_DIR}"
echo "  Exit nested session: Super+Shift+E (or close the window)"

# Nested: run Hyprland from an existing Wayland session with its own config.
exec Hyprland -c "${CONF_OUT}"
