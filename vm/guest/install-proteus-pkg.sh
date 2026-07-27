#!/usr/bin/env bash
# Install proteus-pkg mutator + polkit policy on the guest (or host dogfood).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PKG="${ROOT}/services/proteus-pkg"
BIN_SRC=""

if [[ -x "${PKG}/target/release/proteus-pkg" ]]; then
  BIN_SRC="${PKG}/target/release/proteus-pkg"
elif command -v cargo >/dev/null 2>&1; then
  echo "Building proteus-pkg (release)…"
  (cd "${PKG}" && cargo build --release)
  BIN_SRC="${PKG}/target/release/proteus-pkg"
else
  echo "error: no release binary at ${PKG}/target/release/proteus-pkg" >&2
  echo "  build on the host: (cd services/proteus-pkg && cargo build --release)" >&2
  exit 1
fi

install -d /usr/local/libexec
install -m 755 "${BIN_SRC}" /usr/local/libexec/proteus-pkg

install -d /usr/share/polkit-1/actions
install -m 644 "${PKG}/org.bevington.proteus.pkg.policy" \
  /usr/share/polkit-1/actions/org.bevington.proteus.pkg.policy

# Convenience on PATH (resolves to libexec)
install -d /usr/local/bin
cat > /usr/local/bin/proteus-pkg << 'EOF'
#!/usr/bin/env bash
exec /usr/local/libexec/proteus-pkg "$@"
EOF
chmod 755 /usr/local/bin/proteus-pkg

echo "Installed proteus-pkg → /usr/local/libexec/proteus-pkg"
echo "Polkit action → org.bevington.proteus.pkg"
echo "Smoke: pkexec proteus-pkg sync"
