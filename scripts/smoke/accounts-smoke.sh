#!/usr/bin/env bash
# accounts-smoke — static checks for proteus-accounts + Settings Online accounts
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fail=0
ok() { echo "accounts-smoke: OK $*"; }
die() { echo "accounts-smoke: FAIL $*" >&2; fail=1; }

PKG="${ROOT}/services/proteus-accounts"
[[ -f "${PKG}/Cargo.toml" ]] || die "missing Cargo.toml"
[[ -f "${PKG}/src/main.rs" ]] || die "missing src/main.rs"
[[ -f "${ROOT}/shell/shared/Accounts.qml" ]] || die "missing Accounts.qml"
[[ -f "${ROOT}/apps/proteus-settings/panes/AccountsPane.qml" ]] || die "missing AccountsPane.qml"
[[ -x "${ROOT}/vm/guest/install-proteus-accounts.sh" ]] || die "install-proteus-accounts.sh"

grep -q 'proteus-accounts' "${ROOT}/shell/shared/Accounts.qml" || die "Accounts.qml cites CLI"
grep -q 'connectGoogle\|connectMicrosoft\|connectNextcloud\|disconnectSeat' \
  "${ROOT}/shell/shared/Accounts.qml" || die "Accounts.qml connect/disconnect APIs"
grep -q 'microsoftClientConfigured' "${ROOT}/shell/shared/Accounts.qml" \
  || die "Accounts.qml missing microsoftClientConfigured"
grep -q 'Accounts\.' "${ROOT}/apps/proteus-settings/panes/AccountsPane.qml" \
  || die "AccountsPane uses Accounts façade"
grep -q 'google\|Microsoft\|Nextcloud' "${ROOT}/apps/proteus-settings/panes/AccountsPane.qml" \
  || die "AccountsPane catalog labels"
grep -q 'connectMicrosoft\|Connect Nextcloud' "${ROOT}/apps/proteus-settings/panes/AccountsPane.qml" \
  || die "AccountsPane Microsoft/Nextcloud Connect UI"
grep -q 'settings.json' "${ROOT}/apps/proteus-settings/panes/AccountsPane.qml" \
  || die "AccountsPane vault honesty"
grep -q 'Accounts.qml' "${ROOT}/scripts/smoke/layout-smoke.sh" || die "layout-smoke requires Accounts.qml"

grep -q 'connect microsoft\|connect_microsoft\|"microsoft"' "${PKG}/src/main.rs" \
  || die "proteus-accounts missing microsoft connect"
grep -q 'connect_nextcloud\|connect nextcloud' "${PKG}/src/main.rs" \
  || die "proteus-accounts missing nextcloud connect"
grep -q 'PROTEUS_MICROSOFT_OAUTH_CLIENT_ID\|oauth-microsoft-client-id' "${PKG}/src/main.rs" \
  || die "proteus-accounts missing Microsoft client id path"
grep -q 'v1_status: "connectable"' "${PKG}/src/main.rs" || die "catalog connectable markers"
ok "sources + Settings wiring"

BIN=""
# Prefer freshly built release over possibly stale services/.../bin copy.
if [[ -x "${PKG}/target/release/proteus-accounts" ]]; then
  BIN="${PKG}/target/release/proteus-accounts"
elif [[ -x "${PKG}/bin/proteus-accounts" ]]; then
  BIN="${PKG}/bin/proteus-accounts"
fi
if [[ -n "${BIN}" ]]; then
  out="$("${BIN}" smoke)"
  echo "${out}" | grep -q '"ok": true' || die "smoke JSON ok"
  echo "${out}" | grep -q '"secretsInSettingsJson": false' || die "secrets flag"
  echo "${out}" | grep -q '"catalogCount": 8' || die "catalog count 8"
  echo "${out}" | grep -q '"nextcloudConnectable": true' || die "nextcloudConnectable"
  cat_out="$("${BIN}" catalog)"
  echo "${cat_out}" | grep -q '"id": "google"' || die "catalog google"
  echo "${cat_out}" | grep -q '"id": "microsoft"' || die "catalog microsoft"
  echo "${cat_out}" | grep -q '"id": "nextcloud"' || die "catalog nextcloud"
  echo "${cat_out}" | grep -q '"v1Status": "connectable"' || die "catalog connectable status"
  st="$("${BIN}" status)"
  echo "${st}" | grep -q '"connectors"' || die "status connectors"
  echo "${st}" | grep -q 'microsoftClientConfigured' || die "status microsoftClientConfigured"
  # Usage / arg errors (no live OAuth)
  set +e
  "${BIN}" connect >/dev/null 2>&1
  cec=$?
  "${BIN}" connect nextcloud >/dev/null 2>&1
  nec=$?
  set -e
  [[ "${cec}" -ne 0 ]] || die "connect without provider should fail"
  [[ "${nec}" -ne 0 ]] || die "connect nextcloud without args should fail"
  # Offline Nextcloud seat write (skip network verify)
  TMP="$(mktemp -d)"
  trap 'rm -rf "${TMP}"' RETURN
  export HOME="${TMP}"
  unset XDG_CONFIG_HOME XDG_DATA_HOME || true
  export PROTEUS_ACCOUNTS_SKIP_VERIFY=1
  nc_out="$("${BIN}" connect nextcloud "https://cloud.example" "alice" "app-pass-test")"
  echo "${nc_out}" | grep -q '"ok": true' || die "nextcloud skip-verify connect"
  echo "${nc_out}" | grep -q 'nextcloud' || die "nextcloud seat provider"
  [[ -f "${HOME}/.config/proteus/accounts.json" ]] || die "accounts.json missing after nextcloud"
  tok="$(find "${HOME}/.local/share/proteus/accounts/tokens" -name 'nextcloud-*.token.json' | head -1)"
  [[ -n "${tok}" ]] || die "nextcloud token vault missing"
  ok "binary ${BIN}"
else
  ok "binary not built yet (Cargo.toml + sources present)"
fi

# Fail closed: no token paths in settings schema docs claiming oauth secrets
if grep -q 'oauth.*settings.json\|settings.json.*refresh_token' \
  "${ROOT}/docs/proteus/CONFIG-SCHEMA.md" 2>/dev/null; then
  die "CONFIG-SCHEMA must not put OAuth secrets in settings.json"
fi
ok "no OAuth secrets in settings.json schema"

# Calendar glance consumer (#1322–#1324)
CAL="${ROOT}/shell/scripts/proteus-calendar-events.py"
CE_QML="${ROOT}/shell/shared/CalendarEvents.qml"
CP="${ROOT}/shell/surfaces/desktop/CalendarPanel.qml"
[[ -x "${CAL}" ]] || die "proteus-calendar-events.py not executable"
[[ -f "${CE_QML}" ]] || die "missing CalendarEvents.qml"
grep -q 'CalendarEvents' "${CP}" || die "CalendarPanel must use CalendarEvents"
grep -q 'calendar.readonly\|Calendars.Read' "${PKG}/src/main.rs" \
  || die "proteus-accounts missing calendar scopes"
grep -q 'fn cmd_token\|"token"' "${PKG}/src/main.rs" || die "proteus-accounts missing token command"
grep -q 'proteus-calendar-events.py' "${ROOT}/vm/install/apps.sh" \
  || die "apps.sh must install proteus-calendar-events.py"
grep -q 'CalendarEvents.qml' "${ROOT}/scripts/smoke/layout-smoke.sh" \
  || die "layout-smoke requires CalendarEvents.qml"
ok "calendar glance wiring"

PROTEUS_CALENDAR_FIXTURE=1 python3 "${CAL}" | python3 -c 'import json,sys
d=json.load(sys.stdin)
assert d.get("ok") is True
assert isinstance(d.get("events"), list) and len(d["events"]) >= 1
' || die "calendar fixture fetch"
ok "calendar fixture"

if [[ -n "${BIN}" ]]; then
  TMP2="$(mktemp -d)"
  export HOME="${TMP2}"
  unset XDG_CONFIG_HOME XDG_DATA_HOME || true
  export PROTEUS_ACCOUNTS_SKIP_VERIFY=1
  "${BIN}" connect nextcloud "https://cloud.example" "bob" "tok-pass" >/dev/null
  tok_out="$("${BIN}" token nextcloud)"
  echo "${tok_out}" | python3 -c 'import json,sys
d=json.load(sys.stdin)
assert d.get("ok") is True
assert d.get("provider")=="nextcloud"
assert d.get("accessToken")=="tok-pass"
assert "refresh_token" not in d and "refreshToken" not in d
' || die "token nextcloud JSON"
  set +e
  "${BIN}" token nosuch >/dev/null 2>&1
  tec=$?
  set -e
  [[ "${tec}" -ne 0 ]] || die "token unknown seat should fail"
  rm -rf "${TMP2}"
  ok "token command"
fi

if [[ "${fail}" -ne 0 ]]; then
  exit 1
fi
echo "accounts-smoke: OK"
