#!/usr/bin/env bash
# install-console-software — enable multilib if needed, install console seats.
# Usage (guest): sudo bash /mnt/proteus/vm/guest/install-console-software.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

as_root() {
  if [[ "${EUID}" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

echo "==> install-console-software"

CONF=/etc/pacman.conf
if ! grep -q '^\[multilib\]' "$CONF"; then
  if grep -q '^#\[multilib\]' "$CONF"; then
    echo "  enabling [multilib] in pacman.conf"
    as_root sed -i '/^#\[multilib\]/,/^#Include = \/etc\/pacman.d\/mirrorlist/{s/^#//}' "$CONF"
  else
    echo "  appending [multilib]"
    as_root bash -c 'printf "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n" >>/etc/pacman.conf'
  fi
else
  echo "  [multilib] already enabled"
fi

as_root pacman -Sy --noconfirm

# Core console kit
as_root pacman -S --needed --noconfirm gamescope python-evdev || true

for pkg in steam retroarch; do
  if as_root pacman -S --needed --noconfirm "$pkg"; then
    echo "  OK $pkg"
  else
    echo "  WARN: $pkg failed — seat will show honesty in console" >&2
  fi
done

# Optional lean RetroArch assets (best-effort)
as_root pacman -S --needed --noconfirm retroarch-assets-ozone 2>/dev/null || true

# Refresh helpers onto PATH
bash "${ROOT}/vm/guest/apply-console-kit.sh"

echo "==> done"
command -v steam >/dev/null && echo "  steam: $(command -v steam)" || echo "  steam: MISSING"
command -v retroarch >/dev/null && echo "  retroarch: $(command -v retroarch)" || echo "  retroarch: MISSING"
command -v gamescope >/dev/null && echo "  gamescope: $(command -v gamescope)" || echo "  gamescope: MISSING"
