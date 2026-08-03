#!/usr/bin/env bash
# install-smoke — host-side overlay tree / syntax gate (no guest required)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
exec "${ROOT}/install/check.sh"
