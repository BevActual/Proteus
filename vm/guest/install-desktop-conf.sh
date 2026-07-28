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

seed "${ROOT}/env/hypr/proteus-general.conf" "${HYPR_DIR}/proteus-general.conf"
seed "${ROOT}/env/hypr/proteus-monitors.conf" "${HYPR_DIR}/proteus-monitors.conf"

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

  # Migrate legacy swaybg → unified proteus-bg wallpaper runtime.
  # Prefer an absolute path — Hyprland's exec-once PATH often lacks ~/.local/bin.
  bg_cmd="proteus-bg"
  if [[ -x /usr/local/bin/proteus-bg ]]; then
    bg_cmd="/usr/local/bin/proteus-bg"
  elif [[ -x "${HOME}/.local/bin/proteus-bg" ]]; then
    bg_cmd="${HOME}/.local/bin/proteus-bg"
  elif [[ -x /mnt/proteus/vm/guest/proteus-bg ]]; then
    bg_cmd="/mnt/proteus/vm/guest/proteus-bg"
  fi
  if grep -qE '^[[:space:]]*exec-once[[:space:]]*=[[:space:]]*swaybg' "${HYPR}"; then
    sed -i -E "s|^[[:space:]]*exec-once[[:space:]]*=[[:space:]]*swaybg.*|exec-once = ${bg_cmd}|" "${HYPR}"
    echo "Migrated swaybg → ${bg_cmd} in ${HYPR}"
  elif grep -qE '^[[:space:]]*exec-once[[:space:]]*=[[:space:]]*.*proteus-bg' "${HYPR}"; then
    sed -i -E "s|^[[:space:]]*exec-once[[:space:]]*=[[:space:]]*.*proteus-bg.*|exec-once = ${bg_cmd}|" "${HYPR}"
    echo "Updated proteus-bg exec-once → ${bg_cmd}"
  else
    printf '\n# Proteus wallpaper (Settings → Appearance → Background)\nexec-once = %s\n' "${bg_cmd}" >> "${HYPR}"
    echo "Added exec-once = ${bg_cmd} to ${HYPR}"
  fi
else
  echo "No ${HYPR} yet — Settings will add source lines on apply"
fi

# Session lock PAM for Quickshell LockSurface (optional /etc copy)
PAM_SRC="${ROOT}/shell/pam/proteus-lock"
if [[ -f "${PAM_SRC}" ]]; then
  if [[ "$(id -u)" -eq 0 ]]; then
    install -m 644 "${PAM_SRC}" /etc/pam.d/proteus-lock
    echo "Installed /etc/pam.d/proteus-lock"
  else
    echo "Lock PAM: ${PAM_SRC} (auth helper uses login service). Optional: sudo install -m 644 ${PAM_SRC} /etc/pam.d/proteus-lock"
  fi
fi

# Lock auth uses shell/scripts/check-password.py (ctypes → libpam; no extra pkgs)

# Keybinds: replace if missing, corrupt (NULs), or missing required binds
KB="${HOME}/.config/hypr/proteus-keybinds.conf"
KB_TMPL="${ROOT}/env/hypr/proteus-keybinds.conf"
kb_corrupt=0
if [[ -f "${KB}" ]] && grep -q $'\0' "${KB}" 2>/dev/null; then
  kb_corrupt=1
fi
if [[ ! -f "${KB}" ]] || [[ "${kb_corrupt}" -eq 1 ]]; then
  install -m 644 "${KB_TMPL}" "${KB}"
  echo "Installed clean ${KB}$([[ "${kb_corrupt}" -eq 1 ]] && echo ' (replaced NUL-corrupt file)')"
else
  if ! grep -qE 'proteus:lock' "${KB}"; then
    printf '\n# Session\nbind = SUPER, L, global, proteus:lock\n' >> "${KB}"
    echo "Added Super+L lock to ${KB}"
  fi
  if ! grep -qE 'proteus:customize-desktop' "${KB}"; then
    printf '\nbind = SUPER SHIFT, W, global, proteus:customize-desktop\n' >> "${KB}"
    echo "Added Super+Shift+W desktop customize to ${KB}"
  fi
fi

if command -v hyprctl >/dev/null 2>&1; then
  hyprctl reload >/dev/null 2>&1 || true
fi

echo "Desktop/Displays hypr fragments ready"
