#!/usr/bin/env bash
# Install Proteus Settings (iced sibling) + owned shell helpers on the guest.
set -euo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)"
# shellcheck source=../helpers.sh
source "${ROOT}/install/helpers.sh"

# Brand marks into icon theme (proteus / proteus-settings)
bash "${ROOT}/install/machine/install-icons.sh"
# Hide pavucontrol / blueman / nm-editor from Beacon (Calculator stays)
bash "${ROOT}/install/machine/hide-system-apps.sh"

install -d /usr/local/bin

# iced Settings (sibling repo ../ProteusSettings) — sole Settings app.
ST_ROOT="${PROTEUS_SETTINGS_ROOT:-}"
if [[ -z "${ST_ROOT}" ]]; then
  for cand in "${ROOT}/../ProteusSettings" /mnt/proteus-settings; do
    if [[ -d "${cand}" ]] && { [[ -f "${cand}/Cargo.toml" ]] || [[ -d "${cand}/app" ]]; }; then
      ST_ROOT="${cand}"
      break
    fi
  done
fi
if [[ -z "${ST_ROOT}" ]] && grep -q 9p /proc/filesystems 2>/dev/null; then
  install -d /mnt/proteus-settings
  mount -t 9p -o trans=virtio,version=9p2000.L,msize=262144 \
    proteus-settings /mnt/proteus-settings 2>/dev/null || true
  [[ -d /mnt/proteus-settings ]] && ST_ROOT=/mnt/proteus-settings
fi
ST_BIN=""
if [[ -n "${ST_ROOT}" ]]; then
  for t in target/release/proteus-settings-next \
           target/release/proteus-settings \
           app/src-tauri/target/release/proteus-settings \
           app/bin/proteus-settings; do
    if [[ -x "${ST_ROOT}/${t}" ]]; then
      ST_BIN="${ST_ROOT}/${t}"
      break
    fi
  done
fi
if [[ -z "${ST_BIN}" && -n "${ST_ROOT}" && -f "${ST_ROOT}/Cargo.toml" ]] \
  && command -v cargo >/dev/null 2>&1; then
  echo "note: building proteus-settings-next (release)…"
  (cd "${ST_ROOT}" && cargo build --release) \
    && ST_BIN="${ST_ROOT}/target/release/proteus-settings-next" || true
  [[ -z "${ST_BIN}" && -x "${ST_ROOT}/target/release/proteus-settings" ]] \
    && ST_BIN="${ST_ROOT}/target/release/proteus-settings"
fi
if [[ -z "${ST_BIN}" || ! -x "${ST_BIN}" ]]; then
  echo "error: proteus-settings (iced) required — build sibling first:" >&2
  echo "  (cd ${ST_ROOT:-../ProteusSettings} && cargo build --release)" >&2
  exit 1
fi

install -d /usr/local/libexec/proteus
install -m 755 "${ST_BIN}" /usr/local/libexec/proteus/proteus-settings-next
install -m 755 "${ST_BIN}" /usr/local/bin/proteus-settings-next
# Remove retired QML fallback if present from older installs.
rm -f /usr/local/bin/proteus-settings-qml
cat > /usr/local/bin/proteus-settings << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
BIN=/usr/local/libexec/proteus/proteus-settings-next
[[ -x "${BIN}" ]] || BIN="$(command -v proteus-settings-next || true)"
if [[ -z "${BIN}" || ! -x "${BIN}" ]]; then
  echo "proteus-settings: iced binary missing" >&2
  exit 1
fi
page="" query=""
for arg in "$@"; do
  case "$arg" in
    --page=*) page="${arg#--page=}" ;;
    --query=*) query="${arg#--query=}" ;;
  esac
done
args=()
[[ -n "${page}" ]] && args+=(--page "${page}")
[[ -n "${query}" ]] && args+=(--query "${query}")
exec "${BIN}" "${args[@]}"
EOF
chmod 755 /usr/local/bin/proteus-settings
echo "Installed proteus-settings → iced (proteus-settings-next)"

# Wallpaper is owned by proteus-shell BG layer. Keep a thin no-op proteus-bg
# so older hypr/settings apply paths that pkill/restart it do not fail loud.
cat > /usr/local/bin/proteus-bg << 'EOF'
#!/usr/bin/env bash
# Retired Quickshell wallpaper runner — owned shell paints BG.
# No-op so legacy callers (pkill / Settings apply) stay quiet.
exit 0
EOF
chmod 755 /usr/local/bin/proteus-bg
echo "Installed proteus-bg → no-op (owned shell paints wallpaper)"

install -d /usr/share/applications
DESKTOP_SRC=""
for cand in \
  "${ST_ROOT}/packaging/proteus-settings.desktop" \
  "${ST_ROOT}/proteus-settings.desktop" \
  "${ROOT}/env/desktop/proteus-settings.desktop"; do
  if [[ -f "${cand}" ]]; then
    DESKTOP_SRC="${cand}"
    break
  fi
done
if [[ -n "${DESKTOP_SRC}" ]]; then
  install -m 644 "${DESKTOP_SRC}" /usr/share/applications/proteus-settings.desktop
else
  cat > /usr/share/applications/proteus-settings.desktop << 'EOF'
[Desktop Entry]
Name=Settings
Comment=Proteus system settings
Exec=proteus-settings
Icon=proteus-settings
Terminal=false
Type=Application
Categories=Settings;X-Proteus;
EOF
fi
if grep -q '^Icon=' /usr/share/applications/proteus-settings.desktop; then
  sed -i 's/^Icon=.*/Icon=proteus-settings/' /usr/share/applications/proteus-settings.desktop
fi

echo "Installed proteus-settings → /usr/local/bin/proteus-settings"

# Seed per-user backgrounds folder (stock images)
seed_backgrounds() {
  local home="$1"
  local dest="${home}/.local/share/proteus/backgrounds"
  local owner group
  owner="$(stat -c %u "${home}")"
  group="$(stat -c %g "${home}")"
  install -d -o "${owner}" -g "${group}" \
    "${home}/.local" "${home}/.local/share" \
    "${home}/.local/share/proteus" "${dest}"
  local assets="${ROOT}/shell/assets"
  if [[ -d "${assets}" ]]; then
    shopt -s nullglob
    for f in "${assets}"/wallpaper*.jpg "${assets}"/wallpaper*.png; do
      local base
      base="$(basename "$f")"
      if [[ ! -e "${dest}/${base}" ]]; then
        cp -n "$f" "${dest}/${base}" 2>/dev/null || true
        chown "${owner}:${group}" "${dest}/${base}" 2>/dev/null || true
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

# Owned shell spine + launcher (OWNED-STACK rung 0)
if [[ -x "${ROOT}/services/proteus-shell-core/bin/proteus-shell-core" ]] \
  || [[ -x "${ROOT}/services/proteus-shell-core/target/release/proteus-shell-core" ]] \
  || command -v cargo >/dev/null 2>&1; then
  bash "${ROOT}/install/machine/install-proteus-shell-core.sh"
else
  echo "note: skipped proteus-shell-core (build release on host first)"
fi

# Owned iced shell — fail closed
if [[ -x "${ROOT}/target/release/proteus-shell" ]] \
  || [[ -x "${ROOT}/shell/target/release/proteus-shell" ]] \
  || command -v cargo >/dev/null 2>&1; then
  bash "${ROOT}/install/machine/install-proteus-shell.sh"
else
  echo "error: proteus-shell required — build release on host first:" >&2
  echo "  (cd ${ROOT} && cargo build -p proteus-shell --release)" >&2
  exit 1
fi

# Owned compositor (smithay) — soft-skip install; session refuses hyprland Fact
if [[ -x "${ROOT}/install/machine/install-proteus-compositor.sh" ]]; then
  bash "${ROOT}/install/machine/install-proteus-compositor.sh" \
    || echo "note: compositor install soft-failed"
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
  if [[ -n "${HOME:-}" && "${HOME}" != "/root" ]]; then
    seed_backgrounds "${HOME}"
    ensure_flathub_for "$(id -un)"
  elif session_user="$(proteus_session_user)"; then
    session_home="$(getent passwd "${session_user}" 2>/dev/null | cut -d: -f6 || true)"
    if [[ -n "${session_home}" && -d "${session_home}" ]]; then
      seed_backgrounds "${session_home}"
      ensure_flathub_for "${session_user}"
    else
      echo "note: no home for ${session_user} — skipped backgrounds / flathub seed"
    fi
  else
    echo "note: session user unresolved — skipped backgrounds / flathub seed" >&2
  fi
fi
