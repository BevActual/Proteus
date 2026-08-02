#!/usr/bin/env bash
# network-vpn-smoke — VPN leaf WireGuard + OpenVPN import wiring (host static)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fail=0
ok() { echo "network-vpn-smoke: OK $*"; }
die() { echo "network-vpn-smoke: FAIL $*" >&2; fail=1; }

LEAF="${ROOT}/apps/proteus-settings/panes/NetworkVpnLeaf.qml"
PANE="${ROOT}/apps/proteus-settings/panes/NetworkPane.qml"
CFG="${ROOT}/shell/shared/Config.qml"
PKGS="${ROOT}/vm/install/proteus-base.packages"

for f in "${LEAF}" "${PANE}" "${CFG}" "${PKGS}"; do
  [[ -f "${f}" ]] || die "missing ${f#${ROOT}/}"
done
ok "files present"

grep -q 'importWireGuard\|Import WireGuard' "${LEAF}" || die "leaf missing WireGuard import"
grep -q 'importOpenVpn\|Import OpenVPN' "${LEAF}" || die "leaf missing OpenVPN import"
grep -q 'ovpnDialog' "${LEAF}" || die "leaf missing OpenVPN FileDialog"
grep -q 'ovpnUserDraft\|ovpnPassDraft' "${LEAF}" || die "leaf missing OpenVPN auth drafts"
grep -qiE 'never in settings.json|session-only|session only' "${LEAF}" \
  || die "leaf must say OpenVPN creds stay out of settings.json"
grep -qiE 'Cert wizard Out|Headscale admin →' "${LEAF}" \
  || die "leaf must keep cert wizard Out + Headscale admin pointer"
ok "NetworkVpnLeaf"

grep -q 'function importOpenVpn' "${PANE}" || die "NetworkPane missing importOpenVpn"
grep -q '"openvpn"' "${PANE}" || die "NetworkPane must nmcli import type openvpn"
grep -q 'vpn.user-name\|vpn.secrets' "${PANE}" \
  || die "NetworkPane must optional OpenVPN credentials modify"
grep -q 'function importWireGuard' "${PANE}" || die "NetworkPane missing importWireGuard"
ok "NetworkPane"

grep -q 'vpnImportOpenVpn' "${CFG}" || die "Config missing vpnImportOpenVpn helper"
grep -q 'networkmanager-openvpn' "${PKGS}" \
  || die "proteus-base.packages must include networkmanager-openvpn"
ok "Config + packages"

[[ $fail -eq 0 ]] || { echo "network-vpn-smoke: FAILED" >&2; exit 1; }
echo "network-vpn-smoke: OK"
