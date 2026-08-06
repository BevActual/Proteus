#!/usr/bin/env bash
# Desktop conf seed — Hyprland fragments retired (env/hypr deleted).
# Soft no-op for hypr seeds; still installs optional lock PAM bits.
set -euo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)"

echo "install-desktop-conf: soft no-op (env/hypr deleted; Hyprland purged)"

# Session lock PAM for owned LockSurface (optional /etc copy)
PAM_SRC="${ROOT}/shell/pam/proteus-lock"
if [[ -f "${PAM_SRC}" ]]; then
  if [[ "$(id -u)" -eq 0 ]]; then
    install -m 644 "${PAM_SRC}" /etc/pam.d/proteus-lock
    echo "Installed /etc/pam.d/proteus-lock"
  else
    echo "Lock PAM: ${PAM_SRC} (auth helper uses login service). Optional: sudo install -m 644 ${PAM_SRC} /etc/pam.d/proteus-lock"
  fi
fi

# Lock auth uses shell/scripts/check-unlock.py (PAM password + optional unlock PIN)
echo "Desktop conf: PAM/lock only (no hypr fragments)"
