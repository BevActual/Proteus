#!/usr/bin/env bash
# Install the Proteus Workloads app (iced, sibling repo ../ProteusWorkloads).
#
# Prebuilt honesty gate: installs the release binary from the sibling checkout;
# if none exists, skip with a build note — never a fake launcher. Build with:
#   cd ProteusWorkloads && cargo build --release
set -euo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)"

WL_ROOT="${PROTEUS_WORKLOADS_ROOT:-}"
if [[ -z "${WL_ROOT}" ]]; then
  for cand in "${ROOT}/../ProteusWorkloads" /mnt/proteus-workloads; do
    if [[ -d "${cand}" ]] && { [[ -f "${cand}/Cargo.toml" ]] || [[ -d "${cand}/app" ]]; }; then
      WL_ROOT="${cand}"
      break
    fi
  done
fi
if [[ -z "${WL_ROOT}" ]] && grep -q 9p /proc/filesystems 2>/dev/null; then
  install -d /mnt/proteus-workloads
  mount -t 9p -o trans=virtio,version=9p2000.L,msize=262144 \
    proteus-workloads /mnt/proteus-workloads 2>/dev/null || true
  [[ -d /mnt/proteus-workloads ]] && WL_ROOT=/mnt/proteus-workloads
fi

BIN=""
if [[ -n "${WL_ROOT}" ]]; then
  for t in target/release/proteus-workloads \
           app/src-tauri/target/release/proteus-workloads \
           app/bin/proteus-workloads; do
    if [[ -x "${WL_ROOT}/${t}" ]]; then
      BIN="${WL_ROOT}/${t}"
      break
    fi
  done
fi

if [[ -z "${BIN}" && -n "${WL_ROOT}" && -f "${WL_ROOT}/Cargo.toml" ]] \
  && command -v cargo >/dev/null 2>&1; then
  echo "note: building proteus-workloads (release)…"
  (cd "${WL_ROOT}" && cargo build --release) && BIN="${WL_ROOT}/target/release/proteus-workloads" || true
fi

if [[ -z "${BIN}" || ! -x "${BIN}" ]]; then
  echo "note: skipped proteus-workloads (no prebuilt iced binary)" >&2
  echo "      build on host first: cd ProteusWorkloads && cargo build --release" >&2
  echo "      sibling root: PROTEUS_WORKLOADS_ROOT (default ../ProteusWorkloads)" >&2
  exit 0
fi

bash "${ROOT}/install/machine/install-icons.sh"

install -d /usr/local/bin
install -m 755 "${BIN}" /usr/local/bin/proteus-workloads

install -d /usr/share/applications
for DESKTOP in \
  "${WL_ROOT}/packaging/proteus-workloads.desktop" \
  "${WL_ROOT}/app/packaging/proteus-workloads.desktop"; do
  if [[ -f "${DESKTOP}" ]]; then
    install -m 644 "${DESKTOP}" /usr/share/applications/proteus-workloads.desktop
    break
  fi
done

echo "Installed proteus-workloads (iced) → /usr/local/bin/proteus-workloads"
