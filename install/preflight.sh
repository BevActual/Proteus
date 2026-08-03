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
proteus_log "tree OK (packages, guest/, env/hypr)"

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
