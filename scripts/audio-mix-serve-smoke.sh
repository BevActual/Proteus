#!/usr/bin/env bash
# audio-mix-serve-smoke — host checks for proteus-audio-mix + Audio.qml wiring
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0
ok() { echo "audio-mix-serve-smoke: OK $*"; }
die() { echo "audio-mix-serve-smoke: FAIL $*" >&2; fail=1; }

PKG="${ROOT}/services/proteus-audio-mix"
[[ -f "${PKG}/Cargo.toml" ]] || die "missing Cargo.toml"
[[ -f "${PKG}/src/main.rs" ]] || die "missing src/main.rs"
[[ -f "${PKG}/README.md" ]] || die "missing README"
[[ -x "${ROOT}/vm/guest/install-proteus-audio-mix.sh" ]] || die "install-proteus-audio-mix.sh"
grep -q 'install-proteus-audio-mix' "${ROOT}/vm/guest/install-settings-app.sh" \
  || die "settings-app install hook"

grep -q 'startMixServe' "${ROOT}/shell/shared/Audio.qml" || die "Audio.qml startMixServe"
grep -q 'stopMixServe' "${ROOT}/shell/shared/Audio.qml" || die "Audio.qml stopMixServe"
grep -q 'mixServeProc' "${ROOT}/shell/shared/Audio.qml" || die "Audio.qml mixServeProc"
grep -q 'proteus-audio-mix' "${ROOT}/shell/shared/Audio.qml" || die "Audio.qml resolves helper"
grep -q '_mixCtlWrite' "${ROOT}/shell/shared/Audio.qml" || die "Audio.qml ctl write"
grep -q 'syncMixServe' "${ROOT}/apps/proteus-settings/panes/SoundPane.qml" \
  || die "SoundPane syncMixServe"
grep -q 'mixFallbackTimer' "${ROOT}/apps/proteus-settings/panes/SoundPane.qml" \
  || die "SoundPane Python fallback timer"
# Mutations still Python
grep -q 'audio-mix.py' "${ROOT}/shell/shared/Audio.qml" || die "Audio.qml mutations via audio-mix.py"

BIN=""
if [[ -x "${PKG}/bin/proteus-audio-mix" ]]; then
  BIN="${PKG}/bin/proteus-audio-mix"
elif [[ -x "${PKG}/target/release/proteus-audio-mix" ]]; then
  BIN="${PKG}/target/release/proteus-audio-mix"
fi

if [[ -n "${BIN}" ]]; then
  "${BIN}" version >/dev/null || die "version"
  dump="$("${BIN}" dump 2>/dev/null || true)"
  echo "$dump" | grep -q '"ok"' || die "dump missing ok"
  echo "$dump" | grep -q '"channels"' || die "dump missing channels"
  echo "$dump" | grep -q '"mixes"' || die "dump missing mixes"
  ok "dump shape"

  ctl="/tmp/proteus-audio-mix-smoke-$$.ctl"
  out="/tmp/proteus-audio-mix-smoke-$$.out"
  rm -f "${ctl}" "${out}"
  # Serve should emit a typed dump line quickly (file redirect avoids pipe races).
  timeout 5s "${BIN}" serve --dump-ms 400 --ctl "${ctl}" >"${out}" 2>/dev/null || true
  rm -f "${ctl}"
  if ! grep -q '"t":"dump"' "${out}" 2>/dev/null; then
    rm -f "${out}"
    die "serve did not emit t=dump"
  else
    rm -f "${out}"
    ok "serve emits dump"
  fi
  ok "CLI ${BIN}"
else
  echo "audio-mix-serve-smoke: note — no release binary (build with cargo build --release)"
fi

ok "sources + wiring"
[[ "${fail}" -eq 0 ]] || { echo "audio-mix-serve-smoke: FAILED" >&2; exit 1; }
echo "audio-mix-serve-smoke: OK"
