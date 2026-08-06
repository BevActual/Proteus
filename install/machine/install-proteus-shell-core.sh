#!/usr/bin/env bash
# Install proteus-shell-core + proteus-open (OWNED-STACK rung 0) on the guest
# (or host dogfood). Same libexec honesty pattern as install-proteus-pkg.sh:
# embedded .real fallback, wrapper prefers staged/rebuilt binaries on the
# Proteus 9p share so live dogfood picks up fresh builds without reinstalling.
set -euo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)"
CORE="${ROOT}/services/proteus-shell-core"

resolve_bin() {
  local name="$1"
  if [[ -x "${CORE}/bin/${name}" ]]; then
    echo "${CORE}/bin/${name}"
  elif [[ -x "${CORE}/target/release/${name}" ]]; then
    echo "${CORE}/target/release/${name}"
  else
    echo ""
  fi
}

CORE_SRC="$(resolve_bin proteus-shell-core)"
OPEN_SRC="$(resolve_bin proteus-open)"
if [[ -z "${CORE_SRC}" || -z "${OPEN_SRC}" ]]; then
  if command -v cargo >/dev/null 2>&1; then
    echo "Building proteus-shell-core (release)…"
    (cd "${CORE}" && cargo build --release)
    CORE_SRC="${CORE}/target/release/proteus-shell-core"
    OPEN_SRC="${CORE}/target/release/proteus-open"
  else
    echo "error: no binaries at ${CORE}/bin/ or target/release/ and no cargo" >&2
    echo "  build on the host: (cd services/proteus-shell-core && cargo build --release)" >&2
    echo "  or: mkdir -p bin && cp target/release/{proteus-shell-core,proteus-open} bin/" >&2
    exit 1
  fi
fi

install -d /usr/local/libexec /usr/local/bin
for name in proteus-shell-core proteus-open; do
  src="${CORE}/target/release/${name}"
  [[ "${name}" == "proteus-shell-core" ]] && src="${CORE_SRC}"
  [[ "${name}" == "proteus-open" ]] && src="${OPEN_SRC}"
  # Embedded fallback when the 9p share is unavailable.
  install -m 755 "${src}" "/usr/local/libexec/${name}.real"
  cat > "/usr/local/libexec/${name}" << EOF
#!/usr/bin/env bash
# Prefer staged / rebuilt binary on the Proteus 9p share (VM dogfood).
for c in \\
  "${CORE}/bin/${name}" \\
  "${CORE}/target/release/${name}" \\
  /usr/local/libexec/${name}.real
do
  if [[ -x "\$c" ]]; then
    exec "\$c" "\$@"
  fi
done
echo "${name}: no binary found" >&2
exit 127
EOF
  chmod 755 "/usr/local/libexec/${name}"
  cat > "/usr/local/bin/${name}" << EOF
#!/usr/bin/env bash
exec /usr/local/libexec/${name} "\$@"
EOF
  chmod 755 "/usr/local/bin/${name}"
done

echo "Installed proteus-shell-core + proteus-open → /usr/local/libexec (wrappers)"
echo "Smoke: proteus-shell-core facts · proteus-open settings"
