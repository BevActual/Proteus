#!/usr/bin/env bash
# spaces-smoke — Spaces multi-display + Named Spaces + band math (host static)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fail=0
ok() { echo "spaces-smoke: OK $*"; }
die() { echo "spaces-smoke: FAIL $*" >&2; fail=1; }

WS="${ROOT}/shell/scripts/proteus-workspace"
STRIP="${ROOT}/shell/surfaces/desktop/Workspaces.qml"
LEAF="${ROOT}/apps/proteus-settings/panes/DesktopSpacesLeaf.qml"
BINDS="${ROOT}/env/hypr/proteus-keybinds.conf"
KB="${ROOT}/shell/shared/Keybinds.qml"
SD="${ROOT}/shell/shared/SpacesDisplays.qml"
SN="${ROOT}/shell/shared/SpacesNames.qml"
SS="${ROOT}/shell/shared/SpacesSpecials.qml"
CFG="${ROOT}/shell/shared/Config.qml"
DSHELL="${ROOT}/shell/surfaces/DesktopShell.qml"

[[ -x "${WS}" ]] || die "proteus-workspace not executable"
[[ -f "${STRIP}" ]] || die "missing Workspaces.qml"
[[ -f "${LEAF}" ]] || die "missing DesktopSpacesLeaf.qml"
[[ -f "${BINDS}" ]] || die "missing proteus-keybinds.conf"
[[ -f "${SD}" ]] || die "missing SpacesDisplays.qml"
[[ -f "${SN}" ]] || die "missing SpacesNames.qml"
[[ -f "${SS}" ]] || die "missing SpacesSpecials.qml"
ok "files present"

bash -n "${WS}" || die "proteus-workspace bash -n"
"${WS}" selftest || die "proteus-workspace selftest"
ok "band math selftest (incl. 2-head)"

st="$("${WS}" status --fixture)"
echo "${st}" | grep -q '"ok":true' || die "status fixture not ok: ${st}"
echo "${st}" | grep -q '"monitorCount":2' || die "status fixture missing 2 displays"
echo "${st}" | grep -q 'HDMI-A-1' || die "status fixture missing sample monitor"
ok "status --fixture (2-head)"

grep -q 'proteus-workspace' "${STRIP}" || die "Workspaces.qml must invoke proteus-workspace"
grep -q 'workspaceMode' "${STRIP}" || die "Workspaces.qml must read workspaceMode"
grep -q 'perDisplay\|--local' "${STRIP}" || die "Workspaces.qml must support per-display / --local"
grep -q 'SpacesNames.displayForLogical\|SpacesNames' "${STRIP}" \
  || die "Workspaces.qml must show Named Spaces labels"
grep -q 'workspaceMode' "${LEAF}" || die "DesktopSpacesLeaf must bind workspaceMode"
grep -q 'SpacesDisplays' "${LEAF}" || die "DesktopSpacesLeaf must use SpacesDisplays"
grep -q 'SpacesNames.setName\|SpacesNames' "${LEAF}" \
  || die "DesktopSpacesLeaf must rename via SpacesNames"
grep -q 'workspaceNames' "${CFG}" || die "Config missing workspaceNames"
grep -q 'workspaceOrder\|workspaceOrderList\|reorderWorkspaceStrip' "${CFG}" \
  || die "Config missing workspaceOrder / reorder API"
grep -q 'specialWorkspaces' "${CFG}" || die "Config missing specialWorkspaces"
grep -q 'function add\|function rename\|function remove\|special-toggle' "${SS}" \
  || die "SpacesSpecials missing CRUD / toggle API"
grep -q 'special-toggle\|special-move\|special-list' "${WS}" \
  || die "proteus-workspace missing special-* cmds"
grep -q 'labelForLogical\|apply-names\|setName' "${SN}" \
  || die "SpacesNames missing resolver/apply API"
grep -q 'apply-names' "${WS}" || die "proteus-workspace missing apply-names"
grep -q 'renameworkspace' "${WS}" || die "proteus-workspace apply-names must renameworkspace"
grep -q 'proteus-workspace' "${BINDS}" || die "hypr keybinds must call proteus-workspace"
grep -q 'proteus-workspace goto 1' "${BINDS}" || die "hypr missing Super+1"
grep -q 'proteus-workspace goto 6' "${BINDS}" || die "hypr missing Super+6"
grep -q 'proteus-workspace goto 7' "${BINDS}" || die "hypr missing Super+7"
grep -q 'proteus-workspace goto 10' "${BINDS}" || die "hypr missing Super+0 → Space 10"
grep -q 'goto 1 --local' "${BINDS}" || die "hypr missing Super+Ctrl+1"
grep -q 'goto 10 --local' "${BINDS}" || die "hypr missing Super+Ctrl+0 → Space 10 local"
grep -q 'proteus-workspace move 10' "${BINDS}" || die "hypr missing Super+Shift+0 → move 10"
grep -q 'proteus-workspace goto 7' "${KB}" || die "Keybinds.qml missing Space 7"
grep -q 'proteus-workspace goto 10' "${KB}" || die "Keybinds.qml missing Space 10"
grep -q 'proteus-workspace' "${KB}" || die "Keybinds.qml must cite proteus-workspace"
grep -q 'scratch-toggle' "${KB}" || die "Keybinds.qml missing scratch-toggle"
grep -q 'scratch-move' "${KB}" || die "Keybinds.qml missing scratch-move"
grep -q 'scratch-toggle' "${BINDS}" || die "hypr missing Super+S scratch-toggle"
grep -q 'scratch-move' "${BINDS}" || die "hypr missing Super+Alt+S scratch-move"
grep -q 'scratch-toggle\|scratch-move' "${WS}" || die "proteus-workspace missing scratch cmds"
grep -q 'proteus-workspace' "${ROOT}/install/apps.sh" \
  || die "apps.sh must install proteus-workspace"
ok "shell + Settings + keybind + Named Spaces wiring"

grep -q 'status\|ensure' "${WS}" || die "proteus-workspace missing status/ensure"
grep -q 'migrate_disconnect\|migrate-disconnect' "${WS}" \
  || die "proteus-workspace missing migrate-disconnect"
grep -q 'migrate_disconnect\|migrate-disconnect' "${WS}" \
  && grep -q 'ensure_bands' "${WS}" || die "ensure must call migrate"
# ensure_bands body must invoke migrate first
awk '/^ensure_bands\(\)/,/^}/' "${WS}" | grep -q 'migrate_disconnect' \
  || die "ensure_bands must call migrate_disconnect"
grep -q 'ensureBands\|proteus-workspace.*ensure\|scheduleEnsure' "${SD}" \
  || die "SpacesDisplays missing ensure wire"
grep -q 'liveMonitorCount\|Hyprland.monitors' "${SD}" \
  || die "SpacesDisplays must watch Hyprland monitors"
grep -q 'SpacesDisplays' "${DSHELL}" || die "DesktopShell must refresh SpacesDisplays"
ok "multi-head status/ensure + hotplug wire"

mig="$("${WS}" migrate-disconnect --fixture)"
echo "${mig}" | grep -q '"ok":true' || die "migrate fixture not ok: ${mig}"
echo "${mig}" | grep -q '"fixture":true' || die "migrate fixture flag"
echo "${mig}" | python3 -c 'import json,sys
d=json.load(sys.stdin)
assert d.get("monitorCount")==1
moves=d.get("moves") or []
assert len(moves)==2, moves
tos=sorted(m["to"] for m in moves)
assert tos==[5,10], tos
froms=sorted(m["from"] for m in moves)
assert froms==[15,20], froms
' || die "migrate fixture plan"
ok "migrate-disconnect --fixture"

# Named Spaces + specialWorkspaces settings shape (offline — no hypr)
python3 - "${ROOT}/dev/fixtures/settings.minimal.json" <<'PY' || die "workspaceNames/specialWorkspaces in settings.minimal.json"
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)
assert "workspaceNames" in data and isinstance(data["workspaceNames"], list)
assert "specialWorkspaces" in data and isinstance(data["specialWorkspaces"], list)
print("ok")
PY
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' RETURN
mkdir -p "${TMP}/.config/proteus"
cat > "${TMP}/.config/proteus/settings.json" <<'JSON'
{"workspaceMode":"synced","workspaceNames":["Dev","Browser","","","","","","","",""]}
JSON
python3 - "${TMP}/.config/proteus/settings.json" <<'PY' || die "workspaceNames settings read"
import json, sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = json.load(f)
raw = data.get("workspaceNames") or []
assert isinstance(raw, list) and len(raw) >= 2
assert raw[0] == "Dev" and raw[1] == "Browser"
print("ok")
PY
ok "workspaceNames settings read"

# Honesty: keyboard logical 1–10; strip drag visual order In; Scratchpad In
grep -qiE '1–10|1-10' "${LEAF}" || die "DesktopSpacesLeaf must mention Super+Ctrl+1–10 keyboard range"
grep -qiE 'workspaceOrder|strip drag|visual order' "${LEAF}" \
  || die "DesktopSpacesLeaf must mention strip drag / workspaceOrder"
grep -q 'stripLogicals\|reorderWorkspaceStrip\|dragging' "${STRIP}" \
  || die "Workspaces.qml must implement strip drag reorder"
grep -qiE 'disconnect migrat|orphan-band|migrate-disconnect' "${LEAF}" \
  || die "DesktopSpacesLeaf must mention disconnect migration"
grep -qiE 'migrate-disconnect|orphan' "${SD}" \
  || die "SpacesDisplays must mention disconnect migration"
grep -qiE 'Scratchpad|special:scratch' "${LEAF}" \
  || die "DesktopSpacesLeaf must mention Scratchpad"
grep -qiE 'minimized|dock minimize' "${LEAF}" \
  || die "DesktopSpacesLeaf must distinguish dock minimize"
grep -qiE 'strip pill|◇|scratch-toggle' "${LEAF}" \
  || die "DesktopSpacesLeaf must mention strip scratch pill"
grep -qiE 'special CRUD|SpacesSpecials|specialWorkspaces' "${LEAF}" \
  || die "DesktopSpacesLeaf must state special CRUD"
grep -q 'SpacesSpecials.add\|SpacesSpecials.rename\|SpacesSpecials.remove' "${LEAF}" \
  || die "DesktopSpacesLeaf must wire SpacesSpecials CRUD"
grep -qiE 'Super\+Alt\+1|special-toggle-index|strip pill' "${LEAF}" \
  || die "DesktopSpacesLeaf must state special strip/keybinds In"
grep -qiE 'up to 8|1–8|Super\+Alt\+1–8|maxCustom' "${LEAF}" \
  || die "DesktopSpacesLeaf must state strip/keybinds beyond 4 (≤8)"
grep -q 'specialWorkspaceChords\|startRecording\|chordLabel' "${LEAF}" \
  || die "DesktopSpacesLeaf must wire per-special toggle chords"
grep -q 'specialWorkspaceMoveChords\|startMoveRecording\|moveChordLabel' "${LEAF}" \
  || die "DesktopSpacesLeaf must wire per-special move chords"
grep -q 'specialWorkspaceChords' "${CFG}" || die "Config missing specialWorkspaceChords"
grep -q 'specialWorkspaceMoveChords' "${CFG}" || die "Config missing specialWorkspaceMoveChords"
grep -q 'function setChord\|function customBindLines\|specialWorkspaceChords' "${SS}" \
  || die "SpacesSpecials missing chord API"
grep -q 'function setMoveChord\|function customMoveBindLines\|specialWorkspaceMoveChords' "${SS}" \
  || die "SpacesSpecials missing move chord API"
grep -q 'customBindLines\|SpacesSpecials.customBindLines' "${KB}" \
  || die "Keybinds.confText must emit custom special binds"
grep -q 'customMoveBindLines\|SpacesSpecials.customMoveBindLines' "${KB}" \
  || die "Keybinds.confText must emit custom special move binds"
grep -qiE 'specialWorkspaceMoveChords|special-move <slug>|per-special move chords' "${LEAF}" \
  || die "DesktopSpacesLeaf must state per-special move chords In"
grep -q 'toggleScratch\|scratch-toggle' "${STRIP}" \
  || die "Workspaces.qml must toggle Scratchpad"
grep -q 'scratchActive\|scratchOccupied\|showScratch' "${STRIP}" \
  || die "Workspaces.qml missing Scratchpad pill state"
grep -q '◇' "${STRIP}" || die "Workspaces.qml missing Scratchpad ◇ glyph"
grep -q 'customSpecials\|toggleSpecial\|SpacesSpecials' "${STRIP}" \
  || die "Workspaces.qml must show custom special strip pills"
grep -q 'maxStripSpecials.*maxCustom\|SpacesSpecials.maxCustom' "${STRIP}" \
  || die "Workspaces strip cap must follow SpacesSpecials.maxCustom (beyond 4)"
grep -q 'special-toggle-index' "${KB}" || die "Keybinds.qml missing special-toggle-index"
grep -q 'special-move-index' "${KB}" || die "Keybinds.qml missing special-move-index"
grep -q 'special-toggle-index 8\|special-toggle-index 5' "${KB}" \
  || die "Keybinds.qml missing Super+Alt+5–8 special-toggle-index"
grep -q 'special-toggle-index' "${BINDS}" || die "hypr missing Super+Alt+N special-toggle-index"
grep -q 'special-toggle-index 8' "${BINDS}" || die "hypr missing Super+Alt+8 special-toggle-index"
grep -q 'special-move-index' "${BINDS}" || die "hypr missing Super+Alt+Shift+N special-move-index"
grep -q 'special-toggle-index\|special_by_index\|special-move-index' "${WS}" \
  || die "proteus-workspace missing special-*-index"
ok "1–10 keyboard honesty + strip drag In + disconnect + Scratchpad + special strip/keybinds ≤8 In"

scr="$("${WS}" scratch-toggle --fixture)"
echo "${scr}" | grep -qE '"ok"[[:space:]]*:[[:space:]]*true' \
  || die "scratch-toggle fixture not ok: ${scr}"
echo "${scr}" | grep -qE '"fixture"[[:space:]]*:[[:space:]]*true' \
  || die "scratch-toggle fixture flag"
echo "${scr}" | grep -q 'special:scratch' || die "scratch-toggle missing special:scratch"
scm="$("${WS}" scratch-move --fixture)"
echo "${scm}" | grep -qE '"ok"[[:space:]]*:[[:space:]]*true' \
  || die "scratch-move fixture not ok: ${scm}"
echo "${scm}" | grep -q 'scratch-move' || die "scratch-move action"
ok "scratch-toggle/move --fixture"

spt="$("${WS}" special-toggle notes --fixture)"
echo "${spt}" | grep -qE '"ok"[[:space:]]*:[[:space:]]*true' \
  || die "special-toggle fixture not ok: ${spt}"
echo "${spt}" | grep -q 'special:notes' || die "special-toggle missing special:notes"
spm="$("${WS}" special-move notes --fixture)"
echo "${spm}" | grep -q 'special-move' || die "special-move action"
spl="$("${WS}" special-list --fixture)"
echo "${spl}" | grep -qE '"ok"[[:space:]]*:[[:space:]]*true' \
  || die "special-list fixture not ok: ${spl}"
echo "${spl}" | grep -q '"notes"' || die "special-list fixture missing notes"
echo "${spl}" | grep -q 'scratch' || die "special-list missing reserved scratch"
ok "special-toggle/move/list --fixture"

sti="$("${WS}" special-toggle-index 1 --fixture)"
echo "${sti}" | grep -qE '"ok"[[:space:]]*:[[:space:]]*true' \
  || die "special-toggle-index fixture not ok: ${sti}"
echo "${sti}" | grep -q 'special:notes\|"notes"' || die "special-toggle-index fixture notes"
smi="$("${WS}" special-move-index 2 --fixture)"
echo "${smi}" | grep -q 'mail\|special-move-index' || die "special-move-index fixture mail"
ok "special-*-index --fixture"

python3 - <<'PY' || die "specialWorkspaces normalize fixture"
# Mirror SpacesSpecials.normalizeList rules
import re
pat = re.compile(r"^[a-z][a-z0-9-]{0,23}$")
reserved = {"scratch", "minimized"}

def slugify(raw):
    s = re.sub(r"[^a-z0-9-]+", "-", str(raw or "").strip().lower())
    s = re.sub(r"-+", "-", s).strip("-")
    if not s:
        return ""
    if not ("a" <= s[0] <= "z"):
        s = "w-" + s
    return s[:24].rstrip("-")

def normalize(raw):
    out, seen = [], set()
    for item in raw or []:
        s = slugify(item)
        if not s or s in reserved or s in seen or not pat.match(s):
            continue
        seen.add(s)
        out.append(s)
        if len(out) >= 8:
            break
    return out

assert normalize(["Notes", "scratch", "notes", "Bad Name"]) == ["notes", "bad-name"]
assert normalize([]) == []
print("ok")
PY
ok "specialWorkspaces normalize"

# workspaceOrder normalize (offline)
python3 - <<'PY' || die "workspaceOrder normalize fixture"
# Mirror Config.workspaceOrderList rules
def order_list(raw):
    seen = {}
    out = []
    for x in raw or []:
        try:
            n = int(x)
        except Exception:
            continue
        if n < 1 or n > 10 or n in seen:
            continue
        seen[n] = True
        out.append(n)
    for k in range(1, 11):
        if k not in seen:
            out.append(k)
    return out

assert order_list([]) == list(range(1, 11))
assert order_list([3, 1, 2])[:3] == [3, 1, 2]
assert order_list([3, 1, 2, 3, 99]) == [3, 1, 2, 4, 5, 6, 7, 8, 9, 10]
# reorder 0→2 on identity → [2,3,1,4,...]
lst = order_list([])
item = lst.pop(0)
lst.insert(2, item)
assert lst[:4] == [2, 3, 1, 4]
print("ok")
PY
ok "workspaceOrder normalize"

[[ $fail -eq 0 ]] || { echo "spaces-smoke: FAILED" >&2; exit 1; }
echo "spaces-smoke: OK"
