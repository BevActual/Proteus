#!/usr/bin/env bash
# Apply Proteus login greeter (greetd + tuigreet) on the Arch guest.
# Run on the guest as root, or: ssh … 'sudo bash -s' < apply-greeter.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

pacman -S --noconfirm --needed greetd greetd-tuigreet

install -d /etc/greetd
install -m 644 "${ROOT}/greetd-config.toml" /etc/greetd/config.toml
install -m 755 "${ROOT}/proteus-session" /usr/local/bin/proteus-session
install -m 644 "${ROOT}/proteus.desktop" /usr/share/wayland-sessions/proteus.desktop

# Session icon (proteus mark)
bash "$(cd "${ROOT}/../.." && pwd)/install/machine/install-icons.sh" 2>/dev/null \
  || bash /mnt/proteus/install/machine/install-icons.sh 2>/dev/null \
  || true

# greeter user is created by greetd package
usermod -aG video greeter 2>/dev/null || true

systemctl enable greetd.service
systemctl set-default graphical.target

# Avoid fighting greetd on tty1
systemctl disable getty@tty1.service 2>/dev/null || true

echo "Greeter installed. Reboot to cold-boot into Proteus (autologin andrew → lock screen)."
echo "After logout, tuigreet still appears. Session: Proteus."
echo "Apply: sudo bash /mnt/proteus/install/machine/apply-greeter.sh && sudo systemctl restart greetd"
