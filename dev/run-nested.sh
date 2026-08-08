#!/usr/bin/env bash
# Launch Proteus nested under an existing Wayland/X11 session via compositor
# (winit). Leaves your host session alone — close the nested window to exit.
#
# Chrome: owned iced only (`proteus-chrome` → `proteus-shell`).
# Hyprland / Quickshell purged — this path never execs them.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

need_build_shell=0
need_build_comp=0
[[ -x "${ROOT}/target/debug/proteus-shell" || -x "${ROOT}/target/release/proteus-shell" ]] \
  || command -v proteus-shell >/dev/null 2>&1 || need_build_shell=1
[[ -x "${ROOT}/target/debug/proteus-compositor" || -x "${ROOT}/target/release/proteus-compositor" ]] \
  || command -v proteus-compositor >/dev/null 2>&1 || need_build_comp=1

if [[ "${need_build_shell}" -eq 1 || "${need_build_comp}" -eq 1 ]]; then
  command -v cargo >/dev/null 2>&1 || {
    echo "run-nested: cargo not found and binaries missing" >&2
    exit 1
  }
  if [[ "${need_build_shell}" -eq 1 ]]; then
    echo "Building proteus-shell (owned chrome)…"
    (cd "${ROOT}" && cargo build -p proteus-shell -q) || {
      echo "run-nested: proteus-shell build failed" >&2
      exit 1
    }
  fi
  if [[ "${need_build_comp}" -eq 1 ]]; then
    echo "Building compositor…"
    (cd "${ROOT}" && cargo build -p compositor -q) || {
      echo "run-nested: compositor build failed" >&2
      exit 1
    }
  fi
fi

export PATH="${ROOT}/target/debug:${ROOT}/target/release:${ROOT}/shell/scripts:${PATH}"

COMP=""
for c in \
  "${ROOT}/target/debug/proteus-compositor" \
  "${ROOT}/target/release/proteus-compositor"
do
  if [[ -x "${c}" ]]; then
    COMP="${c}"
    break
  fi
done
if [[ -z "${COMP}" ]] && command -v proteus-compositor >/dev/null 2>&1; then
  COMP="$(command -v proteus-compositor)"
fi
[[ -n "${COMP}" && -x "${COMP}" ]] || {
  echo "proteus-compositor not found — cargo build -p compositor" >&2
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

# Ghostty + fastfetch seeds for nested dogfood (opt-in bashrc: PROTEUS_NESTED_BASHRC=1)
mkdir -p "${HOME}/.config/ghostty" "${HOME}/.config/fastfetch" "${HOME}/.config/proteus"
[[ -f "${HOME}/.config/ghostty/config" ]] || install -m 644 "${ROOT}/env/ghostty/config" "${HOME}/.config/ghostty/config"
[[ -f "${HOME}/.config/fastfetch/config.jsonc" ]] || install -m 644 "${ROOT}/env/fastfetch/config.jsonc" "${HOME}/.config/fastfetch/config.jsonc"
[[ -f "${HOME}/.config/fastfetch/proteus-helix.txt" ]] || install -m 644 "${ROOT}/env/fastfetch/proteus-helix.txt" "${HOME}/.config/fastfetch/proteus-helix.txt"
[[ -f "${HOME}/.config/proteus/proteus-bashrc.sh" ]] || install -m 644 "${ROOT}/env/bash/proteus-bashrc.sh" "${HOME}/.config/proteus/proteus-bashrc.sh"
if [[ "${PROTEUS_NESTED_BASHRC:-0}" == "1" ]] \
  && [[ -f "${HOME}/.bashrc" ]] \
  && ! grep -qF "# Proteus terminal fetch" "${HOME}/.bashrc" 2>/dev/null; then
  {
    echo ""
    echo "# Proteus terminal fetch"
    echo "[[ -f \"\${HOME}/.config/proteus/proteus-bashrc.sh\" ]] && source \"\${HOME}/.config/proteus/proteus-bashrc.sh\""
  } >> "${HOME}/.bashrc"
  echo "run-nested: appended Proteus fetch hook to ~/.bashrc (PROTEUS_NESTED_BASHRC=1)"
fi

export PROTEUS_ROOT="${ROOT}"
export PROTEUS_SURFACE="${PROTEUS_SURFACE:-desktop}"
export PROTEUS_SHELL_ENGINE="${PROTEUS_SHELL_ENGINE:-owned}"
export PROTEUS_COMPOSITOR_ENGINE=smithay
export XDG_CURRENT_DESKTOP=wlroots

echo "Starting nested Proteus (compositor winit)…"
echo "  compositor: ${COMP}"
echo "  chrome:     ${CHROME}"
echo "  engine:     ${PROTEUS_SHELL_ENGINE}"
echo "  Exit: close the nested compositor window"

# Host display stays set so winit can nest; compositor clears nested seat for clients.
exec "${COMP}" --backend winit -c "${CHROME}"
