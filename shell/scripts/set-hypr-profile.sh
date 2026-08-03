#!/usr/bin/env bash
# Soft-select active Hyprland posture profile and reload (not a hard posture switch).
# Usage: set-hypr-profile.sh desktop|console|media|host|home
#   media ≡ console (legacy alias; profile file is console.conf)
# Hard switches: shell/scripts/proteus-posture · docs/proteus/POSTURES.md
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
if [[ -n "${PROTEUS_ROOT:-}" && -d "${PROTEUS_ROOT}/env/hypr" ]]; then
  ROOT="${PROTEUS_ROOT}"
elif [[ -d "${HERE}/../../env/hypr" ]]; then
  ROOT="$(cd "${HERE}/../.." && pwd)"
elif [[ -d /mnt/proteus/env/hypr ]]; then
  ROOT=/mnt/proteus
else
  ROOT="${PROTEUS_ROOT:-/mnt/proteus}"
fi
HYPR_DIR="${HOME}/.config/hypr"
PROFILES_DIR="${HYPR_DIR}/profiles"
POINTER="${HYPR_DIR}/proteus-profile.conf"
NAME="${1:-}"
PROFILES=(desktop console host home)

usage() {
  echo "usage: $0 desktop|console|media|host|home" >&2
  exit 2
}

[[ -n "${NAME}" ]] || usage
case "${NAME}" in
  media) NAME=console ;;
  desktop|console|host|home) ;;
  *) usage ;;
esac

mkdir -p "${PROFILES_DIR}"

# Seed profile files if missing
for p in "${PROFILES[@]}"; do
  src="${ROOT}/env/hypr/profiles/${p}.conf"
  dest="${PROFILES_DIR}/${p}.conf"
  if [[ -f "${src}" && ! -f "${dest}" ]]; then
    install -m 644 "${src}" "${dest}"
  fi
done

# Migrate legacy media.conf → console.conf (pointer + on-disk stub)
if [[ -f "${PROFILES_DIR}/media.conf" && ! -f "${PROFILES_DIR}/console.conf" ]]; then
  mv "${PROFILES_DIR}/media.conf" "${PROFILES_DIR}/console.conf"
  echo "Migrated profiles/media.conf → profiles/console.conf"
elif [[ -f "${ROOT}/env/hypr/profiles/console.conf" ]]; then
  # Refresh seeded console.conf when present in tree (dogfood 9p)
  install -m 644 "${ROOT}/env/hypr/profiles/console.conf" "${PROFILES_DIR}/console.conf"
fi

if [[ -f "${POINTER}" ]] && grep -q 'profiles/media\.conf' "${POINTER}" 2>/dev/null; then
  sed -i 's|profiles/media\.conf|profiles/console.conf|g' "${POINTER}"
  echo "Migrated proteus-profile.conf pointer media → console"
fi

if [[ ! -f "${PROFILES_DIR}/${NAME}.conf" ]]; then
  echo "missing profile: ${PROFILES_DIR}/${NAME}.conf (seed from env/hypr/profiles/)" >&2
  exit 1
fi

cat > "${POINTER}" <<EOF
# Active Hyprland posture profile pointer (files remain SoT).
# Written by set-hypr-profile.sh ${NAME}
# Reload: hyprctl reload
# Hard posture flip: proteus-posture (chrome + this pointer)

source = ~/.config/hypr/profiles/${NAME}.conf
EOF

echo "Active profile → ${NAME} (${POINTER})"

if command -v hyprctl >/dev/null 2>&1; then
  if hyprctl reload >/dev/null 2>&1; then
    echo "hyprctl reload OK"
  else
    echo "hyprctl reload failed (session may be inactive) — pointer updated on disk"
  fi
else
  echo "hyprctl not found — pointer updated; reload when Hyprland is running"
fi
