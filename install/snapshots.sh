#!/usr/bin/env bash
# snapshots — btrfs rollback safety net for bare-metal dogfood.
#
# The VM harness has `dev/vm/run.sh snapshot|restore`. Bare metal has no undo, and a
# posture flip / greetd change / GPU driver swap can cost a boot. This stage
# restores that property on btrfs roots via snapper.
#
# Runs EARLY (right after preflight) so the baseline it takes is genuinely
# "before Proteus touched this machine" — the packaging stage has not run yet.
#
# Honesty gates (never fake a safety net that isn't there):
#   - root is not btrfs        → log + skip, exit 0
#   - snapper unavailable      → log + skip, exit 0
#   - pre-existing snapper cfg → reuse it, never clobber retention settings
#
# Knobs:
#   PROTEUS_INSTALL_SNAPSHOTS=0   skip entirely
#   PROTEUS_SNAPSHOT_BOOT=1       also install grub-btrfs (GRUB systems only)
set -euo pipefail
# shellcheck source=helpers.sh
source "$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)/helpers.sh"

if [[ "${PROTEUS_INSTALL_SNAPSHOTS:-1}" == "0" ]]; then
  proteus_log "snapshots: PROTEUS_INSTALL_SNAPSHOTS=0 — skip"
  exit 0
fi

ROOT_FS="$(findmnt -no FSTYPE / 2>/dev/null || true)"
ROOT_SRC="$(findmnt -no SOURCE / 2>/dev/null || true)"

if [[ "${ROOT_FS}" != "btrfs" ]]; then
  proteus_log "snapshots: root is ${ROOT_FS:-unknown}, not btrfs — skip (no rollback net)"
  proteus_log "snapshots: VM harness users keep ./dev/vm/run.sh snapshot|restore"
  exit 0
fi

proteus_log "snapshots: btrfs root (${ROOT_SRC})"

# --- packages -----------------------------------------------------------------
# snap-pac wraps every pacman transaction in pre/post snapshots — the single
# highest-value piece for a rolling-release dogfood box.
PKGS=(snapper snap-pac btrfs-progs)
if [[ "${PROTEUS_SNAPSHOT_BOOT:-0}" == "1" ]]; then
  if [[ -d /boot/grub ]] || command -v grub-mkconfig >/dev/null 2>&1; then
    PKGS+=(grub-btrfs)
  else
    proteus_log "snapshots: PROTEUS_SNAPSHOT_BOOT=1 but no GRUB found — skipping grub-btrfs"
    proteus_log "snapshots: systemd-boot users boot a snapshot from a live USB instead"
  fi
fi

if command -v pacman >/dev/null 2>&1; then
  proteus_log "snapshots: pacman -S --needed ${PKGS[*]}"
  proteus_root pacman -S --noconfirm --needed "${PKGS[@]}" \
    || proteus_log "warn: snapshot package install failed — continuing without the net"
fi

if ! command -v snapper >/dev/null 2>&1; then
  proteus_log "snapshots: snapper unavailable — skip (no rollback net)"
  exit 0
fi

# --- snapper root config ------------------------------------------------------
if proteus_root snapper -c root get-config >/dev/null 2>&1; then
  proteus_log "snapshots: reusing existing snapper 'root' config (retention untouched)"
else
  proteus_log "snapshots: creating snapper 'root' config"
  if ! proteus_root snapper -c root create-config /; then
    proteus_log "warn: snapper create-config failed — see https://wiki.archlinux.org/title/Snapper"
    proteus_log "snapshots: common cause — /.snapshots already exists as a subvolume; adopt it manually"
    exit 0
  fi
  # Dogfood-shaped retention: enough history to walk back a bad week, small
  # enough that a 1TB laptop does not fill with snapshots.
  proteus_root snapper -c root set-config \
    TIMELINE_CREATE=yes \
    TIMELINE_LIMIT_HOURLY=6 \
    TIMELINE_LIMIT_DAILY=7 \
    TIMELINE_LIMIT_WEEKLY=4 \
    TIMELINE_LIMIT_MONTHLY=2 \
    TIMELINE_LIMIT_YEARLY=0 \
    NUMBER_LIMIT=20 \
    NUMBER_LIMIT_IMPORTANT=10 \
    2>/dev/null || proteus_log "warn: could not set snapper retention"

  # Let the session user read snapshot state without sudo (Settings / helper status).
  USER_NAME="$(proteus_session_user)"
  proteus_root snapper -c root set-config "ALLOW_USERS=${USER_NAME}" 2>/dev/null || true
  proteus_root btrfs subvolume list / >/dev/null 2>&1 || true
fi

proteus_root systemctl enable --now snapper-timeline.timer 2>/dev/null \
  || proteus_log "warn: snapper-timeline.timer not enabled"
proteus_root systemctl enable --now snapper-cleanup.timer 2>/dev/null \
  || proteus_log "warn: snapper-cleanup.timer not enabled"

# --- baseline -----------------------------------------------------------------
# Tagged so `proteus-snapshot list` can point at "the last known-good pre-Proteus
# state" without the operator having to remember a number.
if proteus_root snapper -c root list 2>/dev/null | grep -q 'proteus:baseline'; then
  proteus_log "snapshots: baseline already present — not re-taking"
else
  if proteus_root snapper -c root create \
      --description "proteus:baseline — before Proteus overlay" \
      --cleanup-algorithm number \
      --userdata "proteus=baseline" 2>/dev/null; then
    proteus_log "snapshots: baseline snapshot created"
  else
    proteus_log "warn: baseline snapshot failed"
  fi
fi

proteus_log "snapshots: OK — inspect with 'proteus-snapshot status'"
