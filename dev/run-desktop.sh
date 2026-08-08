#!/usr/bin/env bash
# Retired Quickshell bare-desktop launcher. Owned path is nested compositor +
# iced chrome — see run-nested.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
echo "run-desktop.sh: Quickshell path retired; exec run-nested.sh" >&2
exec "${ROOT}/dev/run-nested.sh" "$@"
