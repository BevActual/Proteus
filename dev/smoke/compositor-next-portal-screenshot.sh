#!/usr/bin/env bash
# compositor-next-portal-screenshot.sh — isolated dbus + xdp-wlr Screenshot.
#
# Usage: WAYLAND_DISPLAY=wayland-N ./dev/smoke/compositor-next-portal-screenshot.sh OUT.png
# Exit 0 on non-empty OUT.png; exit 2 if xdp-wlr / deps missing; exit 1 on hard failure.
set -euo pipefail

OUT="${1:?output png path}"
: >"${OUT}"

XDP_WLR=""
for cand in /usr/lib/xdg-desktop-portal-wlr /usr/libexec/xdg-desktop-portal-wlr; do
  if [[ -x "${cand}" ]]; then
    XDP_WLR="${cand}"
    break
  fi
done
if [[ -z "${XDP_WLR}" ]]; then
  echo "compositor-next-portal-screenshot: xdg-desktop-portal-wlr missing" >&2
  exit 2
fi
if [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
  echo "compositor-next-portal-screenshot: WAYLAND_DISPLAY unset" >&2
  exit 1
fi
if [[ ! -x /usr/lib/xdg-desktop-portal ]]; then
  echo "compositor-next-portal-screenshot: xdg-desktop-portal missing" >&2
  exit 2
fi
command -v dbus-run-session >/dev/null 2>&1 || {
  echo "compositor-next-portal-screenshot: dbus-run-session missing" >&2
  exit 2
}
command -v gdbus >/dev/null 2>&1 || {
  echo "compositor-next-portal-screenshot: gdbus missing" >&2
  exit 2
}

CFG="$(mktemp -d)"
WLR_LOG="${CFG}/wlr.log"
XDP_LOG="${CFG}/xdp.log"
mkdir -p "${CFG}/xdg-desktop-portal"
cat >"${CFG}/xdg-desktop-portal/portals.conf" <<'EOF'
[preferred]
default=wlr
EOF

# Isolated bus so we do not fight host Hyprland portal units.
# shellcheck disable=SC2016
dbus-run-session -- env \
  WAYLAND_DISPLAY="${WAYLAND_DISPLAY}" \
  XDG_CURRENT_DESKTOP=wlroots \
  XDG_CONFIG_HOME="${CFG}" \
  XDP_WLR="${XDP_WLR}" \
  OUT="${OUT}" \
  WLR_LOG="${WLR_LOG}" \
  XDP_LOG="${XDP_LOG}" \
  CFG="${CFG}" \
  bash -c '
set -euo pipefail
cleanup() {
  if [[ -f "${CFG}/wlr.pid" ]]; then kill "$(cat "${CFG}/wlr.pid")" 2>/dev/null || true; fi
  if [[ -f "${CFG}/xdp.pid" ]]; then kill "$(cat "${CFG}/xdp.pid")" 2>/dev/null || true; fi
}
trap cleanup EXIT

"${XDP_WLR}" >"${WLR_LOG}" 2>&1 &
echo $! >"${CFG}/wlr.pid"
/usr/lib/xdg-desktop-portal -r >"${XDP_LOG}" 2>&1 &
echo $! >"${CFG}/xdp.pid"
sleep 1.5

req="$(gdbus call --session \
  --dest org.freedesktop.portal.Desktop \
  --object-path /org/freedesktop/portal/desktop \
  --method org.freedesktop.portal.Screenshot.Screenshot \
  "" "{'\''interactive'\'': <false>, '\''handle_token'\'': <'\''proteusSmoke'\''>}" \
  | sed -n "s/.*(objectpath '\''\\([^'\'']*\\)'\'').*/\\1/p" || true)"

if [[ -z "${req}" ]]; then
  echo "compositor-next-portal-screenshot: Screenshot request failed" >&2
  cat "${WLR_LOG}" >&2 || true
  cat "${XDP_LOG}" >&2 || true
  exit 1
fi

for _ in $(seq 1 50); do
  line="$(timeout 0.5 gdbus monitor --session \
    --dest org.freedesktop.portal.Desktop \
    --object-path "${req}" 2>/dev/null || true)"
  if echo "${line}" | grep -q "file://"; then
    uri="$(echo "${line}" | grep -oE "file://[^'\''\\\"[:space:]]+" | head -1 | sed "s|^file://||")"
    uri="${uri//%20/ }"
    if [[ -n "${uri}" && -s "${uri}" ]]; then
      cp -f "${uri}" "${OUT}"
      exit 0
    fi
  fi
  sleep 0.1
done

echo "compositor-next-portal-screenshot: no Response uri" >&2
cat "${WLR_LOG}" >&2 || true
cat "${XDP_LOG}" >&2 || true
exit 1
'

rm -rf "${CFG}"
[[ -s "${OUT}" ]]
