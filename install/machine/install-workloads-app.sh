#!/usr/bin/env bash
# Install Proteus Workloads thin app on the guest (read-only inventory).
set -euo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)"
APP="${ROOT}/apps/proteus-workloads"

bash "${ROOT}/install/machine/install-icons.sh"

install -d /usr/local/bin
cat > /usr/local/bin/proteus-workloads << EOF
#!/usr/bin/env bash
set -euo pipefail
DIR="${APP}"
export QS_ICON_THEME="\${QS_ICON_THEME:-Papirus-Dark}"

ipc() {
  if command -v qs >/dev/null 2>&1; then
    qs -p "\${DIR}" ipc call "\$@"
  else
    quickshell -p "\${DIR}" ipc call "\$@"
  fi
}

if ipc app state >/dev/null 2>&1; then
  ipc app raise >/dev/null 2>&1 || true
  exit 0
fi

exec quickshell -n -p "\${DIR}"
EOF
chmod 755 /usr/local/bin/proteus-workloads

install -d /usr/share/applications
install -m 644 "${APP}/proteus-workloads.desktop" /usr/share/applications/proteus-workloads.desktop
if grep -q '^Icon=' /usr/share/applications/proteus-workloads.desktop; then
  sed -i 's/^Icon=.*/Icon=proteus/' /usr/share/applications/proteus-workloads.desktop
fi

echo "Installed proteus-workloads → /usr/local/bin/proteus-workloads"
