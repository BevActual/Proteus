#!/usr/bin/env bash
# chrome-tokens-smoke — env/chrome JSON + CSS gate
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHROME="${ROOT}/env/chrome"
fail=0

die() { echo "chrome-tokens-smoke: FAIL $*" >&2; fail=1; }
ok() { echo "chrome-tokens-smoke: OK $*"; }

[[ -f "${CHROME}/chrome-tokens.json" ]] || die "missing chrome-tokens.json"
[[ -f "${CHROME}/chrome-tokens.css" ]] || die "missing chrome-tokens.css"
[[ -f "${CHROME}/README.md" ]] || die "missing README.md"
ok "files present"

python3 - "${CHROME}/chrome-tokens.json" "${CHROME}/chrome-tokens.css" <<'PY' || die "python validate"
import json, sys, re
jp, cp = sys.argv[1], sys.argv[2]
with open(jp, encoding="utf-8") as f:
    data = json.load(f)
assert data.get("schema") == "proteus-chrome-tokens/v1", "schema"
for key in ("spaceXs", "spaceSm", "spaceMd", "spaceLg", "spaceXl"):
    assert key in data["space"], key
for key in ("radiusSm", "radius", "radiusMd", "radiusLg", "radiusXl", "radiusPill"):
    assert key in data["radius"], key
surf = ("bg", "bgPanel", "bgElevated", "bgHover", "border", "separator", "text", "textDim", "textMute")
for mode in ("light", "dark"):
    m = data["modes"][mode]
    for k in surf:
        assert k in m and m[k], f"{mode}.{k}"
assert data.get("danger", "").startswith("#")
css = open(cp, encoding="utf-8").read()
required = [
    "--proteus-bg:",
    "--proteus-bg-panel:",
    "--proteus-text:",
    "--proteus-space-md:",
    "--proteus-radius:",
    "--proteus-danger:",
    'data-proteus-chrome="dark"',
]
for needle in required:
    assert needle in css, needle
# light values appear in :root block
assert "#f2f2f7" in css and "#1c1c1e" in css
print("validate ok")
PY
ok "json+css validate"
[[ $fail -eq 0 ]] || { echo "chrome-tokens-smoke: FAILED" >&2; exit 1; }
echo "chrome-tokens-smoke: OK"
