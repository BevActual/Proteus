#!/usr/bin/env bash
# console-smoke — Console Phase 1 seat/caps + Phase 2 session (host static)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fail=0
ok() { echo "console-smoke: OK $*"; }
die() { echo "console-smoke: FAIL $*" >&2; fail=1; }

SEAT="${ROOT}/shell/scripts/proteus-console-seat"
CAPS="${ROOT}/shell/scripts/proteus-console-capabilities"
LAUNCH="${ROOT}/shell/scripts/proteus-console-launch"
SESSION="${ROOT}/shell/scripts/proteus-console-session"
SHELF="${ROOT}/shell/surfaces/console/ConsoleShelf.qml"
LEAN="${ROOT}/shell/surfaces/console/ConsoleLeanSheet.qml"
HOME_QML="${ROOT}/shell/surfaces/console/ConsoleHome.qml"
BAR="${ROOT}/shell/surfaces/console/ConsoleBar.qml"
LIB="${ROOT}/shell/surfaces/console/ConsoleLibrary.qml"
APPS="${ROOT}/vm/install/apps.sh"
CONSOLE="${ROOT}/vm/install/console.sh"
APPLY="${ROOT}/vm/guest/apply-console-kit.sh"

for f in "${SEAT}" "${CAPS}" "${LAUNCH}" "${SESSION}" "${SHELF}" "${LEAN}" \
         "${HOME_QML}" "${BAR}" "${LIB}" "${APPS}" "${CONSOLE}" "${APPLY}"; do
  [[ -e "${f}" ]] || die "missing ${f#${ROOT}/}"
done
[[ -x "${SEAT}" && -x "${CAPS}" && -x "${LAUNCH}" && -x "${SESSION}" && -x "${APPLY}" ]] \
  || die "console helpers must be executable"
ok "files present"

grep -q 'ConsoleShelf' "${HOME_QML}" || die "ConsoleHome must use ConsoleShelf"
grep -q 'ConsoleLeanSheet' "${HOME_QML}" || die "ConsoleHome must use ConsoleLeanSheet"
grep -q 'peekScale\|shelfActive' "${SHELF}" || die "ConsoleShelf missing active/peek sizing"
grep -q 'proteus-console-seat' "${LIB}" || die "ConsoleLibrary missing proteus-console-seat"
grep -q 'toggleSessionMode\|sessionEffective' "${LIB}" \
  || die "ConsoleLibrary missing session mode wiring"
grep -q 'sessionToggleRequested\|sessionToggleVisible' "${BAR}" \
  || die "ConsoleBar missing session toggle"
grep -q 'onSessionToggleRequested' "${HOME_QML}" \
  || die "ConsoleHome must wire session toggle"
ok "shelf + Library + session UI wiring"

grep -q 'proteus-console-seat' "${APPS}" || die "apps.sh must install proteus-console-seat"
grep -q 'proteus-console-capabilities' "${APPS}" \
  || die "apps.sh must install proteus-console-capabilities"
grep -q 'proteus-console-launch' "${APPS}" || die "apps.sh must install proteus-console-launch"
grep -q 'proteus-console-session' "${APPS}" || die "apps.sh must install proteus-console-session"
grep -q 'proteus-console-session' "${APPLY}" || die "apply-console-kit must install session"
grep -q 'apply-console-kit' "${CONSOLE}" || die "console.sh must apply console kit"
grep -q 'proteus-console.packages' "${CONSOLE}" || die "console.sh must use proteus-console.packages"
ok "install wiring"

CAPS_JSON="$("${CAPS}" 2>/dev/null || true)"
echo "${CAPS_JSON}" | python3 -c 'import json,sys
d=json.load(sys.stdin)
for k in ("vulkan","gamescope","gamescopeUsable","isVm","steam","retroarch","pad",
          "sessionMode","sessionEffective","replacesHyprland"):
  assert k in d, k
assert d["replacesHyprland"] is False
assert d["sessionMode"] in ("seat","gamescope")
assert d["sessionEffective"] in ("seat","gamescope")
' || die "capabilities JSON keys"
ok "capabilities JSON"

bash -n "${SEAT}" || die "seat bash -n"
bash -n "${CAPS}" || die "caps bash -n"
bash -n "${LAUNCH}" || die "launch bash -n"
bash -n "${SESSION}" || die "session bash -n"
set +e
"${SEAT}" >/dev/null 2>&1
sec=$?
set -e
[[ "${sec}" -eq 2 ]] || die "seat usage should exit 2 (got ${sec})"

TMPHOME="$(mktemp -d)"
trap 'rm -rf "${TMPHOME}"' EXIT
export HOME="${TMPHOME}"
export XDG_CONFIG_HOME="${TMPHOME}/.config"
STATUS="$("${SESSION}" status 2>/dev/null || true)"
echo "${STATUS}" | python3 -c 'import json,sys
d=json.load(sys.stdin)
assert d.get("ok") is True
assert d.get("mode") == "seat"
assert d.get("replacesHyprland") is False
' || die "session status default"
"${SESSION}" set-mode gamescope >/dev/null
STATUS2="$("${SESSION}" status)"
echo "${STATUS2}" | python3 -c 'import json,sys
d=json.load(sys.stdin)
assert d.get("mode") == "gamescope"
' || die "session set-mode gamescope"
FLAGS="$("${SESSION}" resolve-flags || true)"
# Flags only when gamescopeUsable; host CI often has no Vulkan → empty OK.
if echo "${STATUS2}" | grep -q '"effective": "gamescope"'; then
  echo "${FLAGS}" | grep -q '\-f' || die "resolve-flags should include -f when effective"
fi
"${SESSION}" set-mode seat >/dev/null
ok "helpers syntax + session Fact"

grep -q 'resolve-flags\|proteus-console-session' "${LAUNCH}" \
  || die "launch must honor session resolve-flags"
ok "launch session wire"

[[ $fail -eq 0 ]] || { echo "console-smoke: FAILED" >&2; exit 1; }
echo "console-smoke: OK"
