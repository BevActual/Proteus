#!/usr/bin/env bash
# config — seatd/pipewire user session hooks + QS symlink
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

proteus_root systemctl enable seatd.service 2>/dev/null || true
# PipeWire usually user services after first graphical login; enable lingering helps
proteus_root loginctl enable-linger "${USER_NAME}" 2>/dev/null || true

# Quickshell → Proteus shell (9p)
proteus_as_user mkdir -p "${USER_HOME}/.config/quickshell"
if [[ -L "${USER_HOME}/.config/quickshell/proteus" || ! -e "${USER_HOME}/.config/quickshell/proteus" ]]; then
  proteus_as_user ln -sfn "${PROTEUS_ROOT}/shell" "${USER_HOME}/.config/quickshell/proteus"
fi

# Hyprland config: prefer existing; else seed from env/ templates if guest has none
HYPR_DIR="${USER_HOME}/.config/hypr"
proteus_as_user mkdir -p "${HYPR_DIR}"
if [[ ! -f "${HYPR_DIR}/hyprland.conf" ]]; then
  if [[ -f "${PROTEUS_ROOT}/env/hypr/hyprland.conf" ]]; then
    proteus_log "seeding hyprland.conf from env/hypr/"
    # Nested template uses SHELL_DIR_PLACEHOLDER — guest wants /mnt/proteus/shell
    sed "s|SHELL_DIR_PLACEHOLDER|${PROTEUS_ROOT}/shell|g" \
      "${PROTEUS_ROOT}/env/hypr/hyprland.conf" \
      | proteus_as_user tee "${HYPR_DIR}/hyprland.conf" >/dev/null
  else
    proteus_log "note: no ${HYPR_DIR}/hyprland.conf — guest may already use a custom session"
  fi
fi

# Autostart quickshell if hypr doesn't already (append once)
if [[ -f "${HYPR_DIR}/hyprland.conf" ]] \
  && ! grep -q 'quickshell -p' "${HYPR_DIR}/hyprland.conf" 2>/dev/null; then
  proteus_log "appending quickshell exec-once"
  {
    echo ""
    echo "# Proteus shell (overlay installer)"
    echo "exec-once = qs_icon_theme=\${QS_ICON_THEME:-Papirus-Dark} quickshell -p ${PROTEUS_ROOT}/shell"
  } | proteus_as_user tee -a "${HYPR_DIR}/hyprland.conf" >/dev/null
fi

# Autostart hypridle (locks via session lock → Proteus lock screen)
if [[ -f "${HYPR_DIR}/hyprland.conf" ]] \
  && ! grep -q 'hypridle' "${HYPR_DIR}/hyprland.conf" 2>/dev/null; then
  {
    echo ""
    echo "exec-once = hypridle"
  } | proteus_as_user tee -a "${HYPR_DIR}/hyprland.conf" >/dev/null
fi
# Interim cliphist watchers
if [[ -f "${HYPR_DIR}/hyprland.conf" ]] \
  && ! grep -q 'cliphist store' "${HYPR_DIR}/hyprland.conf" 2>/dev/null; then
  {
    echo ""
    echo "# Interim clipboard history (shell/scripts/proteus-clipboard)"
    echo "exec-once = wl-paste --type text --watch cliphist store"
    echo "exec-once = wl-paste --type image --watch cliphist store"
  } | proteus_as_user tee -a "${HYPR_DIR}/hyprland.conf" >/dev/null
fi
if [[ ! -f "${HYPR_DIR}/hypridle.conf" ]]; then
  proteus_as_user tee "${HYPR_DIR}/hypridle.conf" >/dev/null <<'EOF'
# Proteus — idle → session lock (Quickshell lock screen)
general {
  lock_cmd = loginctl lock-session
  before_sleep_cmd = loginctl lock-session
}

listener {
  timeout = 300
  on-timeout = loginctl lock-session
}
EOF
fi

# Ensure proteus-hw.conf exists and is sourced (hardware stage fills it)
HW_CONF="${HYPR_DIR}/proteus-hw.conf"
if [[ ! -f "${HW_CONF}" ]]; then
  proteus_as_user tee "${HW_CONF}" >/dev/null <<'EOF'
# Populated by vm/install/hardware/*.sh (NVIDIA / AMD / Intel / virt)
EOF
fi
if [[ -f "${HYPR_DIR}/hyprland.conf" ]] \
  && ! grep -q 'proteus-hw.conf' "${HYPR_DIR}/hyprland.conf" 2>/dev/null; then
  {
    echo ""
    echo "# GPU / hardware envs (vm/install/hardware)"
    echo "source = ~/.config/hypr/proteus-hw.conf"
  } | proteus_as_user tee -a "${HYPR_DIR}/hyprland.conf" >/dev/null
fi

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
seed_file "${PROTEUS_ROOT}/env/shell/proteus-bashrc.sh" "${USER_HOME}/.config/proteus/proteus-bashrc.sh"
# Hypr fragments (apps stage also sources these; seed early so partial runs work)
seed_file "${PROTEUS_ROOT}/env/hypr/proteus-keybinds.conf" "${HYPR_DIR}/proteus-keybinds.conf"
seed_file "${PROTEUS_ROOT}/env/hypr/proteus-general.conf" "${HYPR_DIR}/proteus-general.conf"
seed_file "${PROTEUS_ROOT}/env/hypr/proteus-monitors.conf" "${HYPR_DIR}/proteus-monitors.conf"

# Ensure hypr sources for fragments seeded above (idempotent append)
ensure_hypr_source() {
  local needle="$1" comment="$2"
  [[ -f "${HYPR_DIR}/hyprland.conf" ]] || return 0
  if ! grep -q "${needle}" "${HYPR_DIR}/hyprland.conf" 2>/dev/null; then
    {
      echo ""
      echo "# ${comment}"
      echo "source = ~/.config/hypr/${needle}"
    } | proteus_as_user tee -a "${HYPR_DIR}/hyprland.conf" >/dev/null
    proteus_log "sourced ${needle}"
  fi
}
ensure_hypr_source "proteus-keybinds.conf" "Proteus keyboard shortcuts (Settings → Keyboard)"
ensure_hypr_source "proteus-monitors.conf" "Proteus displays (Settings → Displays)"
ensure_hypr_source "proteus-general.conf" "Proteus desktop (Settings → Desktop)"

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
