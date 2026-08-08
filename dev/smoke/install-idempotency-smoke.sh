#!/usr/bin/env bash
# install-idempotency-smoke — running a stage twice must change nothing.
#
# `bootstrap.sh repair` is the documented fix for almost every install problem,
# and post-install runs re-execute stages by design. config.sh writes Facts under
# ~/.config/proteus/; if any writer is not idempotent, a second run silently
# drifts fingerprints.
#
# Executable, not a grep assertion: it actually runs the stage twice against a
# throwaway HOME and diffs the result.
#
# SAFETY: everything is redirected into a mktemp sandbox via a stubbed `getent`
# (config.sh resolves the target home from getent, not $HOME). The run refuses
# to start unless the resolved home is inside that sandbox, so a broken stub
# fails closed rather than writing into the real ~/.config.
set -euo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)"

SANDBOX="$(mktemp -d)"
cleanup() { rm -rf "${SANDBOX}"; }
trap cleanup EXIT

FAKE_USER="proteus-idem-test"
FAKE_HOME="${SANDBOX}/home/${FAKE_USER}"
BIN="${SANDBOX}/bin"
mkdir -p "${FAKE_HOME}" "${BIN}"

# getent stub — this is what redirects every write into the sandbox.
cat > "${BIN}/getent" <<EOF
#!/usr/bin/env bash
[[ "\${1:-}" == passwd ]] || exit 2
printf '%s:x:1000:1000::%s:/bin/bash\n' "${FAKE_USER}" "${FAKE_HOME}"
EOF

# Neutralise anything privileged or live. config.sh only uses proteus_root for
# systemctl/loginctl; every file write goes through proteus_as_user, which runs
# in-process when not root.
for stub in sudo systemctl loginctl; do
  printf '#!/usr/bin/env bash\nexit 0\n' > "${BIN}/${stub}"
done
chmod +x "${BIN}"/*

export PATH="${BIN}:${PATH}"
export PROTEUS_USER="${FAKE_USER}"
export HOME="${FAKE_HOME}"
export PROTEUS_ROOT="${ROOT}"
export PROTEUS_INSTALL_LOG="${SANDBOX}/install.log"
export PROTEUS_INSTALL_STATUS_DIR="${SANDBOX}/status"

# Fail closed: if the stub is not in effect, do not touch anything.
resolved_home="$(getent passwd "${FAKE_USER}" | cut -d: -f6)"
if [[ "${resolved_home}" != "${SANDBOX}"/* ]]; then
  echo "install-idempotency-smoke: FAIL sandbox not in effect (home resolved to ${resolved_home})" >&2
  exit 1
fi

fingerprint() {
  # Content + layout of everything the stage produced.
  find "${FAKE_HOME}" \( -type f -o -type l \) -printf '%P\n' 2>/dev/null | sort | while read -r rel; do
    local_path="${FAKE_HOME}/${rel}"
    if [[ -L "${local_path}" ]]; then
      printf '%s -> %s\n' "${rel}" "$(readlink "${local_path}")"
    else
      printf '%s %s\n' "${rel}" "$(md5sum <"${local_path}" | cut -d' ' -f1)"
    fi
  done
}

run_stage() {
  local stage="$1"
  bash "${ROOT}/install/${stage}.sh" >"${SANDBOX}/${stage}.out" 2>&1 || {
    echo "install-idempotency-smoke: FAIL ${stage} stage errored on run" >&2
    tail -15 "${SANDBOX}/${stage}.out" >&2
    exit 1
  }
}

STAGE="${PROTEUS_IDEM_STAGE:-config}"
echo "install-idempotency-smoke: running '${STAGE}' twice in ${SANDBOX}"

run_stage "${STAGE}"
first="$(fingerprint)"
run_stage "${STAGE}"
second="$(fingerprint)"

if [[ "${first}" != "${second}" ]]; then
  echo "install-idempotency-smoke: FAIL second '${STAGE}' run changed the system" >&2
  diff <(printf '%s\n' "${first}") <(printf '%s\n' "${second}") | head -25 >&2
  exit 1
fi

# Highest-consequence Facts — shipping session path (Hyprland conf retired).
FACT_DIR="${FAKE_HOME}/.config/proteus"
for fact in compositor-engine shell-engine; do
  if [[ -f "${FACT_DIR}/${fact}" ]]; then
    val="$(tr -d '[:space:]' <"${FACT_DIR}/${fact}" || true)"
    case "${fact}:${val}" in
      compositor-engine:smithay|compositor-engine:compositor|compositor-engine:compositor-next) ;;
      shell-engine:owned|shell-engine:iced|shell-engine:proteus-shell) ;;
      *)
        echo "install-idempotency-smoke: FAIL unexpected ${fact}=${val:-empty}" >&2
        exit 1
        ;;
    esac
    echo "install-idempotency-smoke: OK Fact ${fact}=${val}"
  fi
done
# Must not reintroduce Hyprland seeds
if [[ -d "${FAKE_HOME}/.config/hypr" ]] && find "${FAKE_HOME}/.config/hypr" -type f 2>/dev/null | grep -q .; then
  echo "install-idempotency-smoke: FAIL config stage still writes ~/.config/hypr" >&2
  exit 1
fi

echo "install-idempotency-smoke: OK '${STAGE}' is idempotent ($(printf '%s\n' "${first}" | wc -l) files stable)"

# Honesty: this covers config only, and says so rather than letting a green line
# imply the whole overlay is proven re-runnable. preflight / snapshots / apps /
# desktop are dominated by pacman and privileged calls, which the sandbox stubs
# to no-ops — running them here would assert nothing. Their idempotency is only
# provable on a real guest (dev/vm) or machine.
if [[ "${STAGE}" == "config" ]]; then
  echo "install-idempotency-smoke: NOTE covers the 'config' stage only —"
  echo "install-idempotency-smoke:      preflight/snapshots/apps/desktop are pacman- and"
  echo "install-idempotency-smoke:      root-dominated; prove those on a guest, not here."
fi
