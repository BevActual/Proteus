#!/usr/bin/env bash
# Clean native LocalSend install for dogfood (AUR localsend-bin).
# Run in a guest terminal and leave it open until the shell prompt returns.
set -euo pipefail

echo "=== LocalSend native reinstall ==="
echo
echo "Removing Flatpak copy (if present)…"
flatpak --user uninstall -y org.localsend.localsend_app 2>/dev/null || true

echo "Removing broken leftovers from interrupted install (sudo)…"
sudo rm -f /usr/bin/localsend /usr/share/applications/localsend.desktop
sudo rm -rf /opt/localsend

echo
echo "Installing AUR prebuilt localsend-bin…"
echo "Do NOT close this window / kill the VM until you see Done."
echo
yay -S --needed localsend-bin

echo
echo "Done. Binary check:"
if command -v localsend >/dev/null 2>&1; then
  real="$(readlink -f "$(command -v localsend)")"
  ls -la "${real}"
  sz="$(stat -c%s "${real}" 2>/dev/null || echo 0)"
  if [[ "${sz}" -lt 1024 ]]; then
    echo "ERROR: binary still empty — install did not complete cleanly." >&2
    exit 1
  fi
  echo "OK — localsend ready (${sz} bytes)."
else
  echo "ERROR: localsend not on PATH" >&2
  exit 1
fi

echo
read -r -p "Press Enter to close…" _
