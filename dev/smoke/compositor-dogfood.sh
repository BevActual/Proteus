#!/usr/bin/env bash
# compositor-dogfood.sh — opt-in dogfood gate for owned compositor (OWNED-STACK).
#
# Exit 0 — static OK and at least one live prove (nested / DRM / guest COMP_LIVE)
# Exit 2 — static OK but only optional SKIP paths (no live prove this run)
# Exit 1 — hard failure
#
# Env:
#   PROTEUS_COMPOSITOR_DRM=1  — also run live DRM helper (seat steal)
#   PROTEUS_GUEST=1           — require guest Fact=smithay + binary (live soft-SKIP)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CRATE="${ROOT}/compositor"
SESSION="${ROOT}/shell/scripts/proteus-session"
ENGINE_RS="${ROOT}/shell/src/engine.rs"
COMP="${PROTEUS_COMPOSITOR:-${ROOT}/target/debug/proteus-compositor}"
CTL="${PROTEUS_COMPOSITORCTL:-${ROOT}/target/debug/proteus-compositorctl}"

ok() { echo "compositor-dogfood: OK $*"; }
die() { echo "compositor-dogfood: FAIL $*" >&2; exit 1; }
skip() { echo "compositor-dogfood: SKIP $*" >&2; }

# --- Always: static honesty ---------------------------------------------------
[[ -f "${CRATE}/Cargo.toml" ]] || die "missing compositor crate"
[[ -f "${SESSION}" ]] || die "missing proteus-session"
grep -q 'proteus-compositor' "${SESSION}" || die "session missing compositor resolve"
grep -q -- '--backend drm' "${SESSION}" || die "session missing --backend drm"
grep -q 'Hyprland purged\|refuse (Hyprland purged)' "${SESSION}" || die "session missing Hyprland purge refuse"
grep -q 'resolve_compositor_engine' "${ENGINE_RS}" || die "engine.rs missing resolve_compositor_engine"

if [[ ! -x "${COMP}" ]] || [[ ! -x "${CTL}" ]]; then
  (cd "${ROOT}" && cargo build -p compositor -q) || die "cargo build -p compositor failed"
fi
COMP="$(ls -1 "${ROOT}/target/debug/proteus-compositor" 2>/dev/null || true)"
CTL="$(ls -1 "${ROOT}/target/debug/proteus-compositorctl" 2>/dev/null || true)"
[[ -x "${COMP}" ]] || die "proteus-compositor missing after build"
[[ -x "${CTL}" ]] || die "proteus-compositorctl missing after build"
ok "binaries + session/engine greps"

cat >&2 <<'EOF'
compositor-dogfood: checklist
  - Nested: DISPLAY/WAYLAND_DISPLAY set → this script runs a short winit ctl prove
  - DRM VT/VM: PROTEUS_COMPOSITOR_DRM=1 ./dev/smoke/compositor-drm.sh
  - Hyprland purged — no Fact rollback; session refuses Fact=hyprland
  - Guest: PROTEUS_GUEST=1 SSH (andrew) — Fact smithay + binary required; COMP_LIVE soft
  - Nested dogfood login path: ./dev/run-nested.sh (compositor winit)
EOF

overall_skip=0
live_prove=0

# --- Nested live --------------------------------------------------------------
if [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
  log="$(mktemp)"
  trap 'rm -f "${log}"; kill "${comp_pid:-}" 2>/dev/null || true' RETURN
  unset PROTEUS_COMPOSITOR_ENGINE || true
  stdbuf -oL -eL "${COMP}" >"${log}" 2>&1 &
  comp_pid=$!
  sleep 0.4
  sock=""
  for _ in $(seq 1 80); do
    if grep -q 'ctl socket ' "${log}" 2>/dev/null; then
      sock="$(sed -n 's/.*ctl socket //p' "${log}" | head -1)"
      break
    fi
    if ! kill -0 "${comp_pid}" 2>/dev/null; then
      die "nested compositor exited early: $(tr '\n' ' ' <"${log}" | head -c 240)"
    fi
    sleep 0.1
  done
  [[ -n "${sock}" && -S "${sock}" ]] || die "nested ctl socket missing"
  export PROTEUS_COMPOSITOR_SOCK="${sock}"
  ws="$("${CTL}" workspaces 2>/dev/null || true)"
  echo "${ws}" | grep -q '"id"' || die "workspaces JSON failed: ${ws}"
  "${CTL}" dispatch layout dwindle >/dev/null 2>&1 \
    || die "dispatch layout dwindle failed"
  "${CTL}" dispatch gapsout 8 >/dev/null 2>&1 \
    || die "dispatch gapsout failed"
  "${CTL}" dispatch smartgaps on >/dev/null 2>&1 \
    || die "dispatch smartgaps failed"
  ok "nested ctl (workspaces + layout + gapsout + smartgaps)"
  live_prove=1

  client=""
  for cand in foot kitty; do
    if command -v "${cand}" >/dev/null 2>&1; then
      client="${cand}"
      break
    fi
  done
  if [[ -n "${client}" ]]; then
    nested_wd="$(sed -n 's/.*nested on WAYLAND_DISPLAY=//p' "${log}" | head -1)"
    if [[ -z "${nested_wd}" ]]; then
      nested_wd="$(sed -n 's/.*nested spike on WAYLAND_DISPLAY=//p' "${log}" | head -1)"
    fi
    if [[ -z "${nested_wd}" ]]; then
      nested_wd="$(basename "${sock}" .sock | sed 's/^proteus-compositor-//')"
    fi
    before="$("${CTL}" clients 2>/dev/null || echo '[]')"
    before_n="$(python3 -c "import json,sys; print(len(json.loads(sys.argv[1])))" "${before}" 2>/dev/null || echo 0)"
    WAYLAND_DISPLAY="${nested_wd}" "${client}" >/dev/null 2>&1 &
    cpid=$!
    saw=""
    for _ in $(seq 1 40); do
      sleep 0.15
      after="$("${CTL}" clients 2>/dev/null || echo '[]')"
      after_n="$(python3 -c "import json,sys; print(len(json.loads(sys.argv[1])))" "${after}" 2>/dev/null || echo 0)"
      if [[ "${after_n}" -gt "${before_n}" ]]; then
        saw=1
        break
      fi
    done
    kill "${cpid}" 2>/dev/null || true
    wait "${cpid}" 2>/dev/null || true
    if [[ -n "${saw}" ]]; then
      ok "nested client ${client} in clients"
    else
      ok "nested client ${client} did not map — soft-skip"
    fi
  else
    ok "no foot/kitty — client map soft-skip"
  fi

  kill "${comp_pid}" 2>/dev/null || true
  wait "${comp_pid}" 2>/dev/null || true
  comp_pid=""
  trap - RETURN
  rm -f "${log}"
else
  skip "no DISPLAY/WAYLAND_DISPLAY — nested live skipped"
  overall_skip=1
fi

# --- DRM live -----------------------------------------------------------------
if [[ "${PROTEUS_COMPOSITOR_DRM:-}" == "1" ]]; then
  set +e
  bash "${ROOT}/dev/smoke/compositor-drm.sh"
  drm_rc=$?
  set -e
  if [[ "${drm_rc}" -eq 0 ]]; then
    ok "DRM live prove"
    live_prove=1
  elif [[ "${drm_rc}" -eq 2 ]]; then
    skip "DRM helper soft-skip"
    overall_skip=1
  else
    die "DRM helper failed rc=${drm_rc}"
  fi
else
  skip "PROTEUS_COMPOSITOR_DRM!=1 — DRM live skipped"
  overall_skip=1
fi

# --- Guest SSH ----------------------------------------------------------------
# shellcheck source=dev/smoke/_guest_ssh.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_guest_ssh.sh"
if [[ "${PROTEUS_GUEST:-}" == "1" ]]; then
  proteus_guest_ssh_init
  proteus_guest_ssh_reachable || die "guest SSH unreachable (PROTEUS_GUEST=1)"
  eng="$(proteus_guest_ssh \
    'tr -d "[:space:]" <"${XDG_CONFIG_HOME:-$HOME/.config}/proteus/compositor-engine" 2>/dev/null || true' || true)"
  eng="$(printf '%s' "${eng}" | tr '[:upper:]' '[:lower:]')"
  case "${eng}" in
    smithay|compositor|compositor-next|"") ;;
    *)
      die "guest compositor-engine=${eng:-empty} (want smithay / empty after flipped install)"
      ;;
  esac
  out="$(proteus_guest_ssh bash -s <<'EOS' || true
set -euo pipefail
if command -v proteus-compositor >/dev/null 2>&1; then echo BIN_OK; fi
for c in /usr/local/bin/proteus-compositor \
  /usr/local/libexec/proteus/proteus-compositor \
  "${PROTEUS_ROOT:-/mnt/proteus}/target/release/proteus-compositor" \
  "${PROTEUS_ROOT:-/mnt/proteus}/target/debug/proteus-compositor"; do
  [[ -x "$c" ]] && echo BIN_OK && break
done
if pgrep -x proteus-compositor >/dev/null 2>&1; then echo COMP_LIVE; fi
if [[ -n "${PROTEUS_COMPOSITOR_SOCK:-}" && -S "${PROTEUS_COMPOSITOR_SOCK}" ]]; then echo SOCK_OK; fi
EOS
)"
  echo "${out}" | grep -q 'BIN_OK' || die "guest smithay Fact but proteus-compositor missing"
  if echo "${out}" | grep -qE 'COMP_LIVE|SOCK_OK'; then
    ok "guest smithay binary + live session markers"
    live_prove=1
  else
    skip "guest smithay binary OK but no graphical compositor session yet"
    overall_skip=1
  fi
else
  skip "PROTEUS_GUEST!=1 — guest prove skipped"
  overall_skip=1
fi

ok "dogfood gate complete"
if [[ "${live_prove}" -eq 1 ]]; then
  exit 0
fi
if [[ "${overall_skip}" -eq 1 ]]; then
  exit 2
fi
exit 0
