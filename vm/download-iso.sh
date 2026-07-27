#!/usr/bin/env bash
# Download the latest Arch Linux x86_64 ISO (+ checksum) into vm/iso/
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ISO_DIR="${ROOT}/vm/iso"
MIRROR="${ARCH_MIRROR:-https://geo.mirror.pkgbuild.com}"
ISO_LIST_URL="${MIRROR}/iso/latest/"

mkdir -p "${ISO_DIR}"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing dependency: $1" >&2
    exit 1
  }
}

need curl
need grep
need sed

echo "Resolving latest Arch ISO from ${ISO_LIST_URL} …"
html="$(curl -fsSL "${ISO_LIST_URL}")"
iso_name="$(printf '%s\n' "${html}" | grep -oE 'archlinux-[0-9]{4}\.[0-9]{2}\.[0-9]{2}-x86_64\.iso' | head -1 || true)"

if [[ -z "${iso_name}" ]]; then
  echo "Could not find an Arch ISO name on ${ISO_LIST_URL}" >&2
  exit 1
fi

iso_path="${ISO_DIR}/${iso_name}"
sig_path="${iso_path}.sig"
sha_path="${ISO_DIR}/sha256sums.txt"

if [[ -f "${iso_path}" ]]; then
  echo "Already present: ${iso_path}"
else
  echo "Downloading ${iso_name} …"
  curl -fL --progress-bar -o "${iso_path}.part" "${ISO_LIST_URL}${iso_name}"
  mv "${iso_path}.part" "${iso_path}"
fi

echo "Fetching checksums …"
curl -fsSL -o "${sha_path}" "${ISO_LIST_URL}sha256sums.txt"

expected="$(grep " ${iso_name}\$" "${sha_path}" | awk '{print $1}' || true)"
if [[ -z "${expected}" ]]; then
  echo "Warning: no sha256 entry for ${iso_name} in sha256sums.txt" >&2
else
  echo "Verifying sha256 …"
  actual="$(sha256sum "${iso_path}" | awk '{print $1}')"
  if [[ "${actual}" != "${expected}" ]]; then
    echo "Checksum mismatch for ${iso_name}" >&2
    echo "  expected: ${expected}" >&2
    echo "  actual:   ${actual}" >&2
    exit 1
  fi
  echo "Checksum OK."
fi

# Optional detached signature (verification left to user / pacman-key)
if [[ ! -f "${sig_path}" ]]; then
  curl -fsSL -o "${sig_path}" "${ISO_LIST_URL}${iso_name}.sig" || \
    echo "Note: .sig not downloaded (optional)."
fi

# Convenience symlink for run.sh
ln -sfn "${iso_name}" "${ISO_DIR}/archlinux-x86_64.iso"

echo
echo "ISO ready: ${iso_path}"
echo "Symlink:   ${ISO_DIR}/archlinux-x86_64.iso -> ${iso_name}"
