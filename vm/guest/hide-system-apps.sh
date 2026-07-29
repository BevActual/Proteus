#!/usr/bin/env bash
# Hide Arch/desktop-kit apps from Spotlight when Proteus Settings already owns
# the feature. Packages stay installed as escape hatches (Settings still opens
# nm-connection-editor / blueman / …).
set -euo pipefail

# System-wide overrides beat /usr/share/applications for the same basename.
DEST="${DEST:-/usr/local/share/applications}"
if [[ "${EUID}" -ne 0 ]]; then
  DEST="${XDG_DATA_HOME:-${HOME}/.local/share}/applications"
fi
install -d "${DEST}"

hide() {
  local basename="$1"
  local name="$2"
  local exec_bin="${3:-true}"
  cat > "${DEST}/${basename}.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=${name}
Exec=${exec_bin}
NoDisplay=true
Hidden=true
EOF
}

# Sound → Settings · Sound (pavucontrol remains for advanced routing)
hide pavucontrol "PulseAudio Volume Control" pavucontrol
hide org.pulseaudio.pavucontrol "PulseAudio Volume Control" pavucontrol

# Network → Settings · Network
hide nm-connection-editor "Network Connections" nm-connection-editor

# Bluetooth → Settings · Network (Bluetooth section)
hide blueman-manager "Bluetooth Manager" blueman-manager
hide blueman-adapters "Bluetooth Adapters" blueman-adapters
hide blueman-applet "Bluetooth Applet" blueman-applet

# Avahi discovery UIs — not product surface (zeroconf stays as a service)
hide avahi-discover "Avahi Zeroconf Browser" avahi-discover
hide bssh "Avahi SSH Server Browser" bssh
hide bvnc "Avahi VNC Server Browser" bvnc

# Keep gnome-calculator visible — dedicated Calculator for dogfood
# (Spotlight expression calc remains as a quick path). Drop prior NoDisplay stubs.
rm -f "${DEST}/org.gnome.Calculator.desktop" "${DEST}/gnome-calculator.desktop"

# Disable blueman tray autostart if present
AS_DEST="/etc/xdg/autostart"
if [[ "${EUID}" -ne 0 ]]; then
  AS_DEST="${XDG_CONFIG_HOME:-${HOME}/.config}/autostart"
fi
install -d "${AS_DEST}"
if [[ -f /etc/xdg/autostart/blueman.desktop ]] || [[ -f /usr/share/applications/blueman-applet.desktop ]]; then
  cat > "${AS_DEST}/blueman.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Bluetooth Applet
Exec=blueman-applet
Hidden=true
X-GNOME-Autostart-enabled=false
EOF
fi

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "${DEST}" 2>/dev/null || true
fi

echo "hide-system-apps: OK → ${DEST} (NoDisplay for Settings-covered tools)"
