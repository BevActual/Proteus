#!/usr/bin/env bash
# users-smoke — Users depth greeter autologin writer (host static)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fail=0
ok() { echo "users-smoke: OK $*"; }
die() { echo "users-smoke: FAIL $*" >&2; fail=1; }

PKG="${ROOT}/services/proteus-greetd"
USERS="${ROOT}/apps/proteus-settings/panes/UsersPane.qml"
INSTALL="${ROOT}/vm/guest/install-proteus-greetd.sh"
STATUS_PY="${ROOT}/shell/scripts/proteus-greetd-status.py"

[[ -f "${PKG}/Cargo.toml" ]] || die "missing proteus-greetd Cargo.toml"
[[ -f "${PKG}/src/main.rs" ]] || die "missing proteus-greetd main.rs"
[[ -f "${PKG}/org.bevington.proteus.greetd.policy" ]] || die "missing polkit policy"
[[ -x "${INSTALL}" ]] || die "install-proteus-greetd.sh not executable"
[[ -f "${USERS}" ]] || die "missing UsersPane.qml"
[[ -f "${STATUS_PY}" ]] || die "missing proteus-greetd-status.py"
ok "files present"

grep -q 'set-autologin\|clear-autologin' "${PKG}/src/main.rs" || die "CLI missing set/clear"
grep -q 'initial_session' "${PKG}/src/main.rs" || die "CLI missing initial_session rewrite"
grep -q 'setAutologin\|proteus-greetd' "${USERS}" || die "UsersPane missing autologin wiring"
grep -q 'Turn on\|Turn off\|Autologin' "${USERS}" || die "UsersPane missing Autologin UI"
grep -q 'install-proteus-greetd' "${USERS}" "${ROOT}/vm/guest/install-settings-app.sh" \
  || die "install path missing from Users/settings-app"
grep -q 'install-proteus-greetd.sh' "${ROOT}/vm/guest/install-settings-app.sh" \
  || die "install-settings-app must wire proteus-greetd"
ok "wiring"

BIN=""
if [[ -x "${PKG}/target/release/proteus-greetd" ]]; then
  BIN="${PKG}/target/release/proteus-greetd"
elif [[ -x "${PKG}/bin/proteus-greetd" ]]; then
  BIN="${PKG}/bin/proteus-greetd"
fi

if [[ -n "${BIN}" ]]; then
  out="$("${BIN}" smoke)"
  echo "${out}" | grep -q '"ok": true' || die "smoke JSON ok"
  echo "${out}" | grep -q '"restartsGreetd": false' || die "must not claim greetd restart"
  set +e
  "${BIN}" >/dev/null 2>&1
  uec=$?
  set -e
  [[ "${uec}" -eq 2 ]] || die "usage should exit 2 (got ${uec})"

  TMP="$(mktemp -d)"
  trap 'rm -rf "${TMP}"' RETURN
  export PROTEUS_GREETD_CONF="${TMP}/config.toml"
  export PROTEUS_GREETD_TEST_WRITE=1
  cp "${ROOT}/vm/guest/greetd-config.toml" "${PROTEUS_GREETD_CONF}"
  # neutralize production username for rewrite test
  sed -i 's/user = "andrew"/user = "sample"/' "${PROTEUS_GREETD_CONF}" || true
  "${BIN}" clear-autologin >/dev/null
  grep -q '\[initial_session\]' "${PROTEUS_GREETD_CONF}" && die "clear left initial_session" || true
  "${BIN}" set-autologin dogfooduser >/dev/null
  grep -q '\[initial_session\]' "${PROTEUS_GREETD_CONF}" || die "set missing initial_session"
  grep -q 'user = "dogfooduser"' "${PROTEUS_GREETD_CONF}" || die "set missing user"
  grep -q '\[default_session\]' "${PROTEUS_GREETD_CONF}" || die "default_session clobbered"
  show="$("${BIN}" show)"
  echo "${show}" | grep -q '"autologin": true' || die "show autologin true"
  echo "${show}" | grep -q 'dogfooduser' || die "show user"
  ok "binary ${BIN}"
else
  ok "binary not built yet (sources present)"
fi

[[ $fail -eq 0 ]] || { echo "users-smoke: FAILED" >&2; exit 1; }
echo "users-smoke: OK"
