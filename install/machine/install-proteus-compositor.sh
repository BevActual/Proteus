#!/usr/bin/env bash
# Install proteus-compositor + proteus-compositorctl (OWNED-STACK rung 2).
# Shipping session is smithay-only; missing binary → session refuse.
# Soft-skip when cargo cannot build.
set -euo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)"

BIN_COMP=""
BIN_CTL=""
for t in target/release/proteus-compositor target/debug/proteus-compositor; do
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
    echo "note: building compositor (release)…"
    if (cd "${ROOT}" && cargo build -p compositor --release); then
      BIN_COMP="${ROOT}/target/release/proteus-compositor"
      BIN_CTL="${ROOT}/target/release/proteus-compositorctl"
    else
      echo "note: compositor release build failed — session will refuse without binary" >&2
      exit 0
    fi
  else
    echo "note: compositor missing and no cargo — session will refuse without binary" >&2
    exit 0
  fi
fi

[[ -x "${BIN_COMP}" && -x "${BIN_CTL}" ]] || {
  echo "note: compositor bins not executable — skip install" >&2
  exit 0
}

install -d /usr/local/libexec/proteus
install -m 755 "${BIN_COMP}" /usr/local/libexec/proteus/proteus-compositor
install -m 755 "${BIN_CTL}" /usr/local/libexec/proteus/proteus-compositorctl
# One-release alias for guests/scripts still calling the old name.
ln -sfn proteus-compositor /usr/local/libexec/proteus/proteus-compositor-next

install -d /usr/local/bin
cat >/usr/local/bin/proteus-compositor <<'EOF'
#!/bin/sh
exec /usr/local/libexec/proteus/proteus-compositor "$@"
EOF
cat >/usr/local/bin/proteus-compositorctl <<'EOF'
#!/bin/sh
exec /usr/local/libexec/proteus/proteus-compositorctl "$@"
EOF
ln -sfn proteus-compositor /usr/local/bin/proteus-compositor-next
chmod 755 /usr/local/bin/proteus-compositor /usr/local/bin/proteus-compositorctl

echo "Installed proteus-compositor → /usr/local/libexec/proteus/proteus-compositor"
echo "Installed proteus-compositorctl → /usr/local/libexec/proteus/proteus-compositorctl"
