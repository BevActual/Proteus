#!/usr/bin/env bash
# Soft-select active Hyprland posture profile and reload (not a hard posture switch).
# Usage: set-hypr-profile.sh desktop|console|media|host|home
#   console ≡ media (legacy profile filename media.conf)
# Hard switches: docs/proteus/POSTURES.md
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HYPR_DIR="${HOME}/.config/hypr"
PROFILES_DIR="${HYPR_DIR}/profiles"
POINTER="${HYPR_DIR}/proteus-profile.conf"
NAME="${1:-}"
PROFILES=(desktop media host home)

usage() {
  echo "usage: $0 desktop|console|media|host|home" >&2
  exit 2
}

[[ -n "${NAME}" ]] || usage
case "${NAME}" in
  console) NAME=media ;;
  desktop|media|host|home) ;;
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

if [[ ! -f "${PROFILES_DIR}/${NAME}.conf" ]]; then
  echo "missing profile: ${PROFILES_DIR}/${NAME}.conf (seed from env/hypr/profiles/)" >&2
  exit 1
fi

cat > "${POINTER}" <<EOF
# Active Hyprland posture profile pointer (files remain SoT).
# Written by set-hypr-profile.sh ${NAME}
# Reload: hyprctl reload

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
