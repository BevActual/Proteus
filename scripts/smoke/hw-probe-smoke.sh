#!/usr/bin/env bash
# Smoke: wave A probe emits valid JSON with required keys.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROBE="${ROOT}/services/proteus-hw-probe/proteus-hw-probe"

out="$("${PROBE}" --compact)"
python3 -c "
import json, sys
d = json.loads(sys.argv[1])
assert d.get('schema') == 'proteus.hw.probe/v0', d
assert d.get('wave') == 'A', d
assert 'device_class' in d and d['device_class'], d
assert 'capabilities' in d and isinstance(d['capabilities'], dict), d
assert 'modules' in d and isinstance(d['modules'], dict), d
print('proteus-hw-probe smoke OK')
print('  class:', d['device_class'])
print('  caps:', ', '.join(sorted(d['capabilities'])) or '(none)')
" "${out}"
