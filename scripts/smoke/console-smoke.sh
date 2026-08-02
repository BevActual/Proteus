#!/usr/bin/env bash
# console-smoke — Console Phase 1 shelf/seat/caps + install wiring (host static)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fail=0
ok() { echo "console-smoke: OK $*"; }
die() { echo "console-smoke: FAIL $*" >&2; fail=1; }

SEAT="${ROOT}/shell/scripts/proteus-console-seat"
CAPS="${ROOT}/shell/scripts/proteus-console-capabilities"
LAUNCH="${ROOT}/shell/scripts/proteus-console-launch"
SHELF="${ROOT}/shell/surfaces/console/ConsoleShelf.qml"
LEAN="${ROOT}/shell/surfaces/console/ConsoleLeanSheet.qml"
HOME_QML="${ROOT}/shell/surfaces/console/ConsoleHome.qml"
APPS="${ROOT}/vm/install/apps.sh"
CONSOLE="${ROOT}/vm/install/console.sh"
APPLY="${ROOT}/vm/guest/apply-console-kit.sh"

for f in "${SEAT}" "${CAPS}" "${LAUNCH}" "${SHELF}" "${LEAN}" "${HOME_QML}" \
         "${APPS}" "${CONSOLE}" "${APPLY}"; do
  [[ -e "${f}" ]] || die "missing ${f#${ROOT}/}"
done
[[ -x "${SEAT}" && -x "${CAPS}" && -x "${LAUNCH}" && -x "${APPLY}" ]] \
  || die "console helpers must be executable"
ok "files present"

grep -q 'ConsoleShelf' "${HOME_QML}" || die "ConsoleHome must use ConsoleShelf"
grep -q 'ConsoleLeanSheet' "${HOME_QML}" || die "ConsoleHome must use ConsoleLeanSheet"
grep -q 'peekScale\|shelfActive' "${SHELF}" || die "ConsoleShelf missing active/peek sizing"
grep -q 'proteus-console-seat' "${ROOT}/shell/surfaces/console/ConsoleLibrary.qml" \
  || die "ConsoleLibrary missing proteus-console-seat"
ok "shelf + Library wiring"

grep -q 'proteus-console-seat' "${APPS}" || die "apps.sh must install proteus-console-seat"
grep -q 'proteus-console-capabilities' "${APPS}" \
  || die "apps.sh must install proteus-console-capabilities"
grep -q 'proteus-console-launch' "${APPS}" || die "apps.sh must install proteus-console-launch"
grep -q 'apply-console-kit' "${CONSOLE}" || die "console.sh must apply console kit"
grep -q 'proteus-console.packages' "${CONSOLE}" || die "console.sh must use proteus-console.packages"
grep -q 'proteus-console-seat' "${APPLY}" || die "apply-console-kit must install seat"
ok "install wiring"

CAPS_JSON="$("${CAPS}" 2>/dev/null || true)"
echo "${CAPS_JSON}" | python3 -c 'import json,sys
d=json.load(sys.stdin)
for k in ("vulkan","gamescope","gamescopeUsable","isVm","steam","retroarch","pad"):
  assert k in d, k
' || die "capabilities JSON keys"
ok "capabilities JSON"

bash -n "${SEAT}" || die "seat bash -n"
bash -n "${CAPS}" || die "caps bash -n"
bash -n "${LAUNCH}" || die "launch bash -n"
set +e
"${SEAT}" >/dev/null 2>&1
sec=$?
set -e
[[ "${sec}" -eq 2 ]] || die "seat usage should exit 2 (got ${sec})"
ok "helpers syntax + usage"

[[ $fail -eq 0 ]] || { echo "console-smoke: FAILED" >&2; exit 1; }
echo "console-smoke: OK"
