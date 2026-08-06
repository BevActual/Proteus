#!/usr/bin/env bash
# settings-backing-smoke — HARD RULE 2, enforced.
#
# ARCHITECTURE.md rule 2: "Every Settings control has a file or CLI you can
# inspect." That was aspirational for as long as nothing declared the mapping —
# a pane could quietly grow a control backed by nothing inspectable and no gate
# would notice.
#
# Each settings hub now declares `backsFacts` (on-disk Facts it reads/writes) and
# `backsCli` (commands it drives). This resolves every one of them:
#
#   - every backsCli name exists as a repo helper, a built service, or is a
#     declared external system tool
#   - every backsFacts path is a Fact documented in CURRENT.md §5
#   - every hub in the catalog declares both keys (no silent omission)
#
# Executable: it resolves names against the filesystem and the docs, so a
# renamed helper or an undocumented config path fails here rather than at
# runtime in front of a user.
set -euo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)"
cd "${ROOT}"
fail=0
die() { echo "settings-backing-smoke: FAIL $*" >&2; fail=1; }
ok()  { echo "settings-backing-smoke: OK $*"; }

CATALOG="env/settings/catalog.json"
[[ -f "${CATALOG}" ]] || { echo "settings-backing-smoke: FAIL missing ${CATALOG}" >&2; exit 1; }

# External tools Proteus wraps but does not ship. Declared explicitly so that a
# typo ("nmcl") fails instead of being waved through as "probably external".
EXTERNAL="nmcli bluetoothctl tailscale pactl wpctl hyprctl powerprofilesctl
          timedatectl localectl pacman flatpak"

python3 - "${CATALOG}" <<'PY' > /tmp/proteus-backing.$$ || { echo "settings-backing-smoke: FAIL could not parse catalog" >&2; exit 1; }
import json, sys
for e in json.load(open(sys.argv[1]))["hubs"]:
    hub = e["id"]
    f, c = e.get("backsFacts"), e.get("backsCli")
    if f is None or c is None:
        print(f"MISSING\t{hub}")
        continue
    for x in f:
        print(f"FACT\t{hub}\t{x}")
    for x in c:
        print(f"CLI\t{hub}\t{x}")
    print(f"HUB\t{hub}")
PY
MAP=/tmp/proteus-backing.$$
trap 'rm -f "${MAP}"' EXIT

hubs=$(grep -c '^HUB' "${MAP}" || true)
[[ "${hubs}" -ge 15 ]] || die "only ${hubs} hubs parsed from the catalog (expected >= 15)"

while IFS=$'\t' read -r kind hub _; do
  [[ "${kind}" == "MISSING" ]] && die "hub '${hub}' declares no backsFacts/backsCli (HARD RULE 2)"
done < <(grep '^MISSING' "${MAP}" || true)

# --- CLIs resolve -------------------------------------------------------------
cli_bad=0
while IFS=$'\t' read -r _ hub name; do
  if [[ -e "shell/scripts/${name}" ]]; then continue; fi
  if [[ -d "services/${name}" ]]; then continue; fi
  if [[ -e "install/machine/${name}" ]]; then continue; fi
  if grep -qw -- "${name}" <<<"${EXTERNAL}"; then continue; fi
  die "hub '${hub}' declares CLI '${name}' — not a repo helper, service, or declared external tool"
  cli_bad=1
done < <(grep '^CLI' "${MAP}" || true)
[[ "${cli_bad}" -eq 0 ]] && ok "every declared CLI resolves ($(grep -c '^CLI' "${MAP}" || echo 0) declarations)"

# --- Facts are documented -----------------------------------------------------
FACTS_DOC="docs/proteus/CURRENT.md"
fact_bad=0
while IFS=$'\t' read -r _ hub path; do
  if grep -qF "${path}" "${FACTS_DOC}"; then continue; fi
  die "hub '${hub}' declares Fact '${path}' — not documented in ${FACTS_DOC} §5"
  fact_bad=1
done < <(grep '^FACT' "${MAP}" || true)
[[ "${fact_bad}" -eq 0 ]] && ok "every declared Fact is documented ($(grep -c '^FACT' "${MAP}" || echo 0) declarations)"

# --- A hub with neither is a rule-2 violation ---------------------------------
empty=0
while IFS=$'\t' read -r _ hub; do
  f=$(grep -cP "^FACT\t${hub}\t" "${MAP}" || true)
  c=$(grep -cP "^CLI\t${hub}\t" "${MAP}" || true)
  if [[ "${f}" -eq 0 && "${c}" -eq 0 ]]; then
    die "hub '${hub}' backs onto nothing inspectable (HARD RULE 2)"
    empty=1
  fi
done < <(grep '^HUB' "${MAP}" || true)
[[ "${empty}" -eq 0 ]] && ok "every hub backs onto at least one Fact or CLI"

# --- the derived per-posture command surface ----------------------------------
# The point of declaring backsCli is that a posture's inspectable command set
# becomes derivable instead of folklore. Assert the deriver works, produces a
# non-empty surface for each posture, and actually differs between them — a
# surface identical across postures would mean the postures gate nothing.
SURFACE="shell/scripts/proteus-cli-surface"
if [[ ! -x "${SURFACE}" ]]; then
  die "missing ${SURFACE} (derives the per-posture CLI surface)"
else
  declare -A counts=()
  for p in desktop console host; do
    n="$(python3 "${SURFACE}" "${p}" --json 2>/dev/null \
         | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["cli"]))' 2>/dev/null || echo 0)"
    counts[$p]="${n}"
    [[ "${n}" -gt 0 ]] || die "CLI surface for posture '${p}' is empty"
  done
  if [[ "${counts[desktop]}" == "${counts[console]}" && "${counts[console]}" == "${counts[host]}" ]]; then
    die "CLI surface identical across postures (${counts[desktop]}) — posture gating is not applying"
  fi
  ok "CLI surface derives per posture (desktop:${counts[desktop]} console:${counts[console]} host:${counts[host]})"
  grep -q 'proteus-cli-surface' install/apps.sh \
    && ok "apps stage installs proteus-cli-surface" \
    || die "proteus-cli-surface not installed to PATH (host is headless — it IS the interface)"
fi

[[ "${fail}" -eq 0 ]] || exit 1
echo "settings-backing-smoke: OK (${hubs} hubs, HARD RULE 2 enforced)"
