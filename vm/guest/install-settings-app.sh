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

install -d /usr/share/applications
install -m 644 "${APP}/proteus-settings.desktop" /usr/share/applications/proteus-settings.desktop

echo "Installed proteus-settings → /usr/local/bin/proteus-settings"

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
else
  bash "${ROOT}/vm/guest/install-keybinds.sh"
  bash "${ROOT}/vm/guest/install-desktop-conf.sh"
fi
