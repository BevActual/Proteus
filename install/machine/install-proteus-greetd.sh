#!/usr/bin/env bash
# Install proteus-greetd mutator + polkit policy on the guest (or host dogfood).
set -euo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)"
PKG="${ROOT}/services/proteus-greetd"
BIN_SRC=""

if [[ -x "${PKG}/bin/proteus-greetd" ]]; then
  BIN_SRC="${PKG}/bin/proteus-greetd"
elif [[ -x "${PKG}/target/release/proteus-greetd" ]]; then
  BIN_SRC="${PKG}/target/release/proteus-greetd"
elif command -v cargo >/dev/null 2>&1; then
  echo "Building proteus-greetd (release)…"
  (cd "${PKG}" && cargo build --release)
  BIN_SRC="${PKG}/target/release/proteus-greetd"
else
  echo "error: no binary at ${PKG}/bin/proteus-greetd or target/release/proteus-greetd" >&2
  exit 1
fi

install -d /usr/local/libexec
install -m 755 "${BIN_SRC}" /usr/local/libexec/proteus-greetd.real
cat > /usr/local/libexec/proteus-greetd << EOF
#!/usr/bin/env bash
# Prefer staged / rebuilt binary on the Proteus 9p share (VM dogfood).
for c in \\
  "${PKG}/bin/proteus-greetd" \\
  "${PKG}/target/release/proteus-greetd" \\
  /usr/local/libexec/proteus-greetd.real
do
  if [[ -x "\$c" ]]; then
    exec "\$c" "\$@"
  fi
done
echo "proteus-greetd: no binary found" >&2
exit 127
EOF
chmod 755 /usr/local/libexec/proteus-greetd

install -d /usr/share/polkit-1/actions
install -m 644 "${PKG}/org.bevington.proteus.greetd.policy" \
  /usr/share/polkit-1/actions/org.bevington.proteus.greetd.policy

install -d /usr/local/bin
cat > /usr/local/bin/proteus-greetd << 'EOF'
#!/usr/bin/env bash
exec /usr/local/libexec/proteus-greetd "$@"
EOF
chmod 755 /usr/local/bin/proteus-greetd

echo "Installed proteus-greetd → /usr/local/libexec/proteus-greetd (wrapper; seed from ${BIN_SRC})"
echo "Polkit action → org.bevington.proteus.greetd"
echo "Smoke: proteus-greetd show"
