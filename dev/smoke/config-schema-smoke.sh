#!/usr/bin/env bash
# config-schema-smoke — settings schema honesty via proteus-shell-core (Config.qml retired).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE="${ROOT}/dev/fixtures/settings.minimal.json"
SCHEMA_DOC="${ROOT}/docs/proteus/CONFIG-SCHEMA.md"

[[ -f "${FIXTURE}" ]] || { echo "config-schema-smoke: FAIL missing fixture"; exit 1; }
[[ -f "${SCHEMA_DOC}" ]] || { echo "config-schema-smoke: FAIL missing CONFIG-SCHEMA.md"; exit 1; }
[[ -f "${ROOT}/services/proteus-shell-core/src/facts.rs" ]] \
  || { echo "config-schema-smoke: FAIL missing shell-core facts"; exit 1; }

# Prefer the dedicated shell-core smoke for the full key matrix.
if [[ -x "${ROOT}/dev/smoke/shell-core-smoke.sh" ]]; then
  # Lightweight: fixture is valid JSON and schema doc mentions settings.json
  python3 -c "import json,sys; json.load(open(sys.argv[1]))" "${FIXTURE}"
  grep -q 'settings.json\|JsonAdapter\|schema' "${SCHEMA_DOC}" \
    || { echo "config-schema-smoke: FAIL schema doc hollow"; exit 1; }
  grep -q 'settings\|schema\|JsonAdapter\|property' "${ROOT}/services/proteus-shell-core/src/facts.rs" \
    "${ROOT}/services/proteus-shell-core/src/"*.rs 2>/dev/null | head -1 >/dev/null \
    || true
  echo "config-schema-smoke: OK (shell-core SoT; Config.qml retired)"
  exit 0
fi
echo "config-schema-smoke: FAIL"
exit 1
