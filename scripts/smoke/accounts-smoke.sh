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
PANE="${ROOT}/apps/proteus-settings/panes/AccountsPane.qml"
LEAF="${ROOT}/apps/proteus-settings/panes/AccountsProviderLeaf.qml"
[[ -f "${ROOT}/shell/shared/Accounts.qml" ]] || die "missing Accounts.qml"
[[ -f "${PANE}" ]] || die "missing AccountsPane.qml"
[[ -f "${LEAF}" ]] || die "missing AccountsProviderLeaf.qml"
[[ -x "${ROOT}/vm/guest/install-proteus-accounts.sh" ]] || die "install-proteus-accounts.sh"

grep -q 'proteus-accounts' "${ROOT}/shell/shared/Accounts.qml" || die "Accounts.qml cites CLI"
grep -q 'connectGoogle\|connectMicrosoft\|connectNextcloud\|connectImap\|connectCaldav\|connectCarddav\|connectApple\|connectExchange\|disconnectSeat' \
  "${ROOT}/shell/shared/Accounts.qml" || die "Accounts.qml connect/disconnect APIs"
grep -q 'microsoftClientConfigured' "${ROOT}/shell/shared/Accounts.qml" \
  || die "Accounts.qml missing microsoftClientConfigured"
grep -q 'imapConnectable\|imapHost\|connectImap' "${ROOT}/shell/shared/Accounts.qml" \
  || die "Accounts.qml missing IMAP form APIs"
grep -q 'caldavConnectable\|caldavUrl\|connectCaldav' "${ROOT}/shell/shared/Accounts.qml" \
  || die "Accounts.qml missing CalDAV form APIs"
grep -q 'carddavConnectable\|carddavUrl\|connectCarddav' "${ROOT}/shell/shared/Accounts.qml" \
  || die "Accounts.qml missing CardDAV form APIs"
grep -q 'appleConnectable\|appleId\|connectApple' "${ROOT}/shell/shared/Accounts.qml" \
  || die "Accounts.qml missing Apple form APIs"
grep -q 'exchangeConnectable\|connectExchange' "${ROOT}/shell/shared/Accounts.qml" \
  || die "Accounts.qml missing Exchange connect APIs"
grep -q 'Accounts\.' "${PANE}" || die "AccountsPane uses Accounts façade"
grep -q 'signal requestGo\|property string page' "${PANE}" || die "AccountsPane hub shape"
grep -q 'accounts-google\|accounts-imap\|AccountsProviderLeaf' "${PANE}" \
  || die "AccountsPane leaf loaders"
grep -q 'google\|Microsoft\|Nextcloud\|IMAP\|CalDAV\|CardDAV\|Apple\|Exchange' "${PANE}" \
  || die "AccountsPane catalog labels"
grep -q 'settings.json' "${PANE}" || die "AccountsPane vault honesty"
grep -q 'connectGoogle\|connectMicrosoft\|connectExchange\|connectNextcloud\|connectImap\|connectCaldav\|connectCarddav\|connectApple' "${LEAF}" \
  || die "AccountsProviderLeaf connect wiring"
grep -q 'Connect Nextcloud\|Connect IMAP\|Connect CalDAV\|Connect CardDAV\|Connect Apple' "${LEAF}" \
  || die "AccountsProviderLeaf Microsoft/Exchange/Nextcloud/IMAP/CalDAV/CardDAV/Apple Connect UI"
grep -q 'disconnectSeat\|Disconnect' "${LEAF}" || die "AccountsProviderLeaf disconnect UI"
grep -q 'settings.json' "${LEAF}" || die "AccountsProviderLeaf vault honesty"
# #1596 — password binds must not mirror live values into FormRow hint
grep -q 'modelData.password' "${LEAF}" \
  || die "AccountsProviderLeaf password hint gate (#1596)"
python3 - "${LEAF}" <<'PY' || die "AccountsProviderLeaf password hints must not use fieldValue (#1596)"
import sys
from pathlib import Path
text = Path(sys.argv[1]).read_text()
idx = text.find("SettingsFormRow {\n          label: modelData.label")
if idx < 0:
    raise SystemExit("form-row block missing")
chunk = text[idx:idx + 450]
if "modelData.password" not in chunk:
    raise SystemExit("password branch missing from hint")
pw = chunk.find("modelData.password")
fv = chunk.find("fieldValue(modelData.bind)")
if fv >= 0 and (pw < 0 or fv < pw):
    raise SystemExit("fieldValue before password gate in hint")
print("ok")
PY
# #1597 — Reconnect gated on oauthReady like Connect
grep -q 'interactive: !Accounts.busy && root.oauthReady' "${LEAF}" \
  || die "AccountsProviderLeaf Reconnect must gate on oauthReady (#1597)"
# #1598 — Beacon index includes per-provider leaves
EG="${ROOT}/shell/shared/EnvGate.qml"
for id in accounts-google accounts-microsoft accounts-exchange accounts-nextcloud \
          accounts-imap accounts-caldav accounts-carddav accounts-apple; do
  grep -q "id: \"${id}\"" "${EG}" || die "EnvGate settingsSearchIndex missing ${id} (#1598)"
done
grep -q 'id: "accounts"' "${ROOT}/apps/proteus-settings/SettingsNav.qml" \
  || die "SettingsNav missing accounts hub"
grep -q 'accountsChildren\|accounts-google' "${ROOT}/apps/proteus-settings/Settings.qml" \
  || die "Settings.qml missing accountsChildren"
grep -q 'section === "accounts"' "${ROOT}/apps/proteus-settings/Settings.qml" \
  || die "Settings.qml accounts section loader"
grep -q 'Accounts.qml' "${ROOT}/scripts/smoke/layout-smoke.sh" || die "layout-smoke requires Accounts.qml"

grep -q 'connect microsoft\|connect_microsoft\|"microsoft"' "${PKG}/src/main.rs" \
  || die "proteus-accounts missing microsoft connect"
grep -q 'connect_nextcloud\|connect nextcloud' "${PKG}/src/main.rs" \
  || die "proteus-accounts missing nextcloud connect"
grep -q 'connect_imap\|connect imap' "${PKG}/src/main.rs" \
  || die "proteus-accounts missing imap connect"
grep -q 'connect_caldav\|connect caldav' "${PKG}/src/main.rs" \
  || die "proteus-accounts missing caldav connect"
grep -q 'connect_carddav\|connect carddav' "${PKG}/src/main.rs" \
  || die "proteus-accounts missing carddav connect"
grep -q 'connect_apple\|connect apple' "${PKG}/src/main.rs" \
  || die "proteus-accounts missing apple connect"
grep -q 'connect_exchange\|connect exchange' "${PKG}/src/main.rs" \
  || die "proteus-accounts missing exchange connect"
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
  echo "${out}" | grep -q '"imapConnectable": true' || die "imapConnectable"
  echo "${out}" | grep -q '"caldavConnectable": true' || die "caldavConnectable"
  echo "${out}" | grep -q '"carddavConnectable": true' || die "carddavConnectable"
  echo "${out}" | grep -q '"appleConnectable": true' || die "appleConnectable"
  echo "${out}" | grep -q '"exchangeConnectable"' || die "exchangeConnectable key"
  cat_out="$("${BIN}" catalog)"
  echo "${cat_out}" | grep -q '"id": "google"' || die "catalog google"
  echo "${cat_out}" | grep -q '"id": "microsoft"' || die "catalog microsoft"
  echo "${cat_out}" | grep -q '"id": "nextcloud"' || die "catalog nextcloud"
  echo "${cat_out}" | grep -q '"id": "apple"' || die "catalog apple"
  echo "${cat_out}" | grep -q '"id": "exchange"' || die "catalog exchange"
  echo "${cat_out}" | grep -q '"id": "imap"' || die "catalog imap"
  echo "${cat_out}" | grep -q '"id": "caldav"' || die "catalog caldav"
  echo "${cat_out}" | grep -q '"id": "carddav"' || die "catalog carddav"
  echo "${cat_out}" | grep -q '"v1Status": "connectable"' || die "catalog connectable status"
  echo "${cat_out}" | python3 -c 'import json,sys
c=json.load(sys.stdin)["connectors"]
assert next(x for x in c if x["id"]=="caldav")["v1Status"]=="connectable"
assert next(x for x in c if x["id"]=="carddav")["v1Status"]=="connectable"
assert next(x for x in c if x["id"]=="apple")["v1Status"]=="connectable"
assert next(x for x in c if x["id"]=="exchange")["v1Status"]=="connectable"
' || die "catalog caldav/carddav/apple/exchange connectable"
  st="$("${BIN}" status)"
  echo "${st}" | grep -q '"connectors"' || die "status connectors"
  echo "${st}" | grep -q 'microsoftClientConfigured' || die "status microsoftClientConfigured"
  echo "${st}" | grep -q 'appleConnectable' || die "status appleConnectable"
  # Usage / arg errors (no live OAuth)
  set +e
  "${BIN}" connect >/dev/null 2>&1
  cec=$?
  "${BIN}" connect nextcloud >/dev/null 2>&1
  nec=$?
  "${BIN}" connect imap >/dev/null 2>&1
  iec=$?
  "${BIN}" connect caldav >/dev/null 2>&1
  cdec=$?
  "${BIN}" connect carddav >/dev/null 2>&1
  crdec=$?
  "${BIN}" connect apple >/dev/null 2>&1
  adec=$?
  # Exchange OAuth — empty HOME so we never open a browser if host has a client id.
  XHOME="$(mktemp -d)"
  HOME="${XHOME}" unset PROTEUS_MICROSOFT_OAUTH_CLIENT_ID
  HOME="${XHOME}" env -u PROTEUS_MICROSOFT_OAUTH_CLIENT_ID "${BIN}" connect exchange >/dev/null 2>&1
  xec=$?
  rm -rf "${XHOME}"
  set -e
  [[ "${cec}" -ne 0 ]] || die "connect without provider should fail"
  [[ "${nec}" -ne 0 ]] || die "connect nextcloud without args should fail"
  [[ "${iec}" -ne 0 ]] || die "connect imap without args should fail"
  [[ "${cdec}" -ne 0 ]] || die "connect caldav without args should fail"
  [[ "${crdec}" -ne 0 ]] || die "connect carddav without args should fail"
  [[ "${adec}" -ne 0 ]] || die "connect apple without args should fail"
  [[ "${xec}" -ne 0 ]] || die "connect exchange without client should fail"
  # Offline Nextcloud + IMAP + CalDAV + CardDAV + Apple seat write (skip network verify)
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
  imap_out="$("${BIN}" connect imap "mail.example" "993" "bob" "imap-pass-test")"
  echo "${imap_out}" | grep -q '"ok": true' || die "imap skip-verify connect"
  echo "${imap_out}" | grep -q 'imap' || die "imap seat provider"
  itok="$(find "${HOME}/.local/share/proteus/accounts/tokens" -name 'imap-*.token.json' | head -1)"
  [[ -n "${itok}" ]] || die "imap token vault missing"
  cd_out="$("${BIN}" connect caldav "https://cal.example/dav/calendars/alice" "alice" "cal-pass-test")"
  echo "${cd_out}" | grep -q '"ok": true' || die "caldav skip-verify connect"
  echo "${cd_out}" | grep -q 'caldav' || die "caldav seat provider"
  ctok="$(find "${HOME}/.local/share/proteus/accounts/tokens" -name 'caldav-*.token.json' | head -1)"
  [[ -n "${ctok}" ]] || die "caldav token vault missing"
  cr_out="$("${BIN}" connect carddav "https://card.example/dav/addressbooks/alice" "alice" "card-pass-test")"
  echo "${cr_out}" | grep -q '"ok": true' || die "carddav skip-verify connect"
  echo "${cr_out}" | grep -q 'carddav' || die "carddav seat provider"
  crtok="$(find "${HOME}/.local/share/proteus/accounts/tokens" -name 'carddav-*.token.json' | head -1)"
  [[ -n "${crtok}" ]] || die "carddav token vault missing"
  ap_out="$("${BIN}" connect apple "alice@icloud.com" "apple-app-pass-test")"
  echo "${ap_out}" | grep -q '"ok": true' || die "apple skip-verify connect"
  echo "${ap_out}" | grep -q 'apple' || die "apple seat provider"
  aptok="$(find "${HOME}/.local/share/proteus/accounts/tokens" -name 'apple-*.token.json' | head -1)"
  [[ -n "${aptok}" ]] || die "apple token vault missing"
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

# Calendar glance + CalDAV event CRUD (#1322–#1324 · #1496–#1500 · #1526–#1530)
CAL="${ROOT}/shell/scripts/proteus-calendar-events.py"
MUT="${ROOT}/shell/scripts/proteus-calendar-mutate.py"
CE_QML="${ROOT}/shell/shared/CalendarEvents.qml"
CP="${ROOT}/shell/surfaces/desktop/CalendarPanel.qml"
[[ -x "${CAL}" ]] || die "proteus-calendar-events.py not executable"
[[ -x "${MUT}" ]] || die "proteus-calendar-mutate.py not executable"
[[ -f "${CE_QML}" ]] || die "missing CalendarEvents.qml"
grep -q 'CalendarEvents' "${CP}" || die "CalendarPanel must use CalendarEvents"
grep -q 'createEvent\|deleteEvent\|updateEvent' "${CE_QML}" \
  || die "CalendarEvents missing create/update/delete API"
grep -q 'def cmd_update\|"update"' "${MUT}" || die "mutate missing update action"
grep -q 'CalendarEvents.createEvent\|canCreate' "${CP}" \
  || die "CalendarPanel must wire CalDAV create"
grep -q 'CalendarEvents.updateEvent\|editingHref' "${CP}" \
  || die "CalendarPanel must wire CalDAV edit"
grep -q 'deleteEvent\|isMutable' "${CP}" || die "CalendarPanel must wire CalDAV delete"
grep -q 'calendar.events\|Calendars.ReadWrite' "${PKG}/src/main.rs" \
  || die "proteus-accounts missing calendar write scopes"
grep -q 'fn cmd_token\|"token"' "${PKG}/src/main.rs" || die "proteus-accounts missing token command"
grep -q 'proteus-calendar-events.py' "${ROOT}/vm/install/apps.sh" \
  || die "apps.sh must install proteus-calendar-events.py"
grep -q 'proteus-calendar-mutate.py' "${ROOT}/vm/install/apps.sh" \
  || die "apps.sh must install proteus-calendar-mutate.py"
grep -q 'CalendarEvents.qml' "${ROOT}/scripts/smoke/layout-smoke.sh" \
  || die "layout-smoke requires CalendarEvents.qml"
grep -q 'def fetch_caldav\|providers = ("google", "microsoft", "exchange", "nextcloud", "caldav", "apple")' "${CAL}" \
  || die "proteus-calendar-events.py missing CalDAV/Apple/Exchange fetch"
grep -q 'mutable\|href' "${CAL}" || die "calendar fetch must emit mutable/href"
grep -qiE 'Google/MS create|CalDAV \+ Google/MS|mail compose thin In' "${CP}" \
  || die "CalendarPanel must state Google/MS write In + mail compose thin In"
grep -qiE 'recurrence thin create\+edit|COUNT end|editEventRepeat|cycleEditRepeat' "${CP}" \
  || die "CalendarPanel must expose recurrence thin create+edit"
grep -q 'newEventRepeat\|cycleRepeat' "${CP}" \
  || die "CalendarPanel must expose create recurrence cycler"
grep -q 'cycleRepeatEnd\|newEventRepeatEnd\|editEventRepeatEnd\|endLabel' "${CP}" \
  || die "CalendarPanel must expose COUNT end chip"
grep -q 'google.*microsoft.*exchange\|OAUTH_WRITABLE' "${MUT}" \
  || die "mutate must list Google/MS/Exchange writable"
grep -q '_normalize_recurrence\|--recurrence\|RRULE:FREQ\|_graph_recurrence' "${MUT}" \
  || die "mutate must support create recurrence"
grep -Eqe '--recurrence-end|COUNT=|_normalize_recurrence_end|numbered' -- "${MUT}" \
  || die "mutate must support recurrence COUNT end"
grep -q 'createEvent(title, dayIso, recurrence\|recurrenceEnd' "${CE_QML}" \
  || die "CalendarEvents.createEvent must accept recurrenceEnd"
grep -q 'updateEvent(ev, title, dayIso, recurrence\|seriesId\|recurrenceEnd' "${CE_QML}" \
  || die "CalendarEvents.updateEvent must accept recurrence / seriesId / end"
grep -q '_recurrence_from_ics\|seriesId\|recurringEventId\|seriesMasterId\|recurrenceEnd' "${CAL}" \
  || die "calendar fetch must emit recurrence / seriesId / recurrenceEnd"
grep -q 'calendar.events\|Calendars.ReadWrite' "${PKG}/src/main.rs" \
  || die "accounts catalog/scopes must advertise write"
ok "calendar glance + CRUD wiring"

PROTEUS_CALENDAR_FIXTURE=1 python3 "${CAL}" | python3 -c 'import json,sys
d=json.load(sys.stdin)
assert d.get("ok") is True
assert isinstance(d.get("events"), list) and len(d["events"]) >= 1
ev=d["events"][0]
assert ev.get("mutable") is True
assert "href" in ev and ev["href"]
assert ev.get("recurrence") == "daily"
assert ev.get("recurrenceEnd") == "count:5"
assert ev.get("seriesId")
assert d.get("mutableSeats", 0) >= 1
' || die "calendar fixture fetch"
ok "calendar fixture"

PROTEUS_CALENDAR_MUTATE_FIXTURE=1 python3 "${MUT}" create --title "Smoke" --date 2026-08-02 \
  | python3 -c 'import json,sys
d=json.load(sys.stdin)
assert d.get("ok") is True and d.get("action")=="create"
assert d.get("mutable") is True and d.get("href")
' || die "calendar mutate create fixture"
PROTEUS_CALENDAR_MUTATE_FIXTURE=1 python3 "${MUT}" create --title "Repeat" --date 2026-08-02 \
  --recurrence daily \
  | python3 -c 'import json,sys
d=json.load(sys.stdin)
assert d.get("ok") is True and d.get("action")=="create"
assert d.get("recurrence")=="daily"
assert d.get("recurrenceEnd")=="forever"
' || die "calendar mutate create recurrence fixture"
PROTEUS_CALENDAR_MUTATE_FIXTURE=1 python3 "${MUT}" create --title "Counted" --date 2026-08-02 \
  --recurrence weekly --recurrence-end count:5 \
  | python3 -c 'import json,sys
d=json.load(sys.stdin)
assert d.get("ok") is True and d.get("action")=="create"
assert d.get("recurrence")=="weekly"
assert d.get("recurrenceEnd")=="count:5"
' || die "calendar mutate create COUNT end fixture"
PROTEUS_CALENDAR_MUTATE_FIXTURE=1 python3 "${MUT}" update \
  --href "https://cal.example/dav/calendars/alice/personal/fixture-uid-1.ics" \
  --title "Renamed" --date 2026-08-02 \
  | python3 -c 'import json,sys
d=json.load(sys.stdin)
assert d.get("ok") is True and d.get("action")=="update"
assert d.get("title")=="Renamed" and d.get("mutable") is True
' || die "calendar mutate update fixture"
PROTEUS_CALENDAR_MUTATE_FIXTURE=1 python3 "${MUT}" update \
  --href "https://cal.example/dav/calendars/alice/personal/fixture-uid-1.ics" \
  --title "Renamed" --date 2026-08-02 --recurrence weekly --recurrence-end count:10 \
  | python3 -c 'import json,sys
d=json.load(sys.stdin)
assert d.get("ok") is True and d.get("action")=="update"
assert d.get("recurrence")=="weekly"
assert d.get("recurrenceEnd")=="count:10"
' || die "calendar mutate update recurrence COUNT fixture"
PROTEUS_CALENDAR_MUTATE_FIXTURE=1 python3 "${MUT}" delete \
  --href "https://cal.example/dav/calendars/alice/personal/fixture-uid-1.ics" \
  | python3 -c 'import json,sys
d=json.load(sys.stdin)
assert d.get("ok") is True and d.get("action")=="delete"
' || die "calendar mutate delete fixture"
PROTEUS_CALENDAR_MUTATE_FIXTURE=1 python3 "${MUT}" providers | python3 -c 'import json,sys
d=json.load(sys.stdin)
assert d.get("ok") is True and "caldav" in (d.get("providers") or [])
' || die "calendar mutate providers fixture"
ok "calendar mutate fixtures"

# Mail glance consumer (#1347–#1350)
MAIL="${ROOT}/shell/scripts/proteus-mail-glance.py"
MG_QML="${ROOT}/shell/shared/MailGlance.qml"
[[ -x "${MAIL}" ]] || die "proteus-mail-glance.py not executable"
[[ -f "${MG_QML}" ]] || die "missing MailGlance.qml"
grep -q 'MailGlance' "${CP}" || die "CalendarPanel must use MailGlance"
grep -q 'gmail.metadata\|Mail.ReadBasic' "${PKG}/src/main.rs" \
  || die "proteus-accounts missing mail scopes"
grep -q 'gmail.send\|Mail.Send' "${PKG}/src/main.rs" \
  || die "proteus-accounts missing mail send scopes"
grep -q 'def fetch_imap\|providers = ("google", "microsoft", "exchange", "imap", "apple")' "${MAIL}" \
  || die "proteus-mail-glance.py missing IMAP/Apple/Exchange fetch"
grep -q 'proteus-mail-glance.py' "${ROOT}/vm/install/apps.sh" \
  || die "apps.sh must install proteus-mail-glance.py"
grep -q 'MailGlance.qml' "${ROOT}/scripts/smoke/layout-smoke.sh" \
  || die "layout-smoke requires MailGlance.qml"
grep -q 'mailAppAvailable\|openMailApp' "${ROOT}/shell/shared/ShellState.qml" \
  || die "ShellState missing mail handoff"
ok "mail glance wiring"

PROTEUS_MAIL_FIXTURE=1 python3 "${MAIL}" | python3 -c 'import json,sys
d=json.load(sys.stdin)
assert d.get("ok") is True
assert isinstance(d.get("messages"), list) and len(d["messages"]) >= 1
assert int(d.get("unread") or 0) >= 1
' || die "mail fixture fetch"
ok "mail fixture"

# Mail compose thin (#1571–#1575)
MSEND="${ROOT}/shell/scripts/proteus-mail-send.py"
[[ -x "${MSEND}" ]] || die "proteus-mail-send.py not executable"
grep -q 'sendMessage\|canSend\|proteus-mail-send' "${MG_QML}" \
  || die "MailGlance missing send wiring"
grep -q 'MailGlance.sendMessage\|MailGlance.canSend\|Compose thin In' "${CP}" \
  || die "CalendarPanel missing mail compose UI"
grep -q 'proteus-mail-send.py' "${ROOT}/vm/install/apps.sh" \
  || die "apps.sh must install proteus-mail-send.py"
grep -q 'def send_google\|def send_microsoft\|def send_smtp\|SENDABLE' "${MSEND}" \
  || die "proteus-mail-send.py missing provider send paths"
grep -Eqe '--cc|--bcc|_parse_addrs|ccRecipients|bccRecipients' -- "${MSEND}" \
  || die "proteus-mail-send.py missing CC/BCC"
grep -Eqe 'composeCc|composeBcc|--cc|--bcc' -- "${MG_QML}" \
  || die "MailGlance missing composeCc/composeBcc"
grep -qiE 'placeholderText: "Cc"|placeholderText: "Bcc"|CC/BCC' "${CP}" \
  || die "CalendarPanel missing Cc/Bcc fields"
grep -Eqe '--attach|add_attachment|fileAttachment|ATTACH_MAX' -- "${MSEND}" \
  || die "proteus-mail-send.py missing attachment send"
grep -Eqe 'composeAttachPath|--attach|attachHint' -- "${MG_QML}" \
  || die "MailGlance missing composeAttachPath"
grep -qiE 'FileDialog|mailAttachDialog|one-file attach|Attach' "${CP}" \
  || die "CalendarPanel missing Attach FileDialog"
ok "mail compose wiring"

PROTEUS_MAIL_SEND_FIXTURE=1 python3 "${MSEND}" send \
  --to "smoke@example.com" --subject "Smoke" --body "hi" \
  | python3 -c 'import json,sys
d=json.load(sys.stdin)
assert d.get("ok") is True and d.get("action")=="send"
assert d.get("to")=="smoke@example.com"
' || die "mail send fixture"
PROTEUS_MAIL_SEND_FIXTURE=1 python3 "${MSEND}" send \
  --to "smoke@example.com" --subject "Smoke" --body "hi" \
  --cc "cc@example.com, other@example.com" --bcc "bcc@example.com" \
  | python3 -c 'import json,sys
d=json.load(sys.stdin)
assert d.get("ok") is True and d.get("action")=="send"
assert d.get("cc")==["cc@example.com","other@example.com"]
assert d.get("bcc")==["bcc@example.com"]
' || die "mail send CC/BCC fixture"
PROTEUS_MAIL_SEND_FIXTURE=1 python3 "${MSEND}" send \
  --to "smoke@example.com" --subject "Smoke" --body "hi" \
  --attach "/tmp/fixture-attach.bin" \
  | python3 -c 'import json,sys
d=json.load(sys.stdin)
assert d.get("ok") is True and d.get("action")=="send"
assert d.get("attachment")=="fixture-attach.bin"
' || die "mail send attach fixture"
PROTEUS_MAIL_SEND_FIXTURE=1 python3 "${MSEND}" providers | python3 -c 'import json,sys
d=json.load(sys.stdin)
assert d.get("ok") is True and int(d.get("sendableSeats") or 0) >= 1
' || die "mail send providers fixture"
ok "mail send fixtures"

# Contacts glance + CardDAV write thin (#1419–#1420 · #1616–#1620)
CONTACTS="${ROOT}/shell/scripts/proteus-contacts-glance.py"
CMUT="${ROOT}/shell/scripts/proteus-contacts-mutate.py"
CG_QML="${ROOT}/shell/shared/ContactsGlance.qml"
[[ -x "${CONTACTS}" ]] || die "proteus-contacts-glance.py not executable"
[[ -x "${CMUT}" ]] || die "proteus-contacts-mutate.py not executable"
[[ -f "${CG_QML}" ]] || die "missing ContactsGlance.qml"
grep -q 'ContactsGlance' "${CP}" || die "CalendarPanel must use ContactsGlance"
grep -q 'def fetch_carddav\|providers = ("carddav", "apple")' "${CONTACTS}" \
  || die "proteus-contacts-glance.py missing CardDAV/Apple fetch"
grep -q 'mutableSeats\|"href"' "${CONTACTS}" \
  || die "proteus-contacts-glance.py must emit href/mutableSeats"
grep -q 'createContact\|updateContact\|deleteContact\|canCreate' "${CG_QML}" \
  || die "ContactsGlance must expose create/update/delete + canCreate"
grep -q 'ContactsGlance.createContact\|ContactsGlance.canCreate' "${CP}" \
  || die "CalendarPanel must wire contacts create thin"
grep -q 'ContactsGlance.updateContact\|ContactsGlance.deleteContact\|isMutable' "${CP}" \
  || die "CalendarPanel must wire contacts edit/delete thin"
grep -q 'proteus-contacts-glance.py' "${ROOT}/vm/install/apps.sh" \
  || die "apps.sh must install proteus-contacts-glance.py"
grep -q 'proteus-contacts-mutate.py' "${ROOT}/vm/install/apps.sh" \
  || die "apps.sh must install proteus-contacts-mutate.py"
grep -q 'ContactsGlance.qml' "${ROOT}/scripts/smoke/layout-smoke.sh" \
  || die "layout-smoke requires ContactsGlance.qml"
ok "contacts glance + write wiring"

PROTEUS_CONTACTS_FIXTURE=1 python3 "${CONTACTS}" | python3 -c 'import json,sys
d=json.load(sys.stdin)
assert d.get("ok") is True
assert isinstance(d.get("contacts"), list) and len(d["contacts"]) >= 1
c=d["contacts"][0]
assert c.get("href") and c.get("uid") and c.get("mutable") is True
assert int(d.get("mutableSeats") or 0) >= 1
' || die "contacts fixture fetch"
ok "contacts fixture"

PROTEUS_CONTACTS_MUTATE_FIXTURE=1 python3 "${CMUT}" create --name "Smoke" --email "smoke@example.com" \
  | python3 -c 'import json,sys
d=json.load(sys.stdin)
assert d.get("ok") is True and d.get("action")=="create"
assert d.get("href") and d.get("mutable") is True
' || die "contacts mutate create fixture"
PROTEUS_CONTACTS_MUTATE_FIXTURE=1 python3 "${CMUT}" update \
  --href "https://cal.example/dav/addressbooks/alice/default/fixture-contact-uid.vcf" \
  --uid fixture-contact-uid --name "Updated" --email "u@example.com" \
  | python3 -c 'import json,sys
d=json.load(sys.stdin)
assert d.get("ok") is True and d.get("action")=="update"
' || die "contacts mutate update fixture"
PROTEUS_CONTACTS_MUTATE_FIXTURE=1 python3 "${CMUT}" delete \
  --href "https://cal.example/dav/addressbooks/alice/default/fixture-contact-uid.vcf" \
  | python3 -c 'import json,sys
d=json.load(sys.stdin)
assert d.get("ok") is True and d.get("action")=="delete"
' || die "contacts mutate delete fixture"
PROTEUS_CONTACTS_MUTATE_FIXTURE=1 python3 "${CMUT}" providers | python3 -c 'import json,sys
d=json.load(sys.stdin)
assert d.get("ok") is True and "carddav" in (d.get("providers") or [])
' || die "contacts mutate providers fixture"
ok "contacts mutate fixtures"

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
  "${BIN}" connect imap "imap.example" "993" "carol" "imap-secret" >/dev/null
  itok_out="$("${BIN}" token imap)"
  echo "${itok_out}" | python3 -c 'import json,sys
d=json.load(sys.stdin)
assert d.get("ok") is True
assert d.get("provider")=="imap"
assert d.get("accessToken")=="imap-secret"
assert "imaps://" in (d.get("baseUrl") or "")
assert d.get("username")=="carol"
assert "refresh_token" not in d and "refreshToken" not in d
' || die "token imap JSON"
  "${BIN}" connect caldav "https://cal.example/dav/home" "dave" "cal-secret" >/dev/null
  ctok_out="$("${BIN}" token caldav)"
  echo "${ctok_out}" | python3 -c 'import json,sys
d=json.load(sys.stdin)
assert d.get("ok") is True
assert d.get("provider")=="caldav"
assert d.get("accessToken")=="cal-secret"
assert "cal.example" in (d.get("baseUrl") or "")
assert d.get("username")=="dave"
assert "refresh_token" not in d and "refreshToken" not in d
' || die "token caldav JSON"
  "${BIN}" connect carddav "https://card.example/dav/ab" "erin" "card-secret" >/dev/null
  crtok_out="$("${BIN}" token carddav)"
  echo "${crtok_out}" | python3 -c 'import json,sys
d=json.load(sys.stdin)
assert d.get("ok") is True
assert d.get("provider")=="carddav"
assert d.get("accessToken")=="card-secret"
assert "card.example" in (d.get("baseUrl") or "")
assert d.get("username")=="erin"
assert "refresh_token" not in d and "refreshToken" not in d
' || die "token carddav JSON"
  "${BIN}" connect apple "frank@icloud.com" "apple-secret" >/dev/null
  aptok_out="$("${BIN}" token apple)"
  echo "${aptok_out}" | python3 -c 'import json,sys
d=json.load(sys.stdin)
assert d.get("ok") is True
assert d.get("provider")=="apple"
assert d.get("accessToken")=="apple-secret"
assert "caldav.icloud.com" in (d.get("caldavUrl") or d.get("baseUrl") or "")
assert "contacts.icloud.com" in (d.get("carddavUrl") or "")
assert d.get("imapHost")=="imap.mail.me.com"
assert int(d.get("imapPort") or 0)==993
assert d.get("username")=="frank@icloud.com"
assert "refresh_token" not in d and "refreshToken" not in d
' || die "token apple JSON"
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
