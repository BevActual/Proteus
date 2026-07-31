#!/usr/bin/env bash
# Install proteus-logind mutator + polkit policy on the guest (or host dogfood).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PKG="${ROOT}/services/proteus-logind"
BIN_SRC=""

# Prefer staged dogfood binary (bin/), then cargo target/release.
if [[ -x "${PKG}/bin/proteus-logind" ]]; then
  BIN_SRC="${PKG}/bin/proteus-logind"
elif [[ -x "${PKG}/target/release/proteus-logind" ]]; then
  BIN_SRC="${PKG}/target/release/proteus-logind"
elif command -v cargo >/dev/null 2>&1; then
  echo "Building proteus-logind (release)…"
  (cd "${PKG}" && cargo build --release)
  BIN_SRC="${PKG}/target/release/proteus-logind"
else
  echo "error: no binary at ${PKG}/bin/proteus-logind or target/release/proteus-logind" >&2
  echo "  build on the host: (cd services/proteus-logind && cargo build --release)" >&2
  echo "  or: mkdir -p bin && cp target/release/proteus-logind bin/" >&2
  exit 1
fi

install -d /usr/local/libexec
# Embedded fallback when 9p share is unavailable; live dogfood prefers bin/ on the share.
install -m 755 "${BIN_SRC}" /usr/local/libexec/proteus-logind.real
cat > /usr/local/libexec/proteus-logind << EOF
#!/usr/bin/env bash
# Prefer staged / rebuilt binary on the Proteus 9p share (VM dogfood).
for c in \\
  "${PKG}/bin/proteus-logind" \\
  "${PKG}/target/release/proteus-logind" \\
  /usr/local/libexec/proteus-logind.real
do
  if [[ -x "\$c" ]]; then
    exec "\$c" "\$@"
  fi
done
echo "proteus-logind: no binary found" >&2
exit 127
EOF
chmod 755 /usr/local/libexec/proteus-logind

install -d /usr/share/polkit-1/actions
install -m 644 "${PKG}/org.bevington.proteus.logind.policy" \
  /usr/share/polkit-1/actions/org.bevington.proteus.logind.policy

# Convenience on PATH (resolves to libexec)
install -d /usr/local/bin
cat > /usr/local/bin/proteus-logind << 'EOF'
#!/usr/bin/env bash
exec /usr/local/libexec/proteus-logind "$@"
EOF
chmod 755 /usr/local/bin/proteus-logind

echo "Installed proteus-logind → /usr/local/libexec/proteus-logind (wrapper; seed from ${BIN_SRC})"
echo "Polkit action → org.bevington.proteus.logind"
echo "Smoke: pkexec proteus-logind show"
