#!/usr/bin/env bash
# compositor-game-present.sh — owned game-present + focus-stack ctl smoke.
#
# Env:
#   PROTEUS_COMPOSITOR_SOCK  — ctl socket (required)
#   PROTEUS_COMPOSITORCTL    — optional path to proteus-compositorctl
#
# Exit 0 — dispatch/query OK
# Exit 1 — hard failure
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CTL="${PROTEUS_COMPOSITORCTL:-${ROOT}/target/debug/proteus-compositorctl}"

if [[ -z "${PROTEUS_COMPOSITOR_SOCK:-}" || ! -S "${PROTEUS_COMPOSITOR_SOCK}" ]]; then
  echo "compositor-game-present: PROTEUS_COMPOSITOR_SOCK missing/not a socket" >&2
  exit 1
fi
if [[ ! -x "${CTL}" ]]; then
  echo "compositor-game-present: proteus-compositorctl missing at ${CTL}" >&2
  exit 1
fi

json_ok() {
  python3 -c "import json,sys; d=json.loads(sys.stdin.read()); sys.exit(0 if d.get('ok') is True or d.get('ok') is None else 1)" 2>/dev/null
}

# Query surface
st="$("${CTL}" game-present 2>/dev/null || true)"
echo "${st}" | grep -q 'scale_mode\|fps_limit\|filter' \
  || { echo "compositor-game-present: bad game-present query: ${st}" >&2; exit 1; }

fs="$("${CTL}" focus-stack 2>/dev/null || true)"
echo "${fs}" | grep -q 'layer' \
  || { echo "compositor-game-present: bad focus-stack query: ${fs}" >&2; exit 1; }

# Policy knobs (no mapped client required)
for verb in \
  "game-present scale integer" \
  "game-present scale stretch" \
  "game-present scale fill" \
  "game-present fps 0" \
  "game-present filter nearest" \
  "game-present reload" \
  "focus-stack clear"; do
  out="$("${CTL}" dispatch ${verb} 2>/dev/null || true)"
  echo "${out}" | grep -q '"ok":\s*true\|"ok":true' \
    || { echo "compositor-game-present: dispatch failed: ${verb} → ${out}" >&2; exit 1; }
done

# Unit math for present_dst_rect lives in game_present.rs cargo tests.
echo "compositor-game-present: OK"
exit 0
