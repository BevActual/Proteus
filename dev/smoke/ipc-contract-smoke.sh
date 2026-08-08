#!/usr/bin/env bash
# ipc-contract-smoke — proteus-shellctl targets/verbs stay wired in ctl.rs.
# Quickshell IpcHandler matrix retired with QML chrome.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

die() { echo "ipc-contract-smoke: FAIL $*" >&2; exit 1; }
ok() { echo "ipc-contract-smoke: OK $*"; }

CTL="${ROOT}/shell/src/ctl.rs"
LIB="${ROOT}/shell/src/lib.rs"
[[ -f "${CTL}" ]] || die "missing ${CTL}"
[[ -f "${LIB}" ]] || die "missing ${LIB}"

for t in lock chrome widgets hud; do
  grep -q "\"${t}\"" "${LIB}" || die "ipc target ${t} missing from lib.rs"
done
ok "ipc targets in lib.rs"

# Core verbs that smokes / keybinds rely on
grep -q 'launcher\|beacon' "${CTL}" || die "ctl missing launcher/beacon"
grep -qi 'control.center\|control_center\|controlCenter' "${CTL}" || die "ctl missing control center"
grep -q '"notifications"' "${CTL}" || die "ctl missing chrome notifications"
grep -q 'calendar\|weather' "${CTL}" || die "ctl missing calendar/weather"
grep -q 'widgets' "${CTL}" || die "ctl missing widgets"
grep -q '"lock"' "${CTL}" || die "ctl missing lock"
grep -q 'state' "${CTL}" || die "ctl missing state"
ok "core ctl verbs present"

# No smoke may still call qs/quickshell ipc (except retired skip stubs)
hits="$(mktemp)"
trap 'rm -f "${hits}"' EXIT
if grep -RInE '(^|[^#[:alnum:]_])(qs|quickshell)[[:space:]]+(-p[[:space:]]+\S+[[:space:]]+)?ipc[[:space:]]+call' \
  "${ROOT}/dev/smoke" --include='*-smoke.sh' \
  | grep -v 'ipc-contract-smoke.sh' \
  | grep -v 'SKIP (Quickshell' \
  | grep -v '^[^:]*qs-.*-smoke.sh:' \
  >"${hits}" 2>/dev/null; then
  if [[ -s "${hits}" ]]; then
    cat "${hits}" >&2
    die "dev/smoke still calls qs/quickshell ipc"
  fi
fi
ok "no qs ipc call sites in active smokes"

echo "ipc-contract-smoke: OK"
