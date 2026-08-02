#!/usr/bin/env bash
# Install proteus-battery-threshold mutator + polkit policy on the guest (or host dogfood).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PKG="${ROOT}/services/proteus-battery-threshold"
BIN_SRC=""

if [[ -x "${PKG}/bin/proteus-battery-threshold" ]]; then
  BIN_SRC="${PKG}/bin/proteus-battery-threshold"
elif [[ -x "${PKG}/target/release/proteus-battery-threshold" ]]; then
  BIN_SRC="${PKG}/target/release/proteus-battery-threshold"
elif command -v cargo >/dev/null 2>&1; then
  echo "Building proteus-battery-threshold (release)…"
  (cd "${PKG}" && cargo build --release)
  BIN_SRC="${PKG}/target/release/proteus-battery-threshold"
else
  echo "error: no binary at ${PKG}/bin/ or target/release/" >&2
  echo "  build on the host: (cd services/proteus-battery-threshold && cargo build --release)" >&2
  exit 1
fi

install -d /usr/local/libexec
install -m 755 "${BIN_SRC}" /usr/local/libexec/proteus-battery-threshold.real
cat > /usr/local/libexec/proteus-battery-threshold << EOF
#!/usr/bin/env bash
# Prefer staged / rebuilt binary on the Proteus 9p share (VM dogfood).
for c in \\
  "${PKG}/bin/proteus-battery-threshold" \\
  "${PKG}/target/release/proteus-battery-threshold" \\
  /usr/local/libexec/proteus-battery-threshold.real
do
  if [[ -x "\$c" ]]; then
    exec "\$c" "\$@"
  fi
done
echo "proteus-battery-threshold: no binary found" >&2
exit 127
EOF
chmod 755 /usr/local/libexec/proteus-battery-threshold

install -d /usr/share/polkit-1/actions
install -m 644 "${PKG}/org.bevington.proteus.battery-threshold.policy" \
  /usr/share/polkit-1/actions/org.bevington.proteus.battery-threshold.policy

install -d /usr/local/bin
cat > /usr/local/bin/proteus-battery-threshold << 'EOF'
#!/usr/bin/env bash
exec /usr/local/libexec/proteus-battery-threshold "$@"
EOF
chmod 755 /usr/local/bin/proteus-battery-threshold

echo "Installed proteus-battery-threshold → /usr/local/libexec/proteus-battery-threshold"
echo "Polkit action → org.bevington.proteus.battery-threshold"
echo "Smoke: proteus-battery-threshold show"
