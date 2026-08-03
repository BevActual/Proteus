#!/usr/bin/env bash
# Install Proteus Settings as a system application on the guest.
set -euo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)"
APP="${ROOT}/apps/proteus-settings"

# Brand marks into icon theme (proteus / proteus-settings)
bash "${ROOT}/install/machine/install-icons.sh"
# Hide pavucontrol / blueman / nm-editor from Beacon (Calculator stays)
bash "${ROOT}/install/machine/hide-system-apps.sh"

install -d /usr/local/bin
# Launcher uses the live app tree on 9p; single-instance via nav IPC + raise.
cat > /usr/local/bin/proteus-settings << EOF
#!/usr/bin/env bash
set -euo pipefail
DIR="${APP}"
export QS_ICON_THEME="\${QS_ICON_THEME:-Papirus-Dark}"

for arg in "\$@"; do
  case "\$arg" in
    --page=*) export PROTEUS_SETTINGS_PAGE="\${arg#--page=}" ;;
    --query=*) export PROTEUS_SETTINGS_QUERY="\${arg#--query=}" ;;
  esac
done

ipc() {
  if command -v qs >/dev/null 2>&1; then
    qs -p "\${DIR}" ipc call "\$@"
  else
    quickshell -p "\${DIR}" ipc call "\$@"
  fi
}

# Reuse a live instance — navigate/raise instead of spawning another Quickshell.
if ipc nav state >/dev/null 2>&1; then
  page="\${PROTEUS_SETTINGS_PAGE:-}"
  query="\${PROTEUS_SETTINGS_QUERY:-}"
  if [[ -n "\${query}" ]]; then
    leaf="\${page:-packages-search}"
    ipc nav installSearch "\${query}" "\${leaf}" >/dev/null 2>&1 || true
  elif [[ -n "\${page}" ]]; then
    ipc nav go "\${page}" >/dev/null 2>&1 || true
  fi
  ipc nav raise >/dev/null 2>&1 || true
  exit 0
fi

exec quickshell -n -p "\${DIR}"
EOF
chmod 755 /usr/local/bin/proteus-settings

# Animated background runner (Quickshell layer-shell)
# comm = proteus-bg (script name) so pgrep -x / Settings apply can detect it.
# Respawn loop: background changes can crash the Quickshell wallpaper process;
# without the guard the compositor splash stays until reboot. Clean exits and
# operator signals (TERM/INT/KILL) stop the loop so Settings' pkill works.
cat > /usr/local/bin/proteus-bg << EOF
#!/usr/bin/env bash
set -uo pipefail
export PROTEUS_ROOT="${ROOT}"
export QS_ICON_THEME="\${QS_ICON_THEME:-Papirus-Dark}"
export QT_QPA_PLATFORM="\${QT_QPA_PLATFORM:-wayland}"

child=""
trap '[[ -n "\${child}" ]] && kill "\${child}" 2>/dev/null; exit 143' TERM INT
while :; do
  quickshell -p "${ROOT}/shell/wallpaper" &
  child=\$!
  wait "\${child}"
  ec=\$?
  case "\${ec}" in
    0 | 129 | 130 | 137 | 143) exit "\${ec}" ;;
  esac
  echo "proteus-bg: quickshell exited \${ec} — respawning" >&2
  sleep 1
done
EOF
chmod 755 /usr/local/bin/proteus-bg

install -d /usr/share/applications
# Rewrite desktop Icon= to proteus-settings after install-icons
install -m 644 "${APP}/proteus-settings.desktop" /usr/share/applications/proteus-settings.desktop
if grep -q '^Icon=' /usr/share/applications/proteus-settings.desktop; then
  sed -i 's/^Icon=.*/Icon=proteus-settings/' /usr/share/applications/proteus-settings.desktop
fi

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
if [[ -x "${ROOT}/services/proteus-pkg/bin/proteus-pkg" ]] \
  || [[ -x "${ROOT}/services/proteus-pkg/target/release/proteus-pkg" ]] \
  || command -v cargo >/dev/null 2>&1; then
  bash "${ROOT}/install/machine/install-proteus-pkg.sh"
else
  echo "note: skipped proteus-pkg (build release on host first)"
fi

# Privileged logind writer (polkit) — Settings → Power
if [[ -x "${ROOT}/services/proteus-logind/bin/proteus-logind" ]] \
  || [[ -x "${ROOT}/services/proteus-logind/target/release/proteus-logind" ]] \
  || command -v cargo >/dev/null 2>&1; then
  bash "${ROOT}/install/machine/install-proteus-logind.sh"
else
  echo "note: skipped proteus-logind (build release on host first)"
fi

# Privileged battery charge thresholds (polkit) — Settings → Power
if [[ -x "${ROOT}/services/proteus-battery-threshold/bin/proteus-battery-threshold" ]] \
  || [[ -x "${ROOT}/services/proteus-battery-threshold/target/release/proteus-battery-threshold" ]] \
  || command -v cargo >/dev/null 2>&1; then
  bash "${ROOT}/install/machine/install-proteus-battery-threshold.sh"
else
  echo "note: skipped proteus-battery-threshold (build release on host first)"
fi

# Privileged greetd autologin writer (polkit) — Settings → Users
if [[ -x "${ROOT}/services/proteus-greetd/bin/proteus-greetd" ]] \
  || [[ -x "${ROOT}/services/proteus-greetd/target/release/proteus-greetd" ]] \
  || command -v cargo >/dev/null 2>&1; then
  bash "${ROOT}/install/machine/install-proteus-greetd.sh"
else
  echo "note: skipped proteus-greetd (build release on host first)"
fi

# Online accounts seats (user-scoped; no polkit)
if [[ -x "${ROOT}/services/proteus-accounts/bin/proteus-accounts" ]] \
  || [[ -x "${ROOT}/services/proteus-accounts/target/release/proteus-accounts" ]] \
  || command -v cargo >/dev/null 2>&1; then
  bash "${ROOT}/install/machine/install-proteus-accounts.sh"
else
  echo "note: skipped proteus-accounts (build release on host first)"
fi

# Resident mixer dump+peaks — Settings → Sound Mixer / Apps
if [[ -x "${ROOT}/services/proteus-audio-mix/bin/proteus-audio-mix" ]] \
  || [[ -x "${ROOT}/services/proteus-audio-mix/target/release/proteus-audio-mix" ]] \
  || command -v cargo >/dev/null 2>&1; then
  bash "${ROOT}/install/machine/install-proteus-audio-mix.sh"
else
  echo "note: skipped proteus-audio-mix (build release on host first)"
fi

# Flathub user remote (Settings → Software → Flathub)
ensure_flathub_for() {
  local user="$1"
  if [[ -z "${user}" || "${user}" == "root" ]]; then
    return 0
  fi
  if ! command -v flatpak >/dev/null 2>&1; then
    echo "note: skipped ensure-flathub (flatpak not installed)"
    return 0
  fi
  sudo -u "${user}" bash "${ROOT}/install/machine/ensure-flathub.sh" \
    || echo "note: ensure-flathub failed for ${user}"
}

# Keybinds must land in the session user's home (not root when using sudo)
if [[ "${SUDO_USER:-}" != "" && "${SUDO_USER}" != "root" ]]; then
  sudo -u "${SUDO_USER}" bash "${ROOT}/install/machine/install-keybinds.sh"
  sudo -u "${SUDO_USER}" bash "${ROOT}/install/machine/install-desktop-conf.sh"
  seed_backgrounds "$(getent passwd "${SUDO_USER}" | cut -d: -f6)"
  ensure_flathub_for "${SUDO_USER}"
else
  bash "${ROOT}/install/machine/install-keybinds.sh"
  bash "${ROOT}/install/machine/install-desktop-conf.sh"
  if [[ "${HOME:-}" != "" && "${HOME}" != "/root" ]]; then
    seed_backgrounds "${HOME}"
    ensure_flathub_for "$(id -un)"
  elif [[ -d /home/andrew ]]; then
    seed_backgrounds /home/andrew
    ensure_flathub_for andrew
  fi
fi
