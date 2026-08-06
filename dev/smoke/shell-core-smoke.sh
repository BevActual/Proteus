#!/usr/bin/env bash
# shell-core-smoke — proteus-shell-core (OWNED-STACK rung 0) parity gates.
#
# QML spine (Config.qml / EnvGate.qml / ShellState.qml) retired — schema and
# gating live in this crate; Settings UI is the iced sibling.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CRATE="${ROOT}/services/proteus-shell-core"
fail=0
ok() { echo "shell-core-smoke: OK $*"; }
die() { echo "shell-core-smoke: FAIL $*" >&2; fail=1; }

[[ -f "${CRATE}/Cargo.toml" ]] || die "missing services/proteus-shell-core"
grep -q 'cfg(test)' "${CRATE}/src/tokens.rs" || die "tokens module missing unit tests"
grep -q 'cfg(test)' "${CRATE}/src/facts.rs" || die "facts module missing unit tests"
grep -q 'include_str!.*chrome-tokens.json' "${CRATE}/src/tokens.rs" \
  || die "tokens must golden-pin env/chrome artifacts"
ok "crate + unit tests present"

CORE=""
for cand in \
  "${CRATE}/bin/proteus-shell-core" \
  "${CRATE}/target/release/proteus-shell-core" \
  "${CRATE}/target/debug/proteus-shell-core"; do
  [[ -x "${cand}" ]] && { CORE="${cand}"; break; }
done
if [[ -z "${CORE}" ]]; then
  ok "binary not built — runtime parity checks skipped (cargo build --release)"
  [[ $fail -eq 0 ]] || { echo "shell-core-smoke: FAILED" >&2; exit 1; }
  echo "shell-core-smoke: OK"
  exit 0
fi

# Schema keys are the SoT (Config.qml retired) — must be non-empty and stable.
core_keys="$("${CORE}" schema-keys)"
key_count="$(wc -l <<<"${core_keys}" | tr -d ' ')"
[[ "${key_count}" -ge 80 ]] \
  && ok "settings schema-keys (${key_count})" \
  || die "schema-keys too small (${key_count})"

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
install -d "${tmp}/proteus"
echo "couch" > "${tmp}/proteus/posture"
cp "${ROOT}/dev/fixtures/hw-probe.sample.json" "${tmp}/proteus/hw-probe.json"
cp "${ROOT}/dev/fixtures/settings.minimal.json" "${tmp}/proteus/settings.json"
facts_out="$("${CORE}" facts --config "${tmp}")"
python3 - "${facts_out}" <<'PY' || die "facts JSON shape"
import json, sys
d = json.loads(sys.argv[1])
assert d["schema"] == "proteus.shell.facts/v0", d
assert d["posture"] == "console", "couch must normalize to console"
assert d["probeReady"] is True and d["deviceClass"] == "desktop", d
assert "display" in d["capabilities"], d
assert d["settingsPresent"] is True and d["settingsProblems"] == [], d
print("facts ok")
PY
ok "facts normalizes fixtures (couch→console, caps, settings valid)"

empty_out="$("${CORE}" facts --config "${tmp}/nope")"
echo "${empty_out}" | grep -q '"posture":"desktop"' || die "missing facts must default desktop"
echo "${empty_out}" | grep -q '"probeReady":false' || die "missing probe must not claim ready"
ok "facts fails open without fact files"

SETTINGS_CATALOG="${ROOT}/env/settings/catalog.json"
[[ -f "${SETTINGS_CATALOG}" ]] || die "missing env/settings/catalog.json"
hubs="$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["hubs"]))' "${SETTINGS_CATALOG}")"
[[ "${hubs}" -ge 15 ]] || die "settings catalog has ${hubs} hubs (expected >= 15)"
ok "settings catalog present (${hubs} hubs)"

if "${CORE}" gate matrix "${ROOT}/dev/fixtures/gate-matrix.json" \
    --catalog "${ROOT}/env/apps/catalog.json" \
    --settings-catalog "${SETTINGS_CATALOG}" >/dev/null; then
  ok "gate matrix passes ($(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["cases"]))' "${ROOT}/dev/fixtures/gate-matrix.json") cases)"
else
  die "gate matrix mismatch"
fi
gate_out="$("${CORE}" gate app steam --posture host --caps display --probe-ready 1 \
  --catalog "${ROOT}/env/apps/catalog.json" --settings-catalog "${SETTINGS_CATALOG}")"
echo "${gate_out}" | grep -q '"available":false' || die "gate app posture block failed"
pane_out="$("${CORE}" gate pane sound --posture desktop --caps display --probe-ready 1 \
  --catalog "${ROOT}/env/apps/catalog.json" --settings-catalog "${SETTINGS_CATALOG}")"
echo "${pane_out}" | grep -q 'available' || die "gate pane output hollow"
ok "gate app + gate pane respond"

OPEN="${CORE%/*}/proteus-open"
if [[ -x "${OPEN}" ]]; then
  tab_err="$(env -i PATH=/nonexistent PROTEUS_ROOT=/nonexistent "${OPEN}" workloads --tab bogus 2>&1 || true)"
  grep -q 'unknown workloads tab' <<<"${tab_err}" || die "proteus-open must reject bad --tab"
  set_err="$(env -i PATH=/nonexistent PROTEUS_ROOT=/nonexistent "${OPEN}" settings 2>&1 || true)"
  grep -q 'proteus-settings not found' <<<"${set_err}" || die "proteus-open settings must fail loudly"
  ok "proteus-open validates tabs + fails loudly"
else
  ok "proteus-open not built — launcher runtime checks skipped"
fi

serve_line="$(timeout 5 "${CORE}" serve --config "${tmp}" | head -n 1 || true)"
python3 - "${serve_line}" <<'PY' || die "serve first NDJSON line invalid"
import json, sys
d = json.loads(sys.argv[1])
assert d["schema"] == "proteus.shell.facts/v0", d
print("serve ok")
PY
ok "serve emits a facts line on start"

# Owned shell launches Settings/Workloads via platform helpers / proteus-open
grep -q 'proteus-open\|proteus-settings\|OpenSettings' \
  "${ROOT}/shell/src/platform.rs" "${ROOT}/shell/src/surfaces.rs" "${ROOT}/shell/src/main.rs" \
  && ok "owned shell Settings launch path" \
  || die "owned shell missing Settings launch"

[[ $fail -eq 0 ]] || { echo "shell-core-smoke: FAILED" >&2; exit 1; }
echo "shell-core-smoke: OK"
