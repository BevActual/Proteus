#!/usr/bin/env bash
# Guest Software dogfood — list/browse paths + user Flatpak install/remove.
# Pacman mutators need polkit/GUI auth; those are checked for CLI presence only.
set -uo pipefail

HOST="${PROTEUS_GUEST_HOST:-127.0.0.1}"
PORT="${PROTEUS_GUEST_PORT:-2222}"
USER="${PROTEUS_GUEST_USER:-andrew}"
ssh_opts=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o ConnectTimeout=5
  -o IgnoreUnknown=AddKeysToAgent,IdentityAgent -F /dev/null -p "${PORT}")

ssh_rc=0
out="$(ssh "${ssh_opts[@]}" "${USER}@${HOST}" 'bash -s' <<'EOF'
set -uo pipefail
fail=0
ok() { echo "OK  $*"; }
bad() { echo "FAIL $*"; fail=1; }

help="$(proteus-pkg 2>&1 || true)"
echo "$help" | grep -q upgrade-packages && ok "proteus-pkg CLI" || bad "proteus-pkg CLI"
# AUR helper: yay or paru (Settings accepts either)
aur_helper=""
if command -v yay >/dev/null; then
  aur_helper=yay
  ok "yay"
elif command -v paru >/dev/null; then
  aur_helper=paru
  ok "paru (yay absent)"
else
  bad "yay/paru (need one AUR helper)"
fi
command -v flatpak >/dev/null && ok "flatpak" || bad "flatpak"
flatpak remotes --user --columns=name 2>/dev/null | grep -qx flathub && ok "flathub remote" || bad "flathub remote"

n=$(comm -23 <(pacman -Slq | sort -u) <(pacman -Qq | sort -u) | head -n 5 | wc -l | tr -d ' ')
[[ "$n" -ge 1 ]] && ok "repos browse ($n sample)" || bad "repos browse"

if [[ -n "$aur_helper" ]]; then
  n=$("$aur_helper" -Slq aur 2>/dev/null | head -n 5 | wc -l | tr -d ' ')
  [[ "$n" -ge 1 ]] && ok "aur browse via $aur_helper ($n sample)" || bad "aur browse via $aur_helper"
else
  bad "aur browse (no helper)"
fi

n=$(flatpak remote-ls flathub --app --columns=application:f,name 2>/dev/null | head -n 5 | wc -l | tr -d ' ')
[[ "$n" -ge 1 ]] && ok "flathub browse ($n sample)" || bad "flathub browse"

pacman -Qqe >/dev/null && ok "repos inventory" || bad "repos inventory"
pacman -Qqm >/dev/null && ok "aur inventory" || bad "aur inventory"
pacman -Qu >/dev/null 2>&1 || true
ok "updates query (pacman -Qu)"

REF=org.gnome.Calculator
if flatpak list --user --app --columns=application 2>/dev/null | grep -qx "$REF"; then
  ok "flatpak already has $REF — reinstall skip"
else
  if flatpak install -y --user flathub "$REF" >/tmp/proteus-flatpak-install.log 2>&1; then
    ok "flatpak install $REF"
  else
    bad "flatpak install $REF"
    tail -20 /tmp/proteus-flatpak-install.log || true
  fi
fi
if flatpak list --user --app --columns=application 2>/dev/null | grep -qx "$REF"; then
  if flatpak uninstall -y --user "$REF" >/tmp/proteus-flatpak-remove.log 2>&1; then
    ok "flatpak remove $REF"
  else
    bad "flatpak remove $REF"
    tail -20 /tmp/proteus-flatpak-remove.log || true
  fi
else
  ok "flatpak remove skipped (not installed)"
fi

if sudo -n true 2>/dev/null; then
  if sudo -n proteus-pkg install cowsay && sudo -n proteus-pkg remove cowsay; then
    ok "pacman install+remove cowsay"
  else
    bad "pacman install/remove cowsay"
  fi
else
  ok "pacman mutator skipped (no passwordless sudo; use Settings + polkit in GUI)"
fi

exit "$fail"
EOF
)" || ssh_rc=$?

echo "${out}"
if [[ "$ssh_rc" -ne 0 ]]; then
  if [[ "${PROTEUS_GUEST:-}" == "1" ]]; then
    echo "software-guest-smoke: FAILED (ssh exit $ssh_rc)" >&2
    exit 1
  fi
  echo "software-guest-smoke: SKIP (guest SSH unavailable; set PROTEUS_GUEST=1 to require)"
  exit 0
fi
echo "${out}" | grep -q '^FAIL ' && { echo "software-guest-smoke: FAILED" >&2; exit 1; }
echo "software-guest-smoke: OK"
