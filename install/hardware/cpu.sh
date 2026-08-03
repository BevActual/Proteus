#!/usr/bin/env bash
# cpu — CPU microcode on bare metal (skipped in guests; the host owns it there).
#
# pacstrap does not install microcode automatically, and a manual Arch install
# (the documented bare-metal path — INSTALL.md) frequently misses it. Missing
# microcode shows up as instability under load rather than an obvious error,
# which is exactly the class of bug that would get misattributed to Proteus.
set -euo pipefail
# shellcheck source=_lib.sh
source "$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)/_lib.sh"

if [[ "${PROTEUS_HW_VIRT:-0}" == "1" ]] || proteus_hw_is_virt; then
  echo "hardware/cpu: virt guest — skip (host provides microcode)"
  exit 0
fi

VENDOR="$(grep -m1 '^vendor_id' /proc/cpuinfo 2>/dev/null | awk '{print $3}' || true)"
case "${VENDOR}" in
  GenuineIntel) UCODE=intel-ucode ;;
  AuthenticAMD) UCODE=amd-ucode ;;
  *)
    echo "hardware/cpu: unknown CPU vendor '${VENDOR:-none}' — skip"
    exit 0
    ;;
esac

if pacman -Q "${UCODE}" >/dev/null 2>&1; then
  echo "hardware/cpu: ${UCODE} already installed"
else
  echo "hardware/cpu: installing ${UCODE}"
  proteus_root pacman -S --noconfirm --needed "${UCODE}" \
    || { echo "hardware/cpu: WARN ${UCODE} install failed" >&2; exit 0; }
fi

# Honesty: installing the package is not enough — the bootloader must load the
# image. GRUB picks it up on regenerate; systemd-boot needs an explicit line.
if [[ -d /boot/loader/entries ]]; then
  if ! grep -rqs "${UCODE}.img" /boot/loader/entries 2>/dev/null; then
    echo "hardware/cpu: NOTE systemd-boot detected — microcode is NOT loaded yet."
    echo "hardware/cpu:      add this ABOVE the main initrd line in your boot entry:"
    echo "hardware/cpu:        initrd  /${UCODE}.img"
    echo "hardware/cpu:      (Proteus does not edit boot entries — see ArchWiki 'Microcode')"
  else
    echo "hardware/cpu: systemd-boot entry already references ${UCODE}.img"
  fi
elif command -v grub-mkconfig >/dev/null 2>&1; then
  echo "hardware/cpu: GRUB detected — run: sudo grub-mkconfig -o /boot/grub/grub.cfg"
fi

echo "hardware/cpu: OK"
