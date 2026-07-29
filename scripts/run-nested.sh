#!/usr/bin/env bash
# Launch Proteus inside a nested Hyprland window.
# Leaves your Omarchy session alone — close the nested window / Super+Shift+E to exit.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_DIR="${ROOT}/shell"
CONF_SRC="${ROOT}/env/hypr/hyprland.conf"
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
  install -m 644 "${ROOT}/env/hypr/proteus-keybinds.conf" "${HOME}/.config/hypr/proteus-keybinds.conf"
fi
if [[ ! -f "${HOME}/.config/hypr/proteus-general.conf" ]]; then
  install -m 644 "${ROOT}/env/hypr/proteus-general.conf" "${HOME}/.config/hypr/proteus-general.conf"
fi
if [[ ! -f "${HOME}/.config/hypr/proteus-monitors.conf" ]]; then
  install -m 644 "${ROOT}/env/hypr/proteus-monitors.conf" "${HOME}/.config/hypr/proteus-monitors.conf"
fi
mkdir -p "${HOME}/.config/hypr/profiles"
if [[ ! -f "${HOME}/.config/hypr/profiles/desktop.conf" ]]; then
  install -m 644 "${ROOT}/env/hypr/profiles/desktop.conf" "${HOME}/.config/hypr/profiles/desktop.conf"
fi
if [[ ! -f "${HOME}/.config/hypr/profiles/media.conf" ]]; then
  install -m 644 "${ROOT}/env/hypr/profiles/media.conf" "${HOME}/.config/hypr/profiles/media.conf"
fi
if [[ ! -f "${HOME}/.config/hypr/proteus-profile.conf" ]]; then
  install -m 644 "${ROOT}/env/hypr/proteus-profile.conf" "${HOME}/.config/hypr/proteus-profile.conf"
fi

# Ghostty + fastfetch (DNA helix) for nested dogfood
mkdir -p "${HOME}/.config/ghostty" "${HOME}/.config/fastfetch" "${HOME}/.config/proteus"
[[ -f "${HOME}/.config/ghostty/config" ]] || install -m 644 "${ROOT}/env/ghostty/config" "${HOME}/.config/ghostty/config"
[[ -f "${HOME}/.config/fastfetch/config.jsonc" ]] || install -m 644 "${ROOT}/env/fastfetch/config.jsonc" "${HOME}/.config/fastfetch/config.jsonc"
[[ -f "${HOME}/.config/fastfetch/proteus-helix.txt" ]] || install -m 644 "${ROOT}/env/fastfetch/proteus-helix.txt" "${HOME}/.config/fastfetch/proteus-helix.txt"
[[ -f "${HOME}/.config/proteus/proteus-bashrc.sh" ]] || install -m 644 "${ROOT}/env/shell/proteus-bashrc.sh" "${HOME}/.config/proteus/proteus-bashrc.sh"
if [[ -f "${HOME}/.bashrc" ]] && ! grep -qF "# Proteus terminal fetch" "${HOME}/.bashrc" 2>/dev/null; then
  {
    echo ""
    echo "# Proteus terminal fetch"
    echo "[[ -f \"\${HOME}/.config/proteus/proteus-bashrc.sh\" ]] && source \"\${HOME}/.config/proteus/proteus-bashrc.sh\""
  } >> "${HOME}/.bashrc"
fi

export PROTEUS_SURFACE="${PROTEUS_SURFACE:-desktop}"
export PATH="${ROOT}/shell/scripts:${PATH}"

echo "Starting nested Proteus Hyprland…"
echo "  config: ${CONF_OUT}"
echo "  shell:  ${SHELL_DIR}"
echo "  Exit nested session: Super+Shift+E (or close the window)"

# Nested: run Hyprland from an existing Wayland session with its own config.
exec Hyprland -c "${CONF_OUT}"
