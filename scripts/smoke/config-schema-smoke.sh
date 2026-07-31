#!/usr/bin/env bash
# config-schema-smoke — Config FileView keys ↔ settings.minimal.json fixture
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONFIG_QML="${ROOT}/shell/shared/Config.qml"
FIXTURE="${ROOT}/tests/fixtures/settings.minimal.json"
SCHEMA_DOC="${ROOT}/docs/proteus/CONFIG-SCHEMA.md"

python3 - "${CONFIG_QML}" "${FIXTURE}" "${SCHEMA_DOC}" <<'PY'
import json, re, sys
from pathlib import Path

config_path, fixture_path, schema_path = map(Path, sys.argv[1:4])
text = config_path.read_text()

# Extract JsonAdapter { ... } block (first occurrence after FileView)
m = re.search(r"JsonAdapter\s*\{", text)
if not m:
    print("config-schema-smoke: FAIL no JsonAdapter in Config.qml", file=sys.stderr)
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
    print("config-schema-smoke: FAIL no properties parsed from JsonAdapter", file=sys.stderr)
    sys.exit(1)

fixture = json.loads(fixture_path.read_text())
if not isinstance(fixture, dict):
    print("config-schema-smoke: FAIL fixture must be a JSON object", file=sys.stderr)
    sys.exit(1)
fixture_keys = set(fixture.keys())

extra = sorted(fixture_keys - config_keys)
if extra:
    print("config-schema-smoke: FAIL fixture keys not in Config:", ", ".join(extra), file=sys.stderr)
    sys.exit(1)

# Required core (CONFIG-SCHEMA groups)
required = {
    "gapsIn",
    "accentId",
    "chromeMode",
    "wallpaperKind",
    "lockWidgets",
    "desktopWidgets",
    "audioLatency",
    "fontFamily",
    "notificationsDnd",
    "lockBackgroundMode",
}
missing_core = sorted(required - config_keys)
if missing_core:
    print("config-schema-smoke: FAIL Config missing core keys:", ", ".join(missing_core), file=sys.stderr)
    sys.exit(1)
missing_fixture = sorted(required - fixture_keys)
if missing_fixture:
    print(
        "config-schema-smoke: FAIL fixture missing core keys:",
        ", ".join(missing_fixture),
        file=sys.stderr,
    )
    sys.exit(1)

# Config keys not covered by CONFIG-SCHEMA.md.
#
# The doc is a grouped inventory listing representative keys plus prefix
# patterns (`location*`, `dock/bar*`, `lock wallpaper*`), so a plain substring
# test reports keys that are in fact documented. Honour the convention the doc
# already uses: literal backticked names, plus `prefix*` globs where `/`
# separates alternatives and spaces are dropped (`lock wallpaper*` covers
# lockWallpaperId).
schema_text = schema_path.read_text() if schema_path.is_file() else ""

literals = set(re.findall(r"`([A-Za-z][A-Za-z0-9_]*)`", schema_text))
# Wildcards count whether or not they are backticked, and `/` separates
# alternatives (`dock/bar*` → dock, bar).
prefixes = []
for pattern in re.findall(r"([A-Za-z][A-Za-z0-9_]*(?:[ /][A-Za-z][A-Za-z0-9_]*)*)\*", schema_text):
    for alt in pattern.split("/"):
        alt = alt.strip().replace(" ", "").lower()
        if alt:
            prefixes.append(alt)


def documented(key):
    if key in literals:
        return True
    low = key.lower()
    return any(low.startswith(p) for p in prefixes)


undocumented = sorted(k for k in config_keys if not documented(k))
if undocumented:
    print(
        "config-schema-smoke: FAIL Config keys absent from CONFIG-SCHEMA.md:",
        ", ".join(undocumented),
        file=sys.stderr,
    )
    sys.exit(1)
print(f"config-schema-smoke: OK schema covers all {len(config_keys)} Config keys")

print(f"config-schema-smoke: OK Config={len(config_keys)} keys; fixture⊆Config ({len(fixture_keys)} keys)")
PY
