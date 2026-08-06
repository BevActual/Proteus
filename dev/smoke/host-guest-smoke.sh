#!/usr/bin/env bash
# host-guest-smoke — guest host dogfood flip/verify (SSH).
# Skip if SSH unreachable unless PROTEUS_GUEST=1 (then fail closed).
# Restores desktop posture so the guest stays usable for later smokes.
set -euo pipefail

HOST="${PROTEUS_GUEST_HOST:-127.0.0.1}"
PORT="${PROTEUS_GUEST_PORT:-2222}"
USER="${PROTEUS_GUEST_USER:-andrew}"
REQUIRE="${PROTEUS_GUEST:-0}"

ssh_opts=(
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o BatchMode=yes
  -o ConnectTimeout=3
  -p "${PORT}"
)

if ! ssh "${ssh_opts[@]}" "${USER}@${HOST}" 'echo SSH_OK' >/dev/null 2>&1; then
  if [[ "${REQUIRE}" == "1" ]]; then
    echo "host-guest-smoke: FAIL SSH ${USER}@${HOST}:${PORT} unreachable (PROTEUS_GUEST=1)" >&2
    exit 1
  fi
  echo "host-guest-smoke: SKIP guest SSH unreachable (set PROTEUS_GUEST=1 to require)"
  exit 0
fi

echo "host-guest-smoke: guest SSH OK — dogfood host flip + restore"

out="$(ssh "${ssh_opts[@]}" "${USER}@${HOST}" 'bash -s' <<'EOF'
set -euo pipefail
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
if [[ -d "${XDG_RUNTIME_DIR}/hypr" ]]; then
  export HYPRLAND_INSTANCE_SIGNATURE="$(ls "${XDG_RUNTIME_DIR}/hypr" | head -1)"
fi
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"
export PROTEUS_ROOT="${PROTEUS_ROOT:-/mnt/proteus}"
export PATH="/usr/local/bin:${PROTEUS_ROOT}/shell/scripts:${PROTEUS_ROOT}/install/machine:${PATH}"
export PROTEUS_SKIP_SESSION_LOCK=1

DOG="${PROTEUS_ROOT}/dev/dogfood/dogfood-host.sh"
[[ -x "${DOG}" ]] || { echo "FAIL dogfood-host.sh missing"; exit 1; }
bash -n "${DOG}" || { echo "FAIL dogfood-host.sh bash -n"; exit 1; }

for h in proteus-posture proteus-host-seat; do
  command -v "${h}" >/dev/null 2>&1 || [[ -x "${PROTEUS_ROOT}/install/machine/${h}" ]] \
    || { echo "FAIL helper ${h}"; exit 1; }
done
echo "OK helpers"

if [[ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
  echo "FAIL no Hyprland instance"
  exit 1
fi

bash "${DOG}" || { echo "FAIL dogfood host"; exit 1; }
echo "OK dogfood host"
FACT="$(tr -d '[:space:]' <"${HOME}/.config/proteus/posture")"
[[ "${FACT}" == "host" ]] || { echo "FAIL posture after host=${FACT}"; exit 1; }
HC="$(tr -d '[:space:]' <"${HOME}/.config/proteus/host-chrome")"
[[ "${HC}" == "none" ]] || { echo "FAIL host-chrome after dogfood=${HC}"; exit 1; }
echo "OK headless Fact"

bash "${DOG}" --restore || { echo "FAIL dogfood restore"; exit 1; }
FACT2="$(tr -d '[:space:]' <"${HOME}/.config/proteus/posture")"
[[ "${FACT2}" == "desktop" ]] || { echo "FAIL posture after restore=${FACT2}"; exit 1; }
STATE2="$(proteus-shellctl chrome state 2>/dev/null || true)"
echo "${STATE2}" | python3 -c 'import json,sys
d=json.load(sys.stdin)
r=d.get("result") if isinstance(d.get("result"), dict) else d
assert (r or {}).get("face")=="desktop"
' || { echo "FAIL chrome surface after restore: ${STATE2}"; exit 1; }
echo "OK restore desktop"
echo HOST_GUEST_OK
EOF
)" || {
  echo "host-guest-smoke: FAIL remote script" >&2
  echo "${out}" >&2
  exit 1
}

echo "${out}" | grep -q 'OK helpers' || { echo "host-guest-smoke: FAIL helpers" >&2; echo "${out}" >&2; exit 1; }
echo "${out}" | grep -q 'OK dogfood host' || { echo "host-guest-smoke: FAIL flip" >&2; echo "${out}" >&2; exit 1; }
echo "${out}" | grep -q 'OK headless Fact' || { echo "host-guest-smoke: FAIL headless" >&2; echo "${out}" >&2; exit 1; }
echo "${out}" | grep -q 'OK restore desktop' || { echo "host-guest-smoke: FAIL restore" >&2; echo "${out}" >&2; exit 1; }
echo "${out}" | grep -q 'HOST_GUEST_OK' || { echo "host-guest-smoke: FAIL summary" >&2; echo "${out}" >&2; exit 1; }

echo "host-guest-smoke: OK"
