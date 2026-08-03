#!/usr/bin/env bash
# Static analysis of every tracked shell script (smoke: shellcheck).
#
# The rest of the smoke suite asserts that strings exist in files. This one
# actually evaluates the code, which is the only kind of check that catches the
# class of bug the grep gates cannot: quoting errors, unset-variable paths,
# broken test syntax, misused exit codes.
#
# Gate = severity `error` only. Warnings/info are reported as a count but do not
# fail, so the gate is adoptable now and can be tightened as the backlog burns
# down (PROTEUS_SHELLCHECK_LEVEL=warning to raise the bar locally).
set -euo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)"
cd "${ROOT}"

if ! command -v shellcheck >/dev/null 2>&1; then
  echo "shellcheck-smoke: SKIP (shellcheck not installed — sudo pacman -S shellcheck)"
  exit 0
fi

LEVEL="${PROTEUS_SHELLCHECK_LEVEL:-error}"

# Tracked shell sources: *.sh plus extensionless scripts with a shell shebang.
mapfile -t FILES < <(
  {
    git ls-files '*.sh'
    git ls-files | while read -r f; do
      [[ -f "${f}" ]] || continue
      case "${f}" in *.*) continue ;; esac
      head -c 64 "${f}" 2>/dev/null | head -1 | grep -qE '^#!.*(bash|sh)\b' && echo "${f}"
    done
  } | sort -u
)

if [[ "${#FILES[@]}" -eq 0 ]]; then
  echo "shellcheck-smoke: FAIL no shell sources found" >&2
  exit 1
fi

echo "shellcheck-smoke: ${#FILES[@]} shell sources · gate severity=${LEVEL}"

# -x follows `source` into sibling helpers (install/helpers.sh, hardware/_lib.sh).
# SC1091 = "not following" for paths resolved at runtime; not a defect.
COMMON=(-x --exclude=SC1091)

if ! shellcheck "${COMMON[@]}" --severity="${LEVEL}" "${FILES[@]}"; then
  echo "shellcheck-smoke: FAIL — ${LEVEL}-level findings above" >&2
  exit 1
fi
echo "shellcheck-smoke: OK no ${LEVEL}-level findings"

# Informational backlog — never fails the gate.
WARN_N="$(shellcheck "${COMMON[@]}" --severity=warning --format=gcc "${FILES[@]}" 2>/dev/null | wc -l || true)"
INFO_N="$(shellcheck "${COMMON[@]}" --severity=info --format=gcc "${FILES[@]}" 2>/dev/null | wc -l || true)"
echo "shellcheck-smoke: backlog — ${WARN_N} warning · ${INFO_N} info (not gated)"
echo "shellcheck-smoke: OK"
