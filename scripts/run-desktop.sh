#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v quickshell >/dev/null 2>&1; then
  echo "quickshell not found. Install it first: https://quickshell.org/" >&2
  exit 1
fi

export PROTEUS_SURFACE="${PROTEUS_SURFACE:-desktop}"
exec quickshell -p "${ROOT}/shell"
