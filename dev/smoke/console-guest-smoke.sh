#!/usr/bin/env bash
# console-guest-smoke — guest console dogfood flip/verify (SSH).
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
    echo "console-guest-smoke: FAIL SSH ${USER}@${HOST}:${PORT} unreachable (PROTEUS_GUEST=1)" >&2
    exit 1
  fi
  echo "console-guest-smoke: SKIP guest SSH unreachable (set PROTEUS_GUEST=1 to require)"
  exit 0
fi

echo "console-guest-smoke: guest SSH OK — dogfood console flip + restore"

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

DOG="${PROTEUS_ROOT}/dev/dogfood/dogfood-console.sh"
[[ -x "${DOG}" ]] || { echo "FAIL dogfood-console.sh missing"; exit 1; }
bash -n "${DOG}" || { echo "FAIL dogfood-console.sh bash -n"; exit 1; }

# Helpers / caps before flip
for h in proteus-posture proteus-console-capabilities proteus-console-seat; do
  command -v "${h}" >/dev/null 2>&1 || [[ -x "${PROTEUS_ROOT}/shell/scripts/${h}" ]] \
    || [[ -x "${PROTEUS_ROOT}/install/machine/${h}" ]] \
    || { echo "FAIL helper ${h}"; exit 1; }
done
echo "OK helpers"

CAPS_JSON="$(proteus-console-capabilities 2>/dev/null || "${PROTEUS_ROOT}/shell/scripts/proteus-console-capabilities")"
echo "${CAPS_JSON}" | python3 -c 'import json,sys
d=json.load(sys.stdin)
for k in ("vulkan","gamescope","gamescopeUsable","sessionMode","sessionEffective","replacesHyprland"):
  assert k in d, k
assert d["replacesHyprland"] is False
' || { echo "FAIL capabilities JSON"; exit 1; }
echo "OK capabilities"

SESSION="${PROTEUS_ROOT}/shell/scripts/proteus-console-session"
if command -v proteus-console-session >/dev/null 2>&1; then
  SESSION="$(command -v proteus-console-session)"
fi
[[ -x "${SESSION}" ]] || { echo "FAIL proteus-console-session"; exit 1; }
ST="$("${SESSION}" status)"
echo "${ST}" | python3 -c 'import json,sys
d=json.load(sys.stdin)
assert d.get("ok") is True
assert d.get("mode") in ("seat","gamescope")
assert d.get("replacesHyprland") is False
' || { echo "FAIL session status"; exit 1; }
echo "OK session status"

# Prefer live Hyprland+QS; otherwise verify Fact/profile only via dogfood (may fail chrome).
if [[ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
  echo "FAIL no Hyprland instance"
  exit 1
fi

# Roundtrip: console → desktop
bash "${DOG}" || { echo "FAIL dogfood console"; exit 1; }
echo "OK dogfood console"
FACT="$(tr -d '[:space:]' <"${HOME}/.config/proteus/posture")"
[[ "${FACT}" == "console" ]] || { echo "FAIL posture after console=${FACT}"; exit 1; }
STATE="$(qs -p "${PROTEUS_ROOT}/shell" ipc call chrome state 2>/dev/null || true)"
echo "${STATE}" | python3 -c 'import json,sys
d=json.load(sys.stdin)
assert d.get("surface")=="console"
' || { echo "FAIL chrome surface after console: ${STATE}"; exit 1; }
echo "OK chrome console"

bash "${DOG}" --restore || { echo "FAIL dogfood restore"; exit 1; }
FACT2="$(tr -d '[:space:]' <"${HOME}/.config/proteus/posture")"
[[ "${FACT2}" == "desktop" ]] || { echo "FAIL posture after restore=${FACT2}"; exit 1; }
STATE2="$(qs -p "${PROTEUS_ROOT}/shell" ipc call chrome state 2>/dev/null || true)"
echo "${STATE2}" | python3 -c 'import json,sys
d=json.load(sys.stdin)
assert d.get("surface")=="desktop"
' || { echo "FAIL chrome surface after restore: ${STATE2}"; exit 1; }
echo "OK restore desktop"
echo CONSOLE_GUEST_OK
EOF
)" || {
  echo "console-guest-smoke: FAIL remote script" >&2
  echo "${out}" >&2
  exit 1
}

echo "${out}" | grep -q 'OK helpers' || { echo "console-guest-smoke: FAIL helpers" >&2; echo "${out}" >&2; exit 1; }
echo "${out}" | grep -q 'OK capabilities' || { echo "console-guest-smoke: FAIL capabilities" >&2; echo "${out}" >&2; exit 1; }
echo "${out}" | grep -q 'OK session status' || { echo "console-guest-smoke: FAIL session" >&2; echo "${out}" >&2; exit 1; }
echo "${out}" | grep -q 'OK dogfood console' || { echo "console-guest-smoke: FAIL flip" >&2; echo "${out}" >&2; exit 1; }
echo "${out}" | grep -q 'OK chrome console' || { echo "console-guest-smoke: FAIL chrome console" >&2; echo "${out}" >&2; exit 1; }
echo "${out}" | grep -q 'OK restore desktop' || { echo "console-guest-smoke: FAIL restore" >&2; echo "${out}" >&2; exit 1; }
echo "${out}" | grep -q 'CONSOLE_GUEST_OK' || { echo "console-guest-smoke: FAIL summary" >&2; echo "${out}" >&2; exit 1; }

echo "console-guest-smoke: OK"
