#!/usr/bin/env bash
# Boot the Proteus QEMU/KVM guest.
#
# Usage:
#   ./vm/run.sh install          # Arch ISO + disk (first install)
#   ./vm/run.sh                  # disk only (post-install)
#   ./vm/run.sh snapshot <name>  # qcow2 internal snapshot
#   ./vm/run.sh restore <name>   # apply snapshot
#   ./vm/run.sh snapshots        # list snapshots
#
# Artifacts (ISO, qcow2, OVMF vars, boot extract) live under
#   PROTEUS_VM_CACHE (default: ~/.cache/proteus-vm) — see vm/lib.sh
#
# Automation (optional env):
#   PROTEUS_VM_DISPLAY=none|gtk|gtk,gl=on|…   (default: gtk,gl=on,zoom-to-fit=on)
#   PROTEUS_VM_GL=0|1               (default 1 — virtio-vga-gl; set 0 for plain virtio-vga)
#   PROTEUS_VM_AUDIO=pipewire|pa|sdl|0  (default pa — Pulse-on-PipeWire; stabler under VirGL; 0 disables)
#   PROTEUS_VM_AUDIO_BUFFER=μs      (default 200000 — out/in buffer-length; raise if crackle)
#   PROTEUS_VM_AUDIO_TIMER=μs       (default 20000 — audiodev timer-period)
#   PROTEUS_VM_SOUND=hda|virtio     (default hda — ich9-hda; virtio = virtio-sound-pci)
#   PROTEUS_VM_QMP=1                unix QMP at $PROTEUS_VM_CACHE/runtime/qmp.sock
#   PROTEUS_VM_SERIAL=1             unix serial at $PROTEUS_VM_CACHE/runtime/serial.sock
#   PROTEUS_VM_DIRECT_KERNEL=1      install: boot extracted kernel + ttyS0
set -euo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
proteus_vm_migrate_legacy
proteus_vm_ensure_dirs

ROOT="${PROTEUS_ROOT}"
VM_DIR="${PROTEUS_VM_DIR}"
ISO="${PROTEUS_VM_ISO}"
DISK="${PROTEUS_VM_DISK}"
VARS="${PROTEUS_VM_VARS}"
OVMF_CODE="${OVMF_CODE:-/usr/share/edk2/x64/OVMF_CODE.4m.fd}"
OVMF_VARS_TEMPLATE="${OVMF_VARS_TEMPLATE:-/usr/share/edk2/x64/OVMF_VARS.4m.fd}"
KERNEL="${PROTEUS_VM_KERNEL}"
INITRD="${PROTEUS_VM_INITRD}"
QMP_SOCK="${PROTEUS_VM_QMP_SOCK}"
SERIAL_SOCK="${PROTEUS_VM_SERIAL_SOCK}"

CPUS="${PROTEUS_VM_CPUS:-6}"
MEM="${PROTEUS_VM_MEM:-8G}"
SSH_PORT="${PROTEUS_VM_SSH_PORT:-2222}"
# Hyprland + Quickshell are painful on software virtio-vga — prefer VirGL.
USE_GL="${PROTEUS_VM_GL:-1}"
if [[ -n "${PROTEUS_VM_DISPLAY:-}" ]]; then
  DISPLAY_OPT="${PROTEUS_VM_DISPLAY}"
elif [[ "${USE_GL}" == "1" ]]; then
  DISPLAY_OPT="gtk,gl=on,zoom-to-fit=on"
else
  DISPLAY_OPT="gtk,zoom-to-fit=on"
fi
if [[ "${USE_GL}" == "1" ]]; then
  VGA_DEV="virtio-vga-gl"
else
  VGA_DEV="virtio-vga"
fi

# Host audio backend for guest intel-hda (Settings → Sound needs a real sink).
# Native qemu pipewire audiodev often underruns under VirGL; Pulse (pa) via pipewire-pulse
# is usually stabler. Always force 48 kHz (host is 48k-only) and large buffers.
AUDIO_BACKEND="${PROTEUS_VM_AUDIO:-pa}"
case "${AUDIO_BACKEND}" in
  0|none|off|false) AUDIO_BACKEND="none" ;;
  pulse|pulseaudio) AUDIO_BACKEND="pa" ;;
  pipewire|pa|alsa|sdl|none) ;;
  *)
    echo "Unknown PROTEUS_VM_AUDIO=${AUDIO_BACKEND} (use pipewire|pa|sdl|0)" >&2
    AUDIO_BACKEND="pa"
    ;;
esac
AUDIO_BUFFER_US="${PROTEUS_VM_AUDIO_BUFFER:-200000}"
AUDIO_TIMER_US="${PROTEUS_VM_AUDIO_TIMER:-20000}"
AUDIODEV_OPT=""
if [[ "${AUDIO_BACKEND}" != "none" ]]; then
  AUDIODEV_OPT="${AUDIO_BACKEND},id=snd0,out.frequency=48000,in.frequency=48000"
  AUDIODEV_OPT+=",out.buffer-length=${AUDIO_BUFFER_US},in.buffer-length=${AUDIO_BUFFER_US}"
  AUDIODEV_OPT+=",timer-period=${AUDIO_TIMER_US}"
fi

MODE="${1:-run}"
SNAP_NAME="${2:-}"

die() { echo "$*" >&2; exit 1; }

need() {
  command -v "$1" >/dev/null 2>&1 || die "Missing: $1
On Arch, install: sudo pacman -S qemu-desktop qemu-img edk2-ovmf"
}

need qemu-system-x86_64
need qemu-img

ensure_vars() {
  mkdir -p "${PROTEUS_VM_VARS_DIR}"
  if [[ ! -f "${VARS}" ]]; then
    [[ -f "${OVMF_VARS_TEMPLATE}" ]] || die "OVMF vars template not found: ${OVMF_VARS_TEMPLATE}"
    cp "${OVMF_VARS_TEMPLATE}" "${VARS}"
    echo "Created UEFI vars: ${VARS}"
  fi
}

ensure_disk() {
  [[ -f "${DISK}" ]] || die "Disk missing: ${DISK}
Create it with:  ./vm/create-disk.sh"
}

case "${MODE}" in
  snapshot)
    [[ -n "${SNAP_NAME}" ]] || die "Usage: ./vm/run.sh snapshot <name>"
    ensure_disk
    qemu-img snapshot -c "${SNAP_NAME}" "${DISK}"
    echo "Created snapshot '${SNAP_NAME}' on ${DISK}"
    qemu-img snapshot -l "${DISK}"
    exit 0
    ;;
  restore)
    [[ -n "${SNAP_NAME}" ]] || die "Usage: ./vm/run.sh restore <name>"
    ensure_disk
    qemu-img snapshot -a "${SNAP_NAME}" "${DISK}"
    echo "Restored snapshot '${SNAP_NAME}'"
    exit 0
    ;;
  snapshots)
    ensure_disk
    qemu-img snapshot -l "${DISK}"
    exit 0
    ;;
  install|run) ;;
  -h|--help|help)
    sed -n '2,20p' "$0"
    exit 0
    ;;
  *)
    die "Unknown mode: ${MODE}
Usage: ./vm/run.sh [install|run|snapshot|restore|snapshots]"
    ;;
esac

ensure_disk
ensure_vars

[[ -f "${OVMF_CODE}" ]] || die "OVMF code not found: ${OVMF_CODE}
Install: sudo pacman -S edk2-ovmf"

rm -f "${QMP_SOCK}" "${SERIAL_SOCK}"

ARGS=(
  -enable-kvm
  -machine q35,accel=kvm
  -cpu host
  -smp "${CPUS}"
  -m "${MEM}"
  -drive if=pflash,format=raw,readonly=on,file="${OVMF_CODE}"
  -drive if=pflash,format=raw,file="${VARS}"
  # if=none + virtio-blk so we can set bootindex (OVMF ignores -boot order=).
  -drive if=none,id=proteus-disk,format=qcow2,file="${DISK}"
  -device virtio-blk-pci,drive=proteus-disk,bootindex=1
  -netdev user,id=net0,hostfwd=tcp::"${SSH_PORT}"-:22
  -device virtio-net-pci,netdev=net0,bootindex=3
  -device "${VGA_DEV}"
  -display "${DISPLAY_OPT}"
  -device qemu-xhci
  -device usb-tablet
  -virtfs local,path="${ROOT}",mount_tag=proteus,security_model=mapped-xattr,id=proteus
)

echo "  cache: ${PROTEUS_VM_CACHE}"
echo "  gpu:   ${VGA_DEV}  display: ${DISPLAY_OPT}"
if [[ "${USE_GL}" != "1" ]]; then
  echo "  note:  PROTEUS_VM_GL=0 — software virtio-vga (Hyprland will feel laggy)"
fi

SOUND_DEV="${PROTEUS_VM_SOUND:-hda}"
case "${SOUND_DEV}" in
  hda|ich9|intel-hda) SOUND_DEV="hda" ;;
  virtio|virtio-sound|virtio-snd) SOUND_DEV="virtio" ;;
  *)
    echo "Unknown PROTEUS_VM_SOUND=${SOUND_DEV} (use hda|virtio)" >&2
    SOUND_DEV="hda"
    ;;
esac

if [[ "${AUDIO_BACKEND}" != "none" ]]; then
  ARGS+=(-audiodev "${AUDIODEV_OPT}")
  if [[ "${SOUND_DEV}" == "virtio" ]]; then
    ARGS+=(-device virtio-sound-pci,audiodev=snd0)
    echo "  audio: virtio-sound-pci via host ${AUDIO_BACKEND} (48k, buffer=${AUDIO_BUFFER_US}μs)"
  else
    ARGS+=(-device ich9-intel-hda)
    ARGS+=(-device hda-duplex,audiodev=snd0)
    echo "  audio: ich9-intel-hda via host ${AUDIO_BACKEND} (48k, buffer=${AUDIO_BUFFER_US}μs)"
  fi
else
  echo "  audio: disabled (PROTEUS_VM_AUDIO=0)"
fi

if [[ "${PROTEUS_VM_QMP:-0}" == "1" ]]; then
  ARGS+=(-qmp "unix:${QMP_SOCK},server,nowait")
  echo "QMP: ${QMP_SOCK}"
fi

if [[ "${PROTEUS_VM_SERIAL:-0}" == "1" ]]; then
  ARGS+=(-serial "unix:${SERIAL_SOCK},server,nowait")
  echo "Serial: ${SERIAL_SOCK}"
fi

if [[ "${MODE}" == "install" ]]; then
  [[ -f "${ISO}" ]] || die "ISO missing: ${ISO}
Download it with:  ./vm/download-iso.sh"
  # Prefer ISO over disk (disk still bootindex=1 in ARGS — override via cdrom bootindex=0 first).
  ARGS+=(-drive if=none,id=proteus-cd,media=cdrom,readonly=on,file="${ISO}")
  if [[ "${PROTEUS_VM_DIRECT_KERNEL:-0}" == "1" ]]; then
    [[ -f "${KERNEL}" && -f "${INITRD}" ]] || die "Direct kernel boot needs:
  ${KERNEL}
  ${INITRD}
Extract from ISO into \$PROTEUS_VM_CACHE/boot/ first."
    # -kernel claims bootindex 0; attach ISO as data CD only (archiso finds squashfs).
    ARGS+=(-device ide-cd,drive=proteus-cd)
    ARGS+=(
      -kernel "${KERNEL}"
      -initrd "${INITRD}"
      -append "archisobasedir=arch archisosearchuuid=2026-07-01-16-36-20-00 console=ttyS0,115200n8 copytoram=n"
    )
    echo "Install mode: direct kernel + serial console (Arch live)"
  else
    ARGS+=(-device ide-cd,drive=proteus-cd,bootindex=0)
    ARGS+=(-boot order=d)
    echo "Install mode: booting Arch ISO + disk"
  fi
else
  ARGS+=(-boot order=c)
  echo "Run mode: booting installed disk"
fi

echo "  disk:  ${DISK}"
echo "  share: ${ROOT} -> guest mount tag 'proteus' (/mnt/proteus)"
echo "  ssh:   ssh -p ${SSH_PORT} <user>@127.0.0.1   (after openssh is enabled in guest)"
echo

exec qemu-system-x86_64 "${ARGS[@]}"
