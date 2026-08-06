#!/usr/bin/env bash
# Install proteus-compositor-next + proteus-compositorctl (OWNED-STACK rung 2).
# Shipping session default is smithay; missing binary fail-closes to Hyprland.
# Soft-skip when cargo cannot build (Hyprland fallback remains honest).
set -euo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)"

BIN_COMP=""
BIN_CTL=""
for t in target/release/proteus-compositor-next target/debug/proteus-compositor-next; do
  if [[ -x "${ROOT}/${t}" ]]; then
    BIN_COMP="${ROOT}/${t}"
    break
  fi
done
for t in target/release/proteus-compositorctl target/debug/proteus-compositorctl; do
  if [[ -x "${ROOT}/${t}" ]]; then
    BIN_CTL="${ROOT}/${t}"
    break
  fi
done

if [[ -z "${BIN_COMP}" || -z "${BIN_CTL}" ]]; then
  if command -v cargo >/dev/null 2>&1; then
    echo "note: building compositor-next (release)…"
    if (cd "${ROOT}" && cargo build -p compositor-next --release); then
      BIN_COMP="${ROOT}/target/release/proteus-compositor-next"
      BIN_CTL="${ROOT}/target/release/proteus-compositorctl"
    else
      echo "note: compositor-next release build failed — session will fail-closed to Hyprland" >&2
      exit 0
    fi
  else
    echo "note: compositor-next missing and no cargo — session will fail-closed to Hyprland" >&2
    exit 0
  fi
fi

[[ -x "${BIN_COMP}" && -x "${BIN_CTL}" ]] || {
  echo "note: compositor-next bins not executable — skip install" >&2
  exit 0
}

install -d /usr/local/libexec/proteus
install -m 755 "${BIN_COMP}" /usr/local/libexec/proteus/proteus-compositor-next
install -m 755 "${BIN_CTL}" /usr/local/libexec/proteus/proteus-compositorctl

install -d /usr/local/bin
cat >/usr/local/bin/proteus-compositor-next <<'EOF'
#!/bin/sh
exec /usr/local/libexec/proteus/proteus-compositor-next "$@"
EOF
cat >/usr/local/bin/proteus-compositorctl <<'EOF'
#!/bin/sh
exec /usr/local/libexec/proteus/proteus-compositorctl "$@"
EOF
chmod 755 /usr/local/bin/proteus-compositor-next /usr/local/bin/proteus-compositorctl

echo "Installed proteus-compositor-next → /usr/local/libexec/proteus/proteus-compositor-next"
echo "Installed proteus-compositorctl → /usr/local/libexec/proteus/proteus-compositorctl"
