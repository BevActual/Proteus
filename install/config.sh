#!/usr/bin/env bash
# config — seatd/pipewire user session hooks + ghostty/fastfetch seeds
set -euo pipefail
# shellcheck source=helpers.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

PROTEUS_ROOT="$(proteus_install_root)"
USER_NAME="$(proteus_session_user)"
USER_HOME="$(getent passwd "${USER_NAME}" | cut -d: -f6)"
[[ -n "${USER_HOME}" && -d "${USER_HOME}" ]] || {
  echo "config: no home for ${USER_NAME}" >&2
  exit 1
}

proteus_log "session user ${USER_NAME} (${USER_HOME})"

# Persist the install root so a greetd-launched session (clean env, no
# PROTEUS_ROOT inherited) can find the tree on bare metal. VM installs keep
# writing /mnt/proteus here — same Fact, no special case.
proteus_write_root_fact "${PROTEUS_ROOT}"

# Shipping compositor — smithay only (Hyprland purged).
proteus_as_user mkdir -p "${USER_HOME}/.config/proteus"
printf 'smithay\n' | proteus_as_user tee "${USER_HOME}/.config/proteus/compositor-engine" >/dev/null
proteus_log "compositor-engine=smithay (Hyprland purged — no Fact rollback)"

# Prefer installing compositor-next when the tree/binary is available.
if [[ -x "${PROTEUS_ROOT}/install/machine/install-proteus-compositor-next.sh" ]]; then
  bash "${PROTEUS_ROOT}/install/machine/install-proteus-compositor-next.sh" \
    || proteus_log "note: compositor-next install soft-failed (session will refuse without binary)"
fi

# Portal preference for smithay / wlroots sessions.
PORTAL_DIR="${USER_HOME}/.config/xdg-desktop-portal"
proteus_as_user mkdir -p "${PORTAL_DIR}"
if [[ -f "${PROTEUS_ROOT}/env/portal/portals.conf" ]]; then
  proteus_as_user cp -f "${PROTEUS_ROOT}/env/portal/portals.conf" "${PORTAL_DIR}/portals.conf"
elif [[ ! -f "${PORTAL_DIR}/portals.conf" ]]; then
  proteus_as_user tee "${PORTAL_DIR}/portals.conf" >/dev/null <<'EOF'
[preferred]
default=wlr;gtk;
EOF
fi

proteus_root systemctl enable seatd.service 2>/dev/null || true
# PipeWire usually user services after first graphical login; enable lingering helps
proteus_root loginctl enable-linger "${USER_NAME}" 2>/dev/null || true

# Drop retired Quickshell config symlink if present.
if [[ -L "${USER_HOME}/.config/quickshell/proteus" ]]; then
  proteus_as_user rm -f "${USER_HOME}/.config/quickshell/proteus"
fi

# env/hypr/ deleted (Hyprland purged) — no hyprland.conf seed.
proteus_log "note: env/hypr gone (Hyprland purged); Settings apply via proteus-settings-apply"

# Ghostty + fastfetch — terminal open look (seed once; never overwrite user edits)
seed_file() {
  local src="$1" dest="$2"
  [[ -f "${src}" ]] || return 0
  proteus_as_user mkdir -p "$(dirname "${dest}")"
  if [[ ! -f "${dest}" ]]; then
    proteus_as_user cp "${src}" "${dest}"
    proteus_log "seeded ${dest}"
  else
    proteus_log "keep existing ${dest}"
  fi
}
seed_file "${PROTEUS_ROOT}/env/ghostty/config" "${USER_HOME}/.config/ghostty/config"
seed_file "${PROTEUS_ROOT}/env/fastfetch/config.jsonc" "${USER_HOME}/.config/fastfetch/config.jsonc"
seed_file "${PROTEUS_ROOT}/env/fastfetch/proteus-helix.txt" "${USER_HOME}/.config/fastfetch/proteus-helix.txt"
seed_file "${PROTEUS_ROOT}/env/bash/proteus-bashrc.sh" "${USER_HOME}/.config/proteus/proteus-bashrc.sh"

BASHRC="${USER_HOME}/.bashrc"
MARKER="# Proteus terminal fetch"
if ! proteus_as_user grep -qF "${MARKER}" "${BASHRC}" 2>/dev/null; then
  {
    echo ""
    echo "${MARKER}"
    echo "[[ -f \"\${HOME}/.config/proteus/proteus-bashrc.sh\" ]] && source \"\${HOME}/.config/proteus/proteus-bashrc.sh\""
  } | proteus_as_user tee -a "${BASHRC}" >/dev/null
  proteus_log "appended Proteus bashrc hook"
fi

proteus_log "config OK"
