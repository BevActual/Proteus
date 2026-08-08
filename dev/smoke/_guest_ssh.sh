# Shared guest SSH helpers for desktop smokes / dogfood.
# Source from a smoke:  # shellcheck source=dev/smoke/_guest_ssh.sh
#   source "$(dirname "${BASH_SOURCE[0]}")/_guest_ssh.sh"
#
# Env (optional): PROTEUS_GUEST_HOST · PROTEUS_GUEST_PORT · PROTEUS_GUEST_USER · PROTEUS_GUEST
#
# Sets: PROTEUS_GUEST_SSH_HOST · PROTEUS_GUEST_SSH_PORT · PROTEUS_GUEST_SSH_USER · PROTEUS_GUEST_SSH_OPTS
# Functions:
#   proteus_guest_ssh_init          — fill host/port/user/opts
#   proteus_guest_ssh_reachable     — exit 0 if BatchMode SSH works
#   proteus_guest_ssh_require_or_skip <label>
#       — if unreachable: FAIL when PROTEUS_GUEST=1, else print SKIP and exit 0
#   proteus_guest_ssh <remote…>     — ssh with shared opts

proteus_guest_ssh_init() {
  PROTEUS_GUEST_SSH_HOST="${PROTEUS_GUEST_HOST:-127.0.0.1}"
  PROTEUS_GUEST_SSH_PORT="${PROTEUS_GUEST_PORT:-2222}"
  PROTEUS_GUEST_SSH_USER="${PROTEUS_GUEST_USER:-andrew}"
  PROTEUS_GUEST_SSH_OPTS=(
    -o StrictHostKeyChecking=no
    -o UserKnownHostsFile=/dev/null
    -o BatchMode=yes
    -o ConnectTimeout=3
    -o IgnoreUnknown=AddKeysToAgent,IdentityAgent
    -F /dev/null
    -p "${PROTEUS_GUEST_SSH_PORT}"
  )
}

proteus_guest_ssh_reachable() {
  proteus_guest_ssh_init
  ssh "${PROTEUS_GUEST_SSH_OPTS[@]}" \
    "${PROTEUS_GUEST_SSH_USER}@${PROTEUS_GUEST_SSH_HOST}" 'echo SSH_OK' >/dev/null 2>&1
}

proteus_guest_ssh_require_or_skip() {
  local label="${1:-guest-smoke}"
  proteus_guest_ssh_init
  if proteus_guest_ssh_reachable; then
    return 0
  fi
  if [[ "${PROTEUS_GUEST:-0}" == "1" ]]; then
    echo "${label}: FAIL SSH ${PROTEUS_GUEST_SSH_USER}@${PROTEUS_GUEST_SSH_HOST}:${PROTEUS_GUEST_SSH_PORT} unreachable (PROTEUS_GUEST=1)" >&2
    exit 1
  fi
  echo "${label}: SKIP guest SSH unreachable (set PROTEUS_GUEST=1 to require)"
  exit 0
}

proteus_guest_ssh() {
  proteus_guest_ssh_init
  ssh "${PROTEUS_GUEST_SSH_OPTS[@]}" \
    "${PROTEUS_GUEST_SSH_USER}@${PROTEUS_GUEST_SSH_HOST}" "$@"
}
