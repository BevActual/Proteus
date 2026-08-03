#!/usr/bin/env bash
# Apply Proteus login greeter (greetd + tuigreet).
# Run as root, or: ssh … 'sudo bash -s' < apply-greeter.sh
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
REPO="$(cd "${HERE}/../.." && pwd)"
# Assets ship beside this script; proteus-session is a runtime helper and lives
# with the rest of them in shell/scripts.
ASSETS="${HERE}/assets"
SESSION_BIN="${REPO}/shell/scripts/proteus-session"

for need in "${ASSETS}/greetd-config.toml" "${ASSETS}/proteus.desktop" "${SESSION_BIN}"; do
  [[ -f "${need}" ]] || { echo "apply-greeter: missing ${need}" >&2; exit 1; }
done

pacman -S --noconfirm --needed greetd greetd-tuigreet

install -d /etc/greetd
install -m 644 "${ASSETS}/greetd-config.toml" /etc/greetd/config.toml
install -m 755 "${SESSION_BIN}" /usr/local/bin/proteus-session
install -m 644 "${ASSETS}/proteus.desktop" /usr/share/wayland-sessions/proteus.desktop

# Session icon (proteus mark)
bash "${REPO}/install/machine/install-icons.sh" 2>/dev/null \
  || bash /mnt/proteus/install/machine/install-icons.sh 2>/dev/null \
  || true

# greeter user is created by greetd package
usermod -aG video greeter 2>/dev/null || true

systemctl enable greetd.service
systemctl set-default graphical.target

# Avoid fighting greetd on tty1
systemctl disable getty@tty1.service 2>/dev/null || true

GREET_USER="$(sed -n 's/^user *= *"\(.*\)"/\1/p' "${ASSETS}/greetd-config.toml" | head -1)"
echo "Greeter installed. Reboot to cold-boot into Proteus (autologin ${GREET_USER:-the session user} → lock screen)."
echo "After logout, tuigreet still appears. Session: Proteus."
echo "Apply: sudo bash ${REPO}/install/machine/apply-greeter.sh && sudo systemctl restart greetd"
