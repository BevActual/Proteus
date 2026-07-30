#!/usr/bin/env bash
# Install proteus-pkg mutator + polkit policy on the guest (or host dogfood).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PKG="${ROOT}/services/proteus-pkg"
BIN_SRC=""

# Prefer staged dogfood binary (bin/), then cargo target/release.
if [[ -x "${PKG}/bin/proteus-pkg" ]]; then
  BIN_SRC="${PKG}/bin/proteus-pkg"
elif [[ -x "${PKG}/target/release/proteus-pkg" ]]; then
  BIN_SRC="${PKG}/target/release/proteus-pkg"
elif command -v cargo >/dev/null 2>&1; then
  echo "Building proteus-pkg (release)…"
  (cd "${PKG}" && cargo build --release)
  BIN_SRC="${PKG}/target/release/proteus-pkg"
else
  echo "error: no binary at ${PKG}/bin/proteus-pkg or target/release/proteus-pkg" >&2
  echo "  build on the host: (cd services/proteus-pkg && cargo build --release)" >&2
  echo "  or: mkdir -p bin && cp target/release/proteus-pkg bin/" >&2
  exit 1
fi

install -d /usr/local/libexec
# Embedded fallback when 9p share is unavailable; live dogfood prefers bin/ on the share.
install -m 755 "${BIN_SRC}" /usr/local/libexec/proteus-pkg.real
cat > /usr/local/libexec/proteus-pkg << EOF
#!/usr/bin/env bash
# Prefer staged / rebuilt binary on the Proteus 9p share (VM dogfood).
for c in \\
  "${PKG}/bin/proteus-pkg" \\
  "${PKG}/target/release/proteus-pkg" \\
  /usr/local/libexec/proteus-pkg.real
do
  if [[ -x "\$c" ]]; then
    exec "\$c" "\$@"
  fi
done
echo "proteus-pkg: no binary found" >&2
exit 127
EOF
chmod 755 /usr/local/libexec/proteus-pkg

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

echo "Installed proteus-pkg → /usr/local/libexec/proteus-pkg (wrapper; seed from ${BIN_SRC})"
echo "Polkit action → org.bevington.proteus.pkg"
echo "Smoke: pkexec proteus-pkg sync"
