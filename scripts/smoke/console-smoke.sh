#!/usr/bin/env bash
# console-smoke — Console Phase 1 seat/caps + Phase 2 session + list IA (host static)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fail=0
ok() { echo "console-smoke: OK $*"; }
die() { echo "console-smoke: FAIL $*" >&2; fail=1; }

SEAT="${ROOT}/shell/scripts/proteus-console-seat"
CAPS="${ROOT}/shell/scripts/proteus-console-capabilities"
LAUNCH="${ROOT}/shell/scripts/proteus-console-launch"
SESSION="${ROOT}/shell/scripts/proteus-console-session"
SIDE="${ROOT}/shell/surfaces/console/ConsoleSideList.qml"
DETAIL="${ROOT}/shell/surfaces/console/ConsoleDetailPane.qml"
LEAN="${ROOT}/shell/surfaces/console/ConsoleLeanSheet.qml"
HOME_QML="${ROOT}/shell/surfaces/console/ConsoleHome.qml"
BAR="${ROOT}/shell/surfaces/console/ConsoleBar.qml"
LIB="${ROOT}/shell/surfaces/console/ConsoleLibrary.qml"
APPS_MODEL="${ROOT}/shell/surfaces/console/ConsoleAppsModel.qml"
APPS="${ROOT}/install/apps.sh"
CONSOLE="${ROOT}/install/console.sh"
APPLY="${ROOT}/install/machine/apply-console-kit.sh"
DOGFOOD="${ROOT}/scripts/dogfood/dogfood-console.sh"

for f in "${SEAT}" "${CAPS}" "${LAUNCH}" "${SESSION}" "${SIDE}" "${DETAIL}" "${LEAN}" \
         "${HOME_QML}" "${BAR}" "${LIB}" "${APPS_MODEL}" "${APPS}" "${CONSOLE}" "${APPLY}" "${DOGFOOD}"; do
  [[ -e "${f}" ]] || die "missing ${f#${ROOT}/}"
done
[[ -x "${SEAT}" && -x "${CAPS}" && -x "${LAUNCH}" && -x "${SESSION}" && -x "${APPLY}" && -x "${DOGFOOD}" ]] \
  || die "console helpers must be executable"
ok "files present"

grep -q 'ConsoleSideList' "${HOME_QML}" || die "ConsoleHome must use ConsoleSideList"
grep -q 'ConsoleDetailPane' "${HOME_QML}" || die "ConsoleHome must use ConsoleDetailPane"
grep -q 'ConsoleSettingsPane' "${HOME_QML}" || die "ConsoleHome must use ConsoleSettingsPane"
grep -q 'ConsoleLeanSheet' "${HOME_QML}" || die "ConsoleHome must use ConsoleLeanSheet"
grep -q 'openConsoleSettings\|focusConsoleSettings' "${HOME_QML}" "${LIB}" \
  "${ROOT}/shell/shared/ShellState.qml" \
  || die "Console Settings must stay in-chrome (openConsoleSettings)"
grep -q 'ShellState.openSettings(page)' "${LIB}" \
  && die "ConsoleLibrary must not launch proteus-settings for kind:settings"
grep -q 'fullSettingsRequested\|full-escape' \
  "${ROOT}/shell/surfaces/console/ConsoleSettingsPane.qml" \
  || die "ConsoleSettingsPane missing Full Settings escape hatch"
PANE="${ROOT}/shell/surfaces/console/ConsoleSettingsPane.qml"
NET="${ROOT}/shell/surfaces/console/ConsoleSettingsNet.qml"
test -f "${NET}" || die "ConsoleSettingsNet.qml missing"
grep -q 'mode: "hub"\|property string mode' "${PANE}" \
  || die "ConsoleSettingsPane missing hub/wifi/sinks mode"
grep -q 'openWifiDrill\|wifi-open\|wifiPassword' "${PANE}" \
  || die "ConsoleSettingsPane missing Wi-Fi drill"
grep -q 'openSinksDrill\|sinks-open\|listSinks\|setDefaultSink' "${PANE}" \
  || die "ConsoleSettingsPane missing sink drill"
grep -q 'exitDrill\|inDrill' "${PANE}" "${HOME_QML}" \
  || die "Console Settings drill Back (exitDrill) missing"
grep -q 'wifiConnect\|wifiConnectPassword\|wifiDisconnect' "${NET}" "${PANE}" \
  || die "Console Wi-Fi must wire Config.wifiConnect*"
grep -q 'nmcli' "${NET}" || die "ConsoleSettingsNet must use nmcli"
grep -q 'focusZone.*searchField\|focusZone === "list"' "${HOME_QML}" \
  || die "ConsoleHome missing list IA focus zones"
grep -q 'cycleDestination\|"lb"\|"rb"' "${HOME_QML}" \
  || die "ConsoleHome missing LB/RB destination cycle"
grep -q 'BTN_TL\|"lb"' "${ROOT}/shell/scripts/proteus-guide" \
  || die "proteus-guide must map left/right bumpers"
grep -q 'proteus-console-seat' "${LIB}" || die "ConsoleLibrary missing proteus-console-seat"
grep -q 'toggleSessionMode\|sessionEffective' "${LIB}" \
  || die "ConsoleLibrary missing session mode wiring"
grep -q 'sessionToggleRequested\|sessionToggleVisible' "${BAR}" \
  || die "ConsoleBar missing session toggle"
grep -q 'onSessionToggleRequested' "${HOME_QML}" \
  || die "ConsoleHome must wire session toggle"
grep -q 'Games\|Media\|Search\|Settings' "${BAR}" || die "ConsoleBar missing Games/Media/Search/Settings"
grep -q 'Apps\|id: "apps"' "${BAR}" || die "ConsoleBar missing Apps destination"
# Order: Games, Media, Apps (labels appear in that sequence in destinations model)
python3 - "${BAR}" <<'PY' || die "ConsoleBar must place Apps after Media"
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"destinations:\s*\[(.*?)\]", text, re.S)
assert m, "destinations missing"
ids = re.findall(r'id:\s*"(\w+)"', m.group(1))
assert ids.index("media") < ids.index("apps") < ids.index("search"), ids
print("ok bar order", ids)
PY
ok "list IA + Library + session UI wiring"

grep -q 'isStreamingApp\|isLocalPlayer' "${APPS_MODEL}" \
  || die "ConsoleAppsModel missing streaming classifier"
grep -q 'localPlayerIds' "${APPS_MODEL}" || die "ConsoleAppsModel missing local player denylist"
grep -q 'mpv' "${APPS_MODEL}" || die "ConsoleAppsModel must exclude mpv from Media"
grep -q 'spotify\|netflix\|plex' "${APPS_MODEL}" \
  || die "ConsoleAppsModel missing streaming allowlist hints"
grep -q 'gamesList\|mediaList\|settingsList\|appsList' "${APPS_MODEL}" \
  || die "ConsoleAppsModel missing destination lists"
grep -q 'isConsoleAppsDest' "${APPS_MODEL}" \
  || die "ConsoleAppsModel missing Apps destination classifier"
grep -q 'kind: "section"\|availableSettingsPanesForFace' "${APPS_MODEL}" \
  || die "settingsList must group by Settings face hubs"
grep -q 'availableSettingsPanesForFace\|settingsFaceHubs' "${APPS_MODEL}" \
  "${ROOT}/shell/shared/EnvGate.qml" \
  || die "Console settingsList must use Settings face hubs"
grep -q 'settingsFaceConsoleHubs\|settingsFaceHostHubs\|availableSettingsPanesForFace' \
  "${ROOT}/shell/shared/EnvGate.qml" \
  || die "EnvGate missing settingsFaceHubs API"
# Extract console face array and assert desktop hub is omitted
python3 - "${ROOT}/shell/shared/EnvGate.qml" <<'PY' || die "console face must omit desktop hub"
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r'settingsFaceConsoleHubs:\s*\[(.*?)\]', text, re.S)
assert m, "settingsFaceConsoleHubs missing"
body = m.group(1)
assert '"desktop"' not in body and "'desktop'" not in body, "desktop hub in console face"
assert '"sound"' in body or '"network"' in body
print("ok console face hubs")
PY
ok "streaming classifier + destination catalogs"

grep -q 'proteus-console-seat' "${APPS}" || die "apps.sh must install proteus-console-seat"
grep -q 'proteus-console-capabilities' "${APPS}" \
  || die "apps.sh must install proteus-console-capabilities"
grep -q 'proteus-console-launch' "${APPS}" || die "apps.sh must install proteus-console-launch"
grep -q 'proteus-console-session' "${APPS}" || die "apps.sh must install proteus-console-session"
grep -q 'proteus-console-session' "${APPLY}" || die "apply-console-kit must install session"
grep -q 'install-console-software' "${APPLY}" || die "apply-console-kit must cite full package path"
grep -q 'dogfood-console' "${APPLY}" || die "apply-console-kit must tip dogfood-console"
grep -q 'apply-console-kit' "${CONSOLE}" || die "console.sh must apply console kit"
grep -q 'proteus-console.packages' "${CONSOLE}" || die "console.sh must use proteus-console.packages"
grep -q 'install-console-software\|console stage' "${LIB}" \
  || die "ConsoleLibrary seatMissing must cite install-console-software"
bash -n "${DOGFOOD}" || die "dogfood-console.sh bash -n"
ok "install wiring"

CAPS_JSON="$("${CAPS}" 2>/dev/null || true)"
echo "${CAPS_JSON}" | python3 -c 'import json,sys
d=json.load(sys.stdin)
for k in ("vulkan","vulkanHw","gamescope","gamescopeUsable","gameScope","isVm",
          "steam","retroarch","pad","sessionMode","sessionEffective","replacesHyprland"):
  assert k in d, k
assert isinstance(d["replacesHyprland"], bool)
# replacesHyprland only when the Gamescope session is effective
assert d["replacesHyprland"] == (d["sessionEffective"] == "session")
assert d["sessionMode"] in ("seat","session")
assert d["sessionEffective"] in ("seat","session")
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
# Phase 3: session mode = Gamescope owns the session; legacy `gamescope`
# Fact value must map to `session`.
"${SESSION}" set-mode session >/dev/null
STATUS2="$("${SESSION}" status)"
echo "${STATUS2}" | python3 -c 'import json,sys
d=json.load(sys.stdin)
assert d.get("mode") == "session"
' || die "session set-mode session"
"${SESSION}" set-mode gamescope >/dev/null
echo "$("${SESSION}" status)" | python3 -c 'import json,sys
d=json.load(sys.stdin)
assert d.get("mode") == "session", "legacy gamescope must alias to session"
' || die "session legacy gamescope alias"
FLAGS="$("${SESSION}" resolve-flags || true)"
# Flags only when gamescopeUsable; host CI often has no hardware Vulkan → empty OK.
if echo "${STATUS2}" | grep -q '"effective": "session"'; then
  echo "${FLAGS}" | grep -q '\-f' || die "resolve-flags should include -f when effective"
fi
"${SESSION}" set-mode seat >/dev/null
ok "helpers syntax + session Fact"

grep -q 'resolve-flags\|proteus-console-session' "${LAUNCH}" \
  || die "launch must honor session resolve-flags"
ok "launch session wire"

# --- Phase 3: Gamescope-as-session + Guide focus-flip (host static) ---
GS_SESSION="${ROOT}/shell/scripts/proteus-console-gs-session"
FOCUS="${ROOT}/shell/scripts/proteus-console-focus"
HOME_PROFILE="${ROOT}/shell/console-home/shell.qml"
SWITCHER="${ROOT}/shell/surfaces/console/ConsoleSwitcher.qml"
GUIDE="${ROOT}/shell/scripts/proteus-guide"
for f in "${GS_SESSION}" "${FOCUS}" "${HOME_PROFILE}"; do
  [[ -e "${f}" ]] || die "missing ${f#${ROOT}/}"
done
[[ -x "${GS_SESSION}" && -x "${FOCUS}" ]] || die "gs-session/focus must be executable"
bash -n "${GS_SESSION}" || die "gs-session bash -n"
bash -n "${FOCUS}" || die "focus bash -n"
grep -q 'gamescope' "${GS_SESSION}" || die "gs-session must exec gamescope"
grep -q 'proteus-guide' "${GS_SESSION}" || die "gs-session must own proteus-guide"
grep -q 'console-home' "${GS_SESSION}" || die "gs-session must start console-home profile"
grep -q 'GAMESCOPECTRL_BASELAYER_APPID' "${FOCUS}" \
  || die "focus router must use GAMESCOPECTRL_BASELAYER_APPID"
grep -q 'ConsoleHome' "${HOME_PROFILE}" || die "console-home must reuse ConsoleHome list IA"
grep -q 'FloatingWindow' "${HOME_PROFILE}" || die "console-home must be an xdg FloatingWindow"
grep -q 'sessionMode' "${SWITCHER}" || die "ConsoleSwitcher missing sessionMode branch"
grep -q 'proteus-console-focus' "${SWITCHER}" \
  || die "ConsoleSwitcher session mode must use focus router"
grep -q 'proteus-console-focus' "${GUIDE}" \
  || die "proteus-guide must call focus router in session mode"
grep -q 'PROTEUS_CONSOLE_SESSION' "${LAUNCH}" \
  || die "launch must guard nested GS-in-GS"
grep -q 'PROTEUS_CONSOLE_SESSION' "${SEAT}" \
  || die "seat must branch for Gamescope-owned session"
grep -q 'proteus-console-gs-session' "${APPS}" || die "apps.sh must install gs-session"
grep -q 'proteus-console-focus' "${APPS}" || die "apps.sh must install focus router"
grep -q 'xorg-xprop' "${ROOT}/install/proteus-console.packages" \
  || die "console packages missing xorg-xprop (focus router)"
grep -q 'vulkan-tools' "${ROOT}/install/proteus-console.packages" \
  || die "console packages missing vulkan-tools (hw Vulkan probe)"
grep -q 'PROTEUS_EXPECT_GS_SESSION' "${DOGFOOD}" \
  || die "dogfood-console must support PROTEUS_EXPECT_GS_SESSION assert"
ok "gamescope session + focus router static"

# --- List IA deepening: curation · status strip · installed games ---
GAMES_SCAN="${ROOT}/shell/scripts/proteus-console-games.py"
FOOTER="${ROOT}/shell/surfaces/console/ConsoleFooter.qml"
[[ -x "${GAMES_SCAN}" ]] || die "proteus-console-games.py missing/not executable"
python3 -m py_compile "${GAMES_SCAN}" || die "proteus-console-games.py py_compile"
PROTEUS_CONSOLE_GAMES_FIXTURE=1 python3 "${GAMES_SCAN}" | python3 -c 'import json,sys
d=json.load(sys.stdin)
assert d["ok"] is True and d["fixture"] is True
for src in ("steam","retroarch"):
    assert "available" in d[src] and isinstance(d[src]["titles"], list), src
st = d["steam"]["titles"][0]
for k in ("appId","name","sizeBytes","lastPlayed"): assert k in st, k
rt = d["retroarch"]["titles"][0]
for k in ("name","path","core","system"): assert k in rt, k
assert d["count"] == len(d["steam"]["titles"]) + len(d["retroarch"]["titles"])
' || die "games scan fixture contract"
grep -q 'proteus-console-games.py' "${APPS}" || die "apps.sh must install proteus-console-games.py"
grep -q 'proteus-console-games.py' "${LIB}" || die "ConsoleLibrary must run the games scan"
grep -q 'installedGames\|hydrateGamesScan' "${LIB}" || die "ConsoleLibrary missing installedGames"
grep -q 'steam-title\|retro-title' "${LIB}" || die "ConsoleLibrary missing per-title seats"
grep -q '\-applaunch' "${LIB}" || die "steam titles must launch via -applaunch"
grep -q 'installedTitles' "${APPS_MODEL}" || die "ConsoleAppsModel missing installedTitles"
grep -q 'recentItems' "${APPS_MODEL}" || die "ConsoleAppsModel missing recentItems (Games Recent section)"
grep -q 'gamesSection\|section:games-' "${APPS_MODEL}" \
  || die "Games tab must group Recent / Installed / Launchers"
# Curation: Media = streaming only; no category fallback, no Discord, no title~game heuristic
grep -q 'AudioVideo-category fallback' "${APPS_MODEL}" \
  || die "ConsoleAppsModel must document streaming-only Media (no category fallback)"
python3 - "${APPS_MODEL}" <<'PY' || die "Media/Games curation regressed"
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"streamingHints:\s*\[(.*?)\]", text, re.S)
assert m and "discord" not in m.group(1), "discord must not be streaming"
assert 'title.indexOf("game")' not in text, "broad game title heuristic banned"
assert re.search(r'tag === "MEDIA" \|\| tag\.indexOf\("AUDIO"\)', text) is None, "category fallback banned"
print("ok curation")
PY
# Status strip + pad legend
grep -q 'ConsoleFooter' "${HOME_QML}" || die "ConsoleHome must mount ConsoleFooter"
grep -q 'library.statusHint' "${HOME_QML}" || die "footer must surface library.statusHint"
grep -q 'padActive' "${FOOTER}" || die "ConsoleFooter missing pad legend"
# Local media relocated to Search shortcut; web apps leaf indexed
grep -q 'media:local\|hasLocalPlayer' "${APPS_MODEL}" \
  || die "local media must live as Search shortcut"
grep -q 'packages-webapps' "${ROOT}/shell/shared/EnvGate.qml" \
  || die "settingsSearchIndex missing packages-webapps (console hint honesty)"
# Shelf era stays deleted
for gone in ConsoleHero.qml ConsoleShelf.qml ConsoleRow.qml ConsoleCard.qml; do
  [[ -e "${ROOT}/shell/surfaces/console/${gone}" ]] && die "shelf-era ${gone} resurrected"
done
ok "list IA deepening (curation · footer · installed games)"

# --- Pad input: exactly one nav event per press ---
GUIDE_PY="${ROOT}/shell/scripts/proteus-guide"
python3 -m py_compile "${GUIDE_PY}" || die "proteus-guide py_compile"
grep -q 'acquire_single_instance_lock' "${GUIDE_PY}" \
  || die "proteus-guide missing single-instance lock (double listeners = double inputs)"
grep -q 'DEDUPE_MS' "${GUIDE_PY}" \
  || die "proteus-guide missing press dedupe (BTN_DPAD + HAT dual report)"
grep -q 'REPEAT_DELAY_MS' "${GUIDE_PY}" \
  || die "proteus-guide missing repeat delay (short press must fire once)"
grep -q "proteus-guide\\\$" "${ROOT}/shell/scripts/proteus-posture" \
  || die "proteus-posture stop_guide must pkill by cmdline (script runs as python3)"
grep -q "proteus-guide\\\$" "${ROOT}/shell/scripts/proteus-console-gs-session" \
  || die "gs-session must kill stale guide before starting its own"
ok "pad input single-fire (lock · dedupe · repeat delay)"

[[ $fail -eq 0 ]] || { echo "console-smoke: FAILED" >&2; exit 1; }
echo "console-smoke: OK"
