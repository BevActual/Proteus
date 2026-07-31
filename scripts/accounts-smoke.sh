#!/usr/bin/env bash
# accounts-smoke — static checks for proteus-accounts + Settings Online accounts
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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
grep -q 'connectGoogle\|disconnectSeat' "${ROOT}/shell/shared/Accounts.qml" \
  || die "Accounts.qml connect/disconnect"
grep -q 'Accounts\.' "${ROOT}/apps/proteus-settings/panes/AccountsPane.qml" \
  || die "AccountsPane uses Accounts façade"
grep -q 'google\|Microsoft\|Nextcloud' "${ROOT}/apps/proteus-settings/panes/AccountsPane.qml" \
  || die "AccountsPane catalog labels"
grep -q 'settings.json' "${ROOT}/apps/proteus-settings/panes/AccountsPane.qml" \
  || die "AccountsPane vault honesty"
grep -q 'Accounts.qml' "${ROOT}/scripts/layout-smoke.sh" || die "layout-smoke requires Accounts.qml"

BIN=""
if [[ -x "${PKG}/bin/proteus-accounts" ]]; then
  BIN="${PKG}/bin/proteus-accounts"
elif [[ -x "${PKG}/target/release/proteus-accounts" ]]; then
  BIN="${PKG}/target/release/proteus-accounts"
fi
if [[ -n "${BIN}" ]]; then
  out="$("${BIN}" smoke)"
  echo "${out}" | grep -q '"ok": true' || die "smoke JSON ok"
  echo "${out}" | grep -q '"secretsInSettingsJson": false' || die "secrets flag"
  echo "${out}" | grep -q '"catalogCount": 8' || die "catalog count 8"
  cat_out="$("${BIN}" catalog)"
  echo "${cat_out}" | grep -q '"id": "google"' || die "catalog google"
  echo "${cat_out}" | grep -q '"id": "microsoft"' || die "catalog microsoft"
  echo "${cat_out}" | grep -q '"id": "nextcloud"' || die "catalog nextcloud"
  st="$("${BIN}" status)"
  echo "${st}" | grep -q '"connectors"' || die "status connectors"
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

if [[ "${fail}" -ne 0 ]]; then
  exit 1
fi
echo "accounts-smoke: OK"
