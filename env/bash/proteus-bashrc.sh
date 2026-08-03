# shellcheck shell=bash
# Proteus interactive shell — fastfetch (P monogram) when a terminal opens
# Sourced from ~/.bashrc when present. Does not change Ghostty opacity/theme.

proteus_shell_fetch() {
  [[ $- == *i* ]] || return 0
  [[ -n "${PROTEUS_FETCH_DONE:-}" ]] && return 0
  export PROTEUS_FETCH_DONE=1

  # New Ghostty windows; skip pure SSH/TTY without a display
  if [[ "${TERM_PROGRAM:-}" == "ghostty" ]] || [[ -n "${GHOSTTY_RESOURCES_DIR:-}" ]]; then
    :
  elif [[ -z "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]]; then
    return 0
  fi

  if command -v fastfetch >/dev/null 2>&1; then
    local cfg="${HOME}/.config/fastfetch/config.jsonc"
    if [[ -f "${cfg}" ]]; then
      fastfetch --config "${cfg}"
    else
      fastfetch
    fi
  fi
}

proteus_shell_fetch
