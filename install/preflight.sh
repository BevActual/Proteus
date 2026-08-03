#!/usr/bin/env bash
# preflight — 9p share, paths, basic sanity
set -euo pipefail
# shellcheck source=helpers.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

PROTEUS_ROOT="$(proteus_install_root)"
export PROTEUS_ROOT
PROTEUS_INSTALL="${PROTEUS_ROOT}/install"
export PROTEUS_INSTALL

proteus_log "PROTEUS_ROOT=${PROTEUS_ROOT}"

if [[ ! -d "${PROTEUS_ROOT}/shell" ]]; then
  echo "preflight: missing ${PROTEUS_ROOT}/shell" >&2
  exit 1
fi

for need in \
  "${PROTEUS_INSTALL}/proteus-base.packages" \
  "${PROTEUS_INSTALL}/proteus-desktop.packages" \
  "${PROTEUS_ROOT}/install/machine" \
  "${PROTEUS_ROOT}/env/hypr/hyprland.conf"
do
  if [[ ! -e "${need}" ]]; then
    echo "preflight: missing ${need}" >&2
    exit 1
  fi
done
proteus_log "tree OK (packages, machine/, env/hypr)"

# Fail fast on the two things that make a long overlay run die halfway through.
# In the VM both were effectively guaranteed; on bare metal neither is.
DISK_FREE_MB="$(df -Pm / 2>/dev/null | awk 'NR==2 {print $4}' || echo 0)"
if [[ "${DISK_FREE_MB:-0}" -gt 0 && "${DISK_FREE_MB}" -lt 6000 ]]; then
  echo "preflight: only ${DISK_FREE_MB}MB free on / — the full overlay needs ~6GB" >&2
  echo "preflight:   (console stage alone pulls Steam + lib32 + RetroArch cores)" >&2
  echo "preflight:   free space, or skip stages: PROTEUS_INSTALL_SKIP=console,desktop" >&2
  exit 1
fi
proteus_log "disk OK (${DISK_FREE_MB}MB free on /)"

# Every package stage needs a working mirror. Checking once here turns a
# confusing mid-run pacman failure into an immediate, actionable message.
# proteus_root, not bare pacman: -Sy needs root, and a permission error here
# would otherwise be misreported as "no network".
if command -v pacman >/dev/null 2>&1; then
  if ! timeout 40 proteus_root pacman -Sy >/dev/null 2>&1; then
    echo "preflight: cannot refresh pacman databases — no network, mirrors down, or no sudo" >&2
    echo "preflight:   check: ping -c1 archlinux.org · sudo pacman -Sy" >&2
    echo "preflight:   offline re-run of config/apps only: bootstrap.sh repair (skips preflight)" >&2
    exit 1
  fi
  proteus_log "pacman databases refreshed"
fi

# Ensure 9p mount unit exists + enabled when on a real guest
proteus_is_guest() {
  [[ "${PROTEUS_ROOT}" == /mnt/proteus ]] && return 0
  [[ -n "${PROTEUS_FORCE_GUEST:-}" ]] && return 0
  if command -v systemd-detect-virt >/dev/null 2>&1; then
    systemd-detect-virt -q 2>/dev/null && return 0
  fi
  grep -qiE 'qemu|kvm|virtualbox|vmware|microsoft' /sys/class/dmi/id/product_name 2>/dev/null && return 0
  return 1
}

if proteus_is_guest && [[ -d /etc/systemd/system ]]; then
  if [[ ! -f /etc/systemd/system/mnt-proteus.mount ]]; then
    proteus_log "installing mnt-proteus.mount"
    proteus_root install -d /mnt/proteus
    proteus_root tee /etc/systemd/system/mnt-proteus.mount >/dev/null <<'MOUNT'
[Unit]
Description=Proteus 9p host share
After=network-online.target

[Mount]
What=proteus
Where=/mnt/proteus
Type=9p
Options=trans=virtio,version=9p2000.L,msize=262144,_netdev

[Install]
WantedBy=multi-user.target
MOUNT
  fi
  proteus_root systemctl enable mnt-proteus.mount 2>/dev/null || true
  if ! mountpoint -q /mnt/proteus 2>/dev/null; then
    proteus_root systemctl start mnt-proteus.mount 2>/dev/null \
      || proteus_root mount -t 9p -o trans=virtio,version=9p2000.L,msize=262144 proteus /mnt/proteus \
      || true
  fi
elif [[ -d /etc/systemd/system ]]; then
  proteus_log "skip 9p mount unit (not a guest; set PROTEUS_FORCE_GUEST=1 to force)"
fi

if ! mountpoint -q /mnt/proteus 2>/dev/null && [[ "${PROTEUS_ROOT}" == /mnt/proteus ]]; then
  echo "preflight: /mnt/proteus not mounted (continuing if PROTEUS_ROOT is set)" >&2
fi

proteus_log "preflight OK"
