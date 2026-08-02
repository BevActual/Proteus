#!/usr/bin/env bash
# config-roundtrip-smoke — mutate settings.minimal.json and assert still ⊆ Config keys
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONFIG_QML="${ROOT}/shell/shared/Config.qml"
FIXTURE="${ROOT}/tests/fixtures/settings.minimal.json"

die() { echo "config-roundtrip-smoke: FAIL $*" >&2; exit 1; }
ok() { echo "config-roundtrip-smoke: OK $*"; }

[[ -f "${CONFIG_QML}" ]] || die "missing Config.qml"
[[ -f "${FIXTURE}" ]] || die "missing settings.minimal.json"

python3 - "${CONFIG_QML}" "${FIXTURE}" <<'PY' || die "round-trip"
import json, re, sys, tempfile
from pathlib import Path

config_path, fixture_path = map(Path, sys.argv[1:3])
text = config_path.read_text(encoding="utf-8")

m = re.search(r"JsonAdapter\s*\{", text)
if not m:
    print("no JsonAdapter", file=sys.stderr)
    sys.exit(1)
start = m.end()
depth = 1
i = start
while i < len(text) and depth:
    c = text[i]
    if c == "{":
        depth += 1
    elif c == "}":
        depth -= 1
    i += 1
adapter = text[start : i - 1]
prop_re = re.compile(
    r"^\s*property\s+(?:int|bool|real|string|var|color|double|list)\s+(\w+)\s*:",
    re.M,
)
config_keys = set(prop_re.findall(adapter))
if not config_keys:
    print("no Config keys", file=sys.stderr)
    sys.exit(1)

data = json.loads(fixture_path.read_text(encoding="utf-8"))
if not isinstance(data, dict):
    print("fixture not object", file=sys.stderr)
    sys.exit(1)

# Mutate a few live prefs (must remain valid Config keys).
data["gapsIn"] = int(data.get("gapsIn", 8)) + 1
data["desktopWidgetsSnapToGrid"] = True
data["launcherRecents"] = "smoke-app.desktop"
# Desktop catch-up keys (#1248)
data["workspaceMode"] = "perDisplay" if data.get("workspaceMode") != "perDisplay" else "synced"
data["focusActiveProfileId"] = "sleep"
data["focusProfiles"] = [
    {
        "id": "smoke-focus",
        "name": "Smoke",
        "allowedApps": ["smoke.desktop"],
        "breakCritical": True,
    }
]
data["controlCenterLayout"] = {
    "tiles": {"wifi": {"visible": False}},
    "order": ["wifi", "bluetooth"],
}
widgets = list(data.get("desktopWidgets") or [])
widgets.append({
    "id": "smoke-dw-roundtrip",
    "type": "battery",
    "enabled": True,
    "x": 0.25,
    "y": 0.25,
    "size": "sm",
})
data["desktopWidgets"] = widgets

extra = sorted(set(data) - config_keys)
if extra:
    print("mutated keys not in Config:", ", ".join(extra), file=sys.stderr)
    sys.exit(1)

required = {
    "gapsIn",
    "accentId",
    "chromeMode",
    "wallpaperKind",
    "lockWidgets",
    "desktopWidgets",
    "desktopWidgetsSnapToGrid",
    "launcherRecents",
    "workspaceMode",
    "focusProfiles",
    "focusActiveProfileId",
    "controlCenterLayout",
}
missing_req = sorted(required - set(data))
if missing_req:
    print("missing required after mutate:", ", ".join(missing_req), file=sys.stderr)
    sys.exit(1)

# Round-trip through temp JSON
with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False, encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    tmp = Path(f.name)
try:
    again = json.loads(tmp.read_text(encoding="utf-8"))
finally:
    tmp.unlink(missing_ok=True)

if again.get("gapsIn") != data["gapsIn"]:
    print("gapsIn round-trip mismatch", file=sys.stderr)
    sys.exit(1)
if again.get("desktopWidgetsSnapToGrid") is not True:
    print("snap flag round-trip mismatch", file=sys.stderr)
    sys.exit(1)
if again.get("launcherRecents") != "smoke-app.desktop":
    print("launcherRecents round-trip mismatch", file=sys.stderr)
    sys.exit(1)
if again.get("workspaceMode") != data["workspaceMode"]:
    print("workspaceMode round-trip mismatch", file=sys.stderr)
    sys.exit(1)
if again.get("focusActiveProfileId") != "sleep":
    print("focusActiveProfileId round-trip mismatch", file=sys.stderr)
    sys.exit(1)
fp = again.get("focusProfiles") or []
if not any(isinstance(p, dict) and p.get("id") == "smoke-focus" for p in fp):
    print("focusProfiles stub missing after round-trip", file=sys.stderr)
    sys.exit(1)
ccl = again.get("controlCenterLayout") or {}
if not isinstance(ccl, dict) or not (ccl.get("tiles") or {}).get("wifi"):
    print("controlCenterLayout stub missing after round-trip", file=sys.stderr)
    sys.exit(1)
dw = again.get("desktopWidgets") or []
if not any(isinstance(w, dict) and w.get("id") == "smoke-dw-roundtrip" for w in dw):
    print("desktopWidgets stub missing after round-trip", file=sys.stderr)
    sys.exit(1)

print(f"round-trip OK (keys={len(again)}; config={len(config_keys)})")
PY

ok "mutated fixture ⊆ Config + JSON round-trip"
echo "config-roundtrip-smoke: OK"
