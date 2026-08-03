#!/usr/bin/env bash
# Install proteus-audio-mix (resident mixer dump+peaks) on the guest or host dogfood.
set -euo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)"
PKG="${ROOT}/services/proteus-audio-mix"
BIN_SRC=""

if [[ -x "${PKG}/bin/proteus-audio-mix" ]]; then
  BIN_SRC="${PKG}/bin/proteus-audio-mix"
elif [[ -x "${PKG}/target/release/proteus-audio-mix" ]]; then
  BIN_SRC="${PKG}/target/release/proteus-audio-mix"
elif command -v cargo >/dev/null 2>&1; then
  echo "Building proteus-audio-mix (release)…"
  (cd "${PKG}" && cargo build --release)
  BIN_SRC="${PKG}/target/release/proteus-audio-mix"
else
  echo "error: no binary at ${PKG}/bin/proteus-audio-mix or target/release/proteus-audio-mix" >&2
  echo "  build on the host: (cd services/proteus-audio-mix && cargo build --release)" >&2
  echo "  or: mkdir -p bin && cp target/release/proteus-audio-mix bin/" >&2
  exit 1
fi

install -d /usr/local/libexec
install -m 755 "${BIN_SRC}" /usr/local/libexec/proteus-audio-mix.real
cat > /usr/local/libexec/proteus-audio-mix << EOF
#!/usr/bin/env bash
# Prefer staged / rebuilt binary on the Proteus 9p share (VM dogfood).
for c in \\
  "${PKG}/bin/proteus-audio-mix" \\
  "${PKG}/target/release/proteus-audio-mix" \\
  /usr/local/libexec/proteus-audio-mix.real
do
  if [[ -x "\$c" ]]; then
    exec "\$c" "\$@"
  fi
done
echo "proteus-audio-mix: no binary found" >&2
exit 127
EOF
chmod 755 /usr/local/libexec/proteus-audio-mix

install -d /usr/local/bin
cat > /usr/local/bin/proteus-audio-mix << 'EOF'
#!/usr/bin/env bash
exec /usr/local/libexec/proteus-audio-mix "$@"
EOF
chmod 755 /usr/local/bin/proteus-audio-mix

echo "Installed proteus-audio-mix → /usr/local/libexec/proteus-audio-mix (wrapper; seed from ${BIN_SRC})"
echo "Smoke: proteus-audio-mix dump | head -c 120; echo"
