#!/usr/bin/env bash
# Install the Proteus lock-screen PAM service to /etc/pam.d/proteus-lock.
#
# Without this the lock screen still works — check-password.py falls back to
# the "login" stack — but it bypasses whatever the distro configures in
# system-auth (faillock lockout, fail delay). Run once per guest.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC="${ROOT}/shell/pam/proteus-lock"
DEST="/etc/pam.d/proteus-lock"

if [[ ! -f "${SRC}" ]]; then
  echo "Missing ${SRC}" >&2
  exit 1
fi

if [[ ! -f /etc/pam.d/system-auth ]]; then
  echo "No /etc/pam.d/system-auth on this host — refusing to install a stack that would deny all auth." >&2
  echo "The lock screen will keep using the 'login' service." >&2
  exit 1
fi

SUDO=""
if [[ ${EUID} -ne 0 ]]; then
  SUDO="sudo"
fi

${SUDO} install -m 644 -o root -g root "${SRC}" "${DEST}"
echo "Installed ${DEST}"

# Fail loudly here rather than at the lock screen, where a broken stack means
# the user cannot get back into their session.
if command -v pamtester >/dev/null 2>&1; then
  echo "Verify with: pamtester proteus-lock \"${USER}\" authenticate"
else
  echo "Tip: install pamtester to verify before relying on it."
fi
echo "Rollback: ${SUDO} rm ${DEST}  (lock falls back to the 'login' service)"
