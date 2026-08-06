#!/usr/bin/env bash
# Launch Proteus nested under an existing Wayland/X11 session via compositor-next
# (winit). Leaves your host session alone — close the nested window to exit.
#
# Wave 4: chrome defaults to owned iced (`proteus-chrome` → `proteus-shell`).
# Override: PROTEUS_SHELL_ENGINE=quickshell ./dev/run-nested.sh
# Hyprland purged — this path never execs Hyprland.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Ensure owned shell + compositor binaries exist.
if [[ ! -x "${ROOT}/target/debug/proteus-shell" && ! -x "${ROOT}/target/release/proteus-shell" ]] \
  && ! command -v proteus-shell >/dev/null 2>&1; then
  if command -v cargo >/dev/null 2>&1; then
    echo "Building proteus-shell (owned chrome)…"
    (cd "${ROOT}" && cargo build -p proteus-shell -q) || true
  fi
fi
if [[ ! -x "${ROOT}/target/debug/proteus-compositor-next" && ! -x "${ROOT}/target/release/proteus-compositor-next" ]] \
  && ! command -v proteus-compositor-next >/dev/null 2>&1; then
  if command -v cargo >/dev/null 2>&1; then
    echo "Building compositor-next…"
    (cd "${ROOT}" && cargo build -p compositor-next -q) || true
  fi
fi

export PATH="${ROOT}/target/debug:${ROOT}/target/release:${ROOT}/shell/scripts:${PATH}"

COMP=""
for c in \
  "${ROOT}/target/debug/proteus-compositor-next" \
  "${ROOT}/target/release/proteus-compositor-next"
do
  if [[ -x "${c}" ]]; then
    COMP="${c}"
    break
  fi
done
if [[ -z "${COMP}" ]] && command -v proteus-compositor-next >/dev/null 2>&1; then
  COMP="$(command -v proteus-compositor-next)"
fi
[[ -n "${COMP}" && -x "${COMP}" ]] || {
  echo "proteus-compositor-next not found — cargo build -p compositor-next" >&2
  exit 1
}

CHROME=""
if command -v proteus-chrome >/dev/null 2>&1; then
  CHROME="$(command -v proteus-chrome)"
elif [[ -x "${ROOT}/shell/scripts/proteus-chrome" ]]; then
  CHROME="${ROOT}/shell/scripts/proteus-chrome"
fi
[[ -n "${CHROME}" ]] || {
  echo "proteus-chrome not found" >&2
  exit 1
}

# Ghostty + fastfetch (DNA helix) for nested dogfood
mkdir -p "${HOME}/.config/ghostty" "${HOME}/.config/fastfetch" "${HOME}/.config/proteus"
[[ -f "${HOME}/.config/ghostty/config" ]] || install -m 644 "${ROOT}/env/ghostty/config" "${HOME}/.config/ghostty/config"
[[ -f "${HOME}/.config/fastfetch/config.jsonc" ]] || install -m 644 "${ROOT}/env/fastfetch/config.jsonc" "${HOME}/.config/fastfetch/config.jsonc"
[[ -f "${HOME}/.config/fastfetch/proteus-helix.txt" ]] || install -m 644 "${ROOT}/env/fastfetch/proteus-helix.txt" "${HOME}/.config/fastfetch/proteus-helix.txt"
[[ -f "${HOME}/.config/proteus/proteus-bashrc.sh" ]] || install -m 644 "${ROOT}/env/bash/proteus-bashrc.sh" "${HOME}/.config/proteus/proteus-bashrc.sh"
if [[ -f "${HOME}/.bashrc" ]] && ! grep -qF "# Proteus terminal fetch" "${HOME}/.bashrc" 2>/dev/null; then
  {
    echo ""
    echo "# Proteus terminal fetch"
    echo "[[ -f \"\${HOME}/.config/proteus/proteus-bashrc.sh\" ]] && source \"\${HOME}/.config/proteus/proteus-bashrc.sh\""
  } >> "${HOME}/.bashrc"
fi

export PROTEUS_ROOT="${ROOT}"
export PROTEUS_SURFACE="${PROTEUS_SURFACE:-desktop}"
export PROTEUS_SHELL_ENGINE="${PROTEUS_SHELL_ENGINE:-owned}"
export PROTEUS_COMPOSITOR_ENGINE=smithay
export XDG_CURRENT_DESKTOP=wlroots

echo "Starting nested Proteus (compositor-next winit)…"
echo "  compositor: ${COMP}"
echo "  chrome:     ${CHROME}"
echo "  engine:     ${PROTEUS_SHELL_ENGINE}"
echo "  Exit: close the nested compositor window"

# Host display stays set so winit can nest; compositor clears nested seat for clients.
exec "${COMP}" --backend winit -c "${CHROME}"
