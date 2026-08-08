#!/usr/bin/env bash
# Install proteus-shell + proteus-shellctl (owned iced session, OWNED-STACK rung 1).
# Wave 4: owned is the shipping default; Quickshell remains an installable fallback.
# Fail closed when bins cannot be installed (no silent skip).
set -euo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)"

# Prefer staged/rebuild on live tree (9p / checkout) over installed binary.
BIN_SHELL=""
BIN_CTL=""
BIN_LOCK=""
for t in target/release/proteus-shell shell/target/release/proteus-shell; do
  if [[ -x "${ROOT}/${t}" ]]; then
    BIN_SHELL="${ROOT}/${t}"
    break
  fi
done
for t in target/release/proteus-shellctl shell/target/release/proteus-shellctl; do
  if [[ -x "${ROOT}/${t}" ]]; then
    BIN_CTL="${ROOT}/${t}"
    break
  fi
done
for t in target/release/proteus-session-lock shell/target/release/proteus-session-lock; do
  if [[ -x "${ROOT}/${t}" ]]; then
    BIN_LOCK="${ROOT}/${t}"
    break
  fi
done

if [[ -z "${BIN_SHELL}" || -z "${BIN_CTL}" ]]; then
  if command -v cargo >/dev/null 2>&1; then
    echo "note: building proteus-shell (release)…"
    if ! (cd "${ROOT}" && cargo build -p proteus-shell --release); then
      echo "error: proteus-shell release build failed (Wave 4 owned default requires it)" >&2
      exit 1
    fi
    BIN_SHELL="${ROOT}/target/release/proteus-shell"
    BIN_CTL="${ROOT}/target/release/proteus-shellctl"
    BIN_LOCK="${ROOT}/target/release/proteus-session-lock"
  else
    echo "error: proteus-shell missing and no cargo — build on host first:" >&2
    echo "  (cd ${ROOT} && cargo build -p proteus-shell --release)" >&2
    exit 1
  fi
fi

if [[ ! -x "${BIN_SHELL}" || ! -x "${BIN_CTL}" ]]; then
  echo "error: proteus-shell bins not executable after resolve" >&2
  exit 1
fi

install -d /usr/local/libexec/proteus
install -m 755 "${BIN_SHELL}" /usr/local/libexec/proteus/proteus-shell
install -m 755 "${BIN_CTL}" /usr/local/libexec/proteus/proteus-shellctl
if [[ -n "${BIN_LOCK}" && -x "${BIN_LOCK}" ]]; then
  install -m 755 "${BIN_LOCK}" /usr/local/libexec/proteus/proteus-session-lock
fi

install -d /usr/local/bin
# Thin wrappers — honesty pattern (libexec holds the real binary).
cat >/usr/local/bin/proteus-shell <<'EOF'
#!/bin/sh
exec /usr/local/libexec/proteus/proteus-shell "$@"
EOF
cat >/usr/local/bin/proteus-shellctl <<'EOF'
#!/bin/sh
exec /usr/local/libexec/proteus/proteus-shellctl "$@"
EOF
if [[ -x /usr/local/libexec/proteus/proteus-session-lock ]]; then
  cat >/usr/local/bin/proteus-session-lock <<'EOF'
#!/bin/sh
exec /usr/local/libexec/proteus/proteus-session-lock "$@"
EOF
  chmod 755 /usr/local/bin/proteus-session-lock
fi
chmod 755 /usr/local/bin/proteus-shell /usr/local/bin/proteus-shellctl

# Session engine fact — owned only (Quickshell retired).
seed_engine_fact() {
  local dir="$1"
  local f cur
  install -d "${dir}"
  f="${dir}/shell-engine"
  if [[ -f "${f}" ]]; then
    cur="$(tr -d '[:space:]' <"${f}" 2>/dev/null || true)"
    if [[ "${cur}" == "quickshell" || "${cur}" == "qs" ]]; then
      echo "owned" >"${f}"
    fi
  else
    echo "owned" >"${f}"
  fi
}

FACT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/proteus"
if [[ "$(id -u)" -eq 0 ]]; then
  seed_engine_fact /etc/proteus
  # Also seed the session user when overlay runs as root.
  USER_NAME="${PROTEUS_USER:-${PROTEUS_SESSION_USER:-}}"
  if [[ -n "${USER_NAME}" ]]; then
    USER_HOME="$(getent passwd "${USER_NAME}" | cut -d: -f6 || true)"
    if [[ -n "${USER_HOME}" && -d "${USER_HOME}" ]]; then
      install -d -o "${USER_NAME}" -g "${USER_NAME}" "${USER_HOME}/.config/proteus"
      seed_engine_fact "${USER_HOME}/.config/proteus"
      chown "${USER_NAME}:${USER_NAME}" "${USER_HOME}/.config/proteus/shell-engine" 2>/dev/null || true
    fi
  fi
else
  seed_engine_fact "${FACT_DIR}"
fi

echo "Installed proteus-shell + proteus-shellctl (+ session-lock helper when built)"
