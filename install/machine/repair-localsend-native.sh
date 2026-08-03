#!/usr/bin/env bash
# Repair empty libs from interrupted localsend-bin install, then install the
# already-built package. Leave this terminal open until OK.
set -euo pipefail

PKG="${HOME}/.cache/yay/localsend-bin/localsend-bin-1.17.0-1-x86_64.pkg.tar.zst"

echo "=== Repair corrupted deps (empty .so from killed VM) ==="
sudo pacman -S --noconfirm --needed \
  fuse2 \
  libayatana-appindicator \
  libayatana-indicator \
  libdbusmenu-glib \
  libdbusmenu-gtk3

echo
echo "=== Install built localsend-bin ==="
if [[ ! -f "${PKG}" ]]; then
  echo "Built package missing — running yay…"
  yay -S --needed localsend-bin
else
  sudo pacman -U --noconfirm "${PKG}"
fi

echo
echo "=== Verify ==="
pacman -Q localsend-bin
real="$(readlink -f "$(command -v localsend)")"
ls -la "${real}"
sz="$(stat -c%s "${real}")"
if [[ "${sz}" -lt 1024 ]]; then
  echo "FAIL: binary still empty" >&2
  exit 1
fi
# Fuse lib must be non-empty too
fsz="$(stat -c%s /usr/lib/libfuse.so.2.9.9)"
if [[ "${fsz}" -lt 1024 ]]; then
  echo "FAIL: libfuse still empty — re-run pacman -S fuse2" >&2
  exit 1
fi
echo "OK — localsend-bin installed (binary ${sz} bytes, libfuse ${fsz} bytes)."
echo
read -r -p "Press Enter to close…" _
