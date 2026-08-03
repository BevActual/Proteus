#!/usr/bin/env bash
# host — host posture kit: samba usershares (no-root share CRUD from the
# Workloads app), smartmontools for the dashboard health cards, and a
# read-only smartctl sudoers drop so SMART works without a root shell.
# Skip with: PROTEUS_INSTALL_SKIP=host
set -euo pipefail
# shellcheck source=helpers.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

PROTEUS_ROOT="$(proteus_install_root)"
LIST="${PROTEUS_ROOT}/vm/install/proteus-host.packages"
USER_NAME="$(proteus_session_user)"

# 1. Packages — best-effort per package (mirror gaps must not fail the stage;
# the dashboard/Shares tab show honesty when a backend is missing).
if command -v pacman >/dev/null 2>&1; then
  while IFS= read -r pkg; do
    [[ -n "${pkg}" ]] || continue
    pacman -Q "${pkg}" >/dev/null 2>&1 && continue
    if proteus_root pacman -S --needed --noconfirm "${pkg}" 2>&1 | tail -4; then
      proteus_log "host pkg ${pkg} OK"
    else
      proteus_log "warn: ${pkg} not installed — host UI shows honesty"
    fi
  done < <(proteus_read_pkg_list "${LIST}")
else
  proteus_log "host: pacman missing — skip packages"
fi

# 2. Samba usershares — the no-root path: usershare dir + sambashare group
# membership lets `net usershare add/delete` work from the Workloads app.
if command -v net >/dev/null 2>&1; then
  proteus_root groupadd -f sambashare
  proteus_root install -d -m 1770 -g sambashare /var/lib/samba/usershares

  SMB_CONF=/etc/samba/smb.conf
  if [[ ! -f "${SMB_CONF}" ]]; then
    proteus_log "seeding minimal smb.conf (usershares)"
    proteus_root install -d -m 755 /etc/samba
    proteus_root bash -c "cat >${SMB_CONF}" <<'EOF'
[global]
   workgroup = WORKGROUP
   server string = Proteus host
   map to guest = Bad User
   usershare path = /var/lib/samba/usershares
   usershare max shares = 100
   usershare allow guests = yes
EOF
  elif ! grep -q 'usershare path' "${SMB_CONF}"; then
    proteus_log "enabling usershares in existing smb.conf"
    proteus_root sed -i '/^\[global\]/a\   usershare path = /var/lib/samba/usershares\n   usershare max shares = 100\n   usershare allow guests = yes' "${SMB_CONF}"
  else
    proteus_log "smb.conf usershares already configured"
  fi

  if [[ -n "${USER_NAME}" ]]; then
    proteus_root usermod -aG sambashare "${USER_NAME}" \
      || proteus_log "warn: could not add ${USER_NAME} to sambashare"
  fi

  if command -v systemctl >/dev/null 2>&1; then
    proteus_root systemctl enable --now smb 2>/dev/null \
      || proteus_log "warn: smb service not enabled (no systemd? chroot?) — Shares tab shows stopped"
  fi
else
  proteus_log "samba missing — Shares tab gates with the install path"
fi

# 3. SMART without a root shell: read-only health query only (-jH). The
# dashboard shows "—" honestly when this drop (or smartctl) is absent.
if command -v smartctl >/dev/null 2>&1 && [[ -n "${USER_NAME}" ]]; then
  SUDOERS_DROP=/etc/sudoers.d/proteus-smartctl
  if [[ ! -f "${SUDOERS_DROP}" ]]; then
    proteus_log "installing read-only smartctl sudoers drop"
    proteus_root bash -c "cat >${SUDOERS_DROP}" <<EOF
# Proteus host dashboard: read-only SMART health for the Storage card.
${USER_NAME} ALL=(root) NOPASSWD: /usr/bin/smartctl -jH /dev/*
EOF
    proteus_root chmod 440 "${SUDOERS_DROP}"
    if ! proteus_root visudo -cf "${SUDOERS_DROP}" >/dev/null 2>&1; then
      proteus_log "warn: sudoers drop failed validation — removing"
      proteus_root rm -f "${SUDOERS_DROP}"
    fi
  fi
else
  proteus_log "smartctl missing — SMART shows '—' on the dashboard"
fi

proteus_log "host OK (user=${USER_NAME})"
