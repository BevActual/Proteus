#!/usr/bin/env bash
# Install proteus-accounts on the guest (or host dogfood). User-scoped seats; no polkit.
set -euo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)"
PKG="${ROOT}/services/proteus-accounts"
BIN_SRC=""

if [[ -x "${PKG}/bin/proteus-accounts" ]]; then
  BIN_SRC="${PKG}/bin/proteus-accounts"
elif [[ -x "${PKG}/target/release/proteus-accounts" ]]; then
  BIN_SRC="${PKG}/target/release/proteus-accounts"
elif command -v cargo >/dev/null 2>&1; then
  echo "Building proteus-accounts (release)…"
  (cd "${PKG}" && cargo build --release)
  BIN_SRC="${PKG}/target/release/proteus-accounts"
else
  echo "error: no binary at ${PKG}/bin/proteus-accounts or target/release/proteus-accounts" >&2
  exit 1
fi

install -d /usr/local/libexec
install -m 755 "${BIN_SRC}" /usr/local/libexec/proteus-accounts.real
cat > /usr/local/libexec/proteus-accounts << EOF
#!/usr/bin/env bash
for c in \\
  "${PKG}/bin/proteus-accounts" \\
  "${PKG}/target/release/proteus-accounts" \\
  /usr/local/libexec/proteus-accounts.real
do
  if [[ -x "\$c" ]]; then
    exec "\$c" "\$@"
  fi
done
echo "proteus-accounts: no binary found" >&2
exit 127
EOF
chmod 755 /usr/local/libexec/proteus-accounts

install -d /usr/local/bin
cat > /usr/local/bin/proteus-accounts << 'EOF'
#!/usr/bin/env bash
exec /usr/local/libexec/proteus-accounts "$@"
EOF
chmod 755 /usr/local/bin/proteus-accounts

echo "Installed proteus-accounts → /usr/local/libexec/proteus-accounts (wrapper; seed from ${BIN_SRC})"
echo "Google client id: PROTEUS_GOOGLE_OAUTH_CLIENT_ID or ~/.config/proteus/oauth-google-client-id"
echo "Smoke: proteus-accounts smoke"
