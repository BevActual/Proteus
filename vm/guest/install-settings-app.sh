#!/usr/bin/env bash
# Install Proteus Settings as a system application on the guest.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP="${ROOT}/apps/proteus-settings"

install -d /usr/local/bin
install -m 755 "${APP}/proteus-settings" /usr/local/bin/proteus-settings
# Rewrite launcher to absolute share path when installed from 9p (optional override)
cat > /usr/local/bin/proteus-settings << EOF
#!/usr/bin/env bash
set -euo pipefail
export QS_ICON_THEME="\${QS_ICON_THEME:-Papirus-Dark}"
exec quickshell -p "${APP}"
EOF
chmod 755 /usr/local/bin/proteus-settings

# Animated background runner (Quickshell layer-shell)
cat > /usr/local/bin/proteus-bg << EOF
#!/usr/bin/env bash
set -euo pipefail
export PROTEUS_ROOT="${ROOT}"
export QS_ICON_THEME="\${QS_ICON_THEME:-Papirus-Dark}"
export QT_QPA_PLATFORM="\${QT_QPA_PLATFORM:-wayland}"
exec quickshell -p "${ROOT}/shell/wallpaper"
EOF
chmod 755 /usr/local/bin/proteus-bg

install -d /usr/share/applications
install -m 644 "${APP}/proteus-settings.desktop" /usr/share/applications/proteus-settings.desktop

echo "Installed proteus-settings → /usr/local/bin/proteus-settings"
echo "Installed proteus-bg → /usr/local/bin/proteus-bg"

# Wallpaper video needs Qt Multimedia (Quickshell / proteus-bg)
if command -v pacman >/dev/null 2>&1; then
  pacman -S --noconfirm --needed qt6-multimedia >/dev/null 2>&1 \
    && echo "Installed qt6-multimedia (video backgrounds)" \
    || echo "note: install qt6-multimedia for Appearance → Background → Video"
fi

# Seed per-user backgrounds folder (stock images)
seed_backgrounds() {
  local home="$1"
  local dest="${home}/.local/share/proteus/backgrounds"
  mkdir -p "${dest}"
  local assets="${ROOT}/shell/assets"
  if [[ -d "${assets}" ]]; then
    shopt -s nullglob
    for f in "${assets}"/wallpaper*.jpg "${assets}"/wallpaper*.png; do
      local base
      base="$(basename "$f")"
      if [[ ! -e "${dest}/${base}" ]]; then
        cp -n "$f" "${dest}/${base}" 2>/dev/null || true
      fi
    done
    shopt -u nullglob
  fi
  echo "Seeded backgrounds → ${dest}"
}

# Privileged package mutator (polkit) — skip if binary missing and no cargo
if [[ -x "${ROOT}/services/proteus-pkg/target/release/proteus-pkg" ]] || command -v cargo >/dev/null 2>&1; then
  bash "${ROOT}/vm/guest/install-proteus-pkg.sh"
else
  echo "note: skipped proteus-pkg (build release on host first)"
fi

# Keybinds must land in the session user's home (not root when using sudo)
if [[ "${SUDO_USER:-}" != "" && "${SUDO_USER}" != "root" ]]; then
  sudo -u "${SUDO_USER}" bash "${ROOT}/vm/guest/install-keybinds.sh"
  sudo -u "${SUDO_USER}" bash "${ROOT}/vm/guest/install-desktop-conf.sh"
  seed_backgrounds "$(getent passwd "${SUDO_USER}" | cut -d: -f6)"
else
  bash "${ROOT}/vm/guest/install-keybinds.sh"
  bash "${ROOT}/vm/guest/install-desktop-conf.sh"
  if [[ "${HOME:-}" != "" && "${HOME}" != "/root" ]]; then
    seed_backgrounds "${HOME}"
  elif [[ -d /home/andrew ]]; then
    seed_backgrounds /home/andrew
  fi
fi
