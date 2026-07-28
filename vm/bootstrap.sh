#!/usr/bin/env bash
# Host helper: run the Proteus overlay installer on a reachable guest over SSH.
#
# Prerequisites:
#   ./vm/run.sh              # guest booted, sshd up
#   Base Arch already installed (./vm/run.sh install + guest-install, or manual)
#   SSH key auth for PROTEUS_GUEST_USER (password prompts are not used here)
#
# Usage:
#   ./vm/bootstrap.sh
#   PROTEUS_GUEST_USER=andrew ./vm/bootstrap.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "${ROOT}/vm/lib.sh"
proteus_vm_ensure_dirs

HOST="${PROTEUS_GUEST_HOST:-127.0.0.1}"
PORT="${PROTEUS_GUEST_PORT:-${PROTEUS_VM_SSH_PORT:-2222}}"
USER="${PROTEUS_GUEST_USER:-andrew}"

ssh_opts=(
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o ConnectTimeout=5
  -o BatchMode=yes
  -o PreferredAuthentications=publickey
  -p "${PORT}"
)

echo "vm/bootstrap: waiting for SSH ${USER}@${HOST}:${PORT} (publickey) …"
ready=0
for _ in $(seq 1 60); do
  if ssh "${ssh_opts[@]}" "${USER}@${HOST}" 'echo OK' >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 2
done
if [[ "${ready}" -ne 1 ]]; then
  echo "vm/bootstrap: FAIL SSH unreachable (BatchMode/publickey only)" >&2
  echo "  Boot the guest, finish base Arch, enable sshd, then:" >&2
  echo "    ssh-copy-id -p ${PORT} ${USER}@${HOST}" >&2
  echo "  or install a key during guest-install. Password auth is not polled" >&2
  echo "  (avoids hanging this script on interactive prompts)." >&2
  exit 1
fi

echo "vm/bootstrap: ensuring /mnt/proteus …"
ssh "${ssh_opts[@]}" "${USER}@${HOST}" 'bash -s' <<'EOF'
set -euo pipefail
sudo mkdir -p /mnt/proteus
if ! mountpoint -q /mnt/proteus; then
  sudo mount -t 9p -o trans=virtio,version=9p2000.L,msize=262144 proteus /mnt/proteus \
    || sudo systemctl start mnt-proteus.mount
fi
test -f /mnt/proteus/vm/install/bootstrap.sh
EOF

echo "vm/bootstrap: running overlay (sudo) …"
# Pass install knobs through SSH with safe remote quoting
q_env() {
  # shellcheck disable=SC2086
  printf '%q' "$1"
}

remote_cmd="sudo env"
remote_cmd+=" PROTEUS_INSTALL_DESKTOP=$(q_env "${PROTEUS_INSTALL_DESKTOP:-1}")"
remote_cmd+=" PROTEUS_INSTALL_RESUME=$(q_env "${PROTEUS_INSTALL_RESUME:-0}")"
remote_cmd+=" PROTEUS_USER=$(q_env "${USER}")"
[[ -n "${PROTEUS_INSTALL_SKIP:-}" ]] && \
  remote_cmd+=" PROTEUS_INSTALL_SKIP=$(q_env "${PROTEUS_INSTALL_SKIP}")"
[[ -n "${PROTEUS_INSTALL_ONLY:-}" ]] && \
  remote_cmd+=" PROTEUS_INSTALL_ONLY=$(q_env "${PROTEUS_INSTALL_ONLY}")"
remote_cmd+=" bash /mnt/proteus/vm/install/bootstrap.sh"

# -t for sudo password if needed; auth itself is still publickey
ssh -t "${ssh_opts[@]}" "${USER}@${HOST}" "${remote_cmd}"

echo
echo "vm/bootstrap: OK — reboot guest, then on host:"
echo "  ./vm/run.sh snapshot hyprland-base"
echo "  PROTEUS_GUEST=1 ./scripts/smoke-all.sh"
