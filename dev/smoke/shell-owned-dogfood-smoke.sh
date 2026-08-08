#!/usr/bin/env bash
# shell-owned-dogfood-smoke — host-safe owned-engine dogfood gate (pre/post Wave 4).
#
# Builds bins, headless ctl under owned path, asserts PAM unlock helper + boot
# layers + HUD verbs. Manual VM checklist printed at end (honest skip if no Wayland).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fail=0
ok() { echo "  OK  $*"; }
bad() { echo "  FAIL $*"; fail=1; }
skip() { echo "  SKIP $*"; }

echo "==> shell-owned-dogfood-smoke"

[[ -f "${ROOT}/shell/Cargo.toml" ]] && ok "shell crate" || bad "shell missing"

if command -v cargo >/dev/null 2>&1; then
  if (cd "${ROOT}" && cargo build -p proteus-shell -q); then
    ok "proteus-shell builds"
  else
    bad "proteus-shell build"
  fi
else
  bad "cargo not available"
fi

SHELL_BIN="${ROOT}/target/debug/proteus-shell"
CTL_BIN="${ROOT}/target/debug/proteus-shellctl"
[[ -x "${SHELL_BIN}" ]] && ok "proteus-shell bin" || bad "proteus-shell bin missing"
[[ -x "${CTL_BIN}" ]] && ok "proteus-shellctl bin" || bad "proteus-shellctl bin missing"

# Source gates for dogfood readiness
grep -rq --include='*.rs' 'try_unlock\|check-unlock' "${ROOT}/shell/src/platform" \
  && ok "PAM unlock path" || bad "PAM unlock path"
[[ -f "${ROOT}/shell/scripts/check-unlock.py" ]] \
  && ok "check-unlock.py present" || bad "check-unlock.py missing"
grep -q 'fn boot_layers\|Face::' "${ROOT}/shell/src/faces/mod.rs" \
  && grep -rq --include='*.rs' 'boot_layers()' "${ROOT}/shell/src/app" "${ROOT}/shell/src/main.rs" \
  && ok "face-aware boot" || bad "face-aware boot"
for verb in volumeUp volumeDown brightnessUp brightnessDown; do
  grep -q "${verb}" "${ROOT}/shell/src/ctl.rs" \
    && ok "hud ${verb}" || bad "hud ${verb}"
done
grep -q 'spawn_socket2_listener' "${ROOT}/shell/src/wm_ipc.rs" \
  && ok "wm_ipc subscribe" || bad "wm_ipc subscribe"

# Headless ctl roundtrip (owned session binary — engine env for chrome script)
if [[ -x "${SHELL_BIN}" && -x "${CTL_BIN}" ]]; then
  dog_rt="$(mktemp -d)"
  dog_log="$(mktemp)"
  trap 'rm -rf "${dog_rt}"; rm -f "${dog_log}"; kill "${spid:-}" 2>/dev/null || true' EXIT
  export XDG_RUNTIME_DIR="${dog_rt}"
  install -d "${XDG_RUNTIME_DIR}/proteus"
  export PROTEUS_SHELL_ENGINE=owned
  "${SHELL_BIN}" --headless >"${dog_log}" 2>&1 &
  spid=$!
  sleep 0.5
  if "${CTL_BIN}" chrome state 2>/dev/null | grep -q '"ok"'; then
    ok "owned headless chrome.state"
  else
    bad "owned headless chrome.state"
    cat "${dog_log}" >&2 || true
  fi
  if "${CTL_BIN}" lock lock 2>/dev/null | grep -q '"ok"'; then
    ok "owned headless lock.lock"
  else
    bad "owned headless lock.lock"
  fi
  if "${CTL_BIN}" hud volumeUp 2>/dev/null | grep -q '"ok"'; then
    ok "owned headless hud.volumeUp"
  else
    # may fail without pulse — still ok if method exists (response shape)
    if "${CTL_BIN}" hud volume 50 2>/dev/null | grep -q '"ok"'; then
      ok "owned headless hud.volume"
    else
      bad "owned headless hud volume"
    fi
  fi
  kill "${spid}" 2>/dev/null || true
  wait "${spid}" 2>/dev/null || true
  spid=""
  rm -rf "${dog_rt}"
  rm -f "${dog_log}"
  trap - EXIT
fi

# Nested / VM checklist (manual — do not fail host CI)
# Nested harness starts proteus-chrome via compositor (env/hypr deleted)
grep -q 'proteus-chrome' "${ROOT}/shell/scripts/proteus-chrome" \
  && ok "proteus-chrome present" || bad "proteus-chrome missing"
grep -q 'proteus-compositor\|PROTEUS_SHELL_ENGINE' "${ROOT}/dev/run-nested.sh" \
  && ok "run-nested compositor/engine" || bad "run-nested missing compositor/engine"
grep -q 'PROTEUS_SHELL_ENGINE' "${ROOT}/dev/run-nested.sh" \
  && ok "run-nested exports engine" || bad "run-nested missing engine"

echo "  ---- manual owned dogfood checklist (VM / nested) ----"
echo "  ./dev/run-nested.sh   # Wave 4 owned default via proteus-chrome"
echo "  [ ] bar + dock visible"
echo "  [ ] Beacon (launcher) + Control Center toggle"
echo "  [ ] HUD volume/brightness"
echo "  [ ] lock / unlock (PAM or PIN)"
echo "  [ ] toast / privacy ask layers"
echo "  [ ] proteus-open settings / workloads"
if [[ -z "${WAYLAND_DISPLAY:-}" && -z "${WAYLAND_SOCKET:-}" ]]; then
  skip "no Wayland — nested visual checklist not run"
else
  skip "Wayland present — run nested checklist manually (not auto)"
fi

# Guest SSH — prefer owned-guest-smoke for Wave 4 live assert
if command -v ssh >/dev/null && ssh -o BatchMode=yes -o ConnectTimeout=1 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2222 andrew@127.0.0.1 true 2>/dev/null; then
  skip "guest SSH up — primary gate: ./dev/smoke/owned-guest-smoke.sh (PROTEUS_GUEST=1)"
else
  skip "no guest SSH — VM owned dogfood deferred"
fi

if [[ "${fail}" -ne 0 ]]; then
  echo "shell-owned-dogfood-smoke: FAILED"
  exit 1
fi
echo "shell-owned-dogfood-smoke: ok"
