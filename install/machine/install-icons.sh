#!/usr/bin/env bash
# Install Proteus icons into the icon theme (hicolor).
# Root → /usr/share/icons/hicolor; otherwise → ~/.local/share/icons/hicolor
#
#   proteus.svg           — brand helix mark
#   proteus-settings.svg  — gear
#   proteus-launcher.svg  — telescope (Beacon)
set -euo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)"
BRAND="${ROOT}/brand"
MARK="${BRAND}/proteus-mark.svg"
SETTINGS_ICON="${BRAND}/proteus-settings.svg"
LAUNCHER_ICON="${BRAND}/proteus-launcher.svg"

if [[ ! -f "${MARK}" ]]; then
  echo "install-icons: missing ${MARK}" >&2
  exit 1
fi
if [[ ! -f "${SETTINGS_ICON}" || ! -f "${LAUNCHER_ICON}" ]]; then
  echo "install-icons: missing settings/launcher SVGs in ${BRAND}" >&2
  exit 1
fi

if [[ "${EUID}" -eq 0 ]] && [[ -w /usr/share/icons ]]; then
  BASE="/usr/share/icons/hicolor"
else
  BASE="${XDG_DATA_HOME:-${HOME}/.local/share}/icons/hicolor"
fi

SCALABLE="${BASE}/scalable/apps"
install -d "${SCALABLE}"
install -m 644 "${MARK}" "${SCALABLE}/proteus.svg"
# Distinct glyphs (do not alias to the brand mark)
install -m 644 "${SETTINGS_ICON}" "${SCALABLE}/proteus-settings.svg"
install -m 644 "${LAUNCHER_ICON}" "${SCALABLE}/proteus-launcher.svg"

rasterize() {
  local src="$1" out="$2" sz="$3"
  if command -v rsvg-convert >/dev/null 2>&1; then
    rsvg-convert -w "${sz}" -h "${sz}" "${src}" -o "${out}"
  elif command -v magick >/dev/null 2>&1; then
    magick -background none "${src}" -resize "${sz}x${sz}" "${out}"
  elif command -v convert >/dev/null 2>&1; then
    convert -background none "${src}" -resize "${sz}x${sz}" "${out}"
  else
    return 1
  fi
  chmod 644 "${out}"
}

for sz in 48 64 128 256; do
  dir="${BASE}/${sz}x${sz}/apps"
  install -d "${dir}"
  # Drop stale symlinks that used to point everything at proteus.png
  rm -f "${dir}/proteus-settings.png" "${dir}/proteus-launcher.png"
  rasterize "${MARK}" "${dir}/proteus.png" "${sz}" \
    || { [[ -f "${BRAND}/proteus-mark.png" ]] && magick "${BRAND}/proteus-mark.png" -resize "${sz}x${sz}" "${dir}/proteus.png"; }
  rasterize "${SETTINGS_ICON}" "${dir}/proteus-settings.png" "${sz}"
  rasterize "${LAUNCHER_ICON}" "${dir}/proteus-launcher.png" "${sz}"
done

if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -f -t "${BASE}" 2>/dev/null || true
fi

if command -v update-desktop-database >/dev/null 2>&1 && [[ -d /usr/share/applications ]]; then
  update-desktop-database /usr/share/applications 2>/dev/null || true
fi

echo "install-icons: OK → ${SCALABLE}/proteus{,-settings,-launcher}.svg"
