#!/usr/bin/env bash
# config-schema-smoke — Config FileView keys ↔ settings.minimal.json fixture
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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

# Warn-only: Config keys not mentioned in CONFIG-SCHEMA.md
schema_text = schema_path.read_text() if schema_path.is_file() else ""
undocumented = sorted(k for k in config_keys if k not in schema_text)
if undocumented:
    print(
        "config-schema-smoke: WARN Config keys not mentioned in CONFIG-SCHEMA.md:",
        ", ".join(undocumented[:20]) + ("…" if len(undocumented) > 20 else ""),
    )

print(f"config-schema-smoke: OK Config={len(config_keys)} keys; fixture⊆Config ({len(fixture_keys)} keys)")
PY
