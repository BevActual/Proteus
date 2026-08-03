#!/usr/bin/env bash
# Ensure Flatpak user remote "flathub" exists (idempotent).
set -euo pipefail

if ! command -v flatpak >/dev/null 2>&1; then
  echo "ensure-flathub: flatpak not installed — skip"
  exit 0
fi

flatpak remote-add --user --if-not-exists flathub \
  https://dl.flathub.org/repo/flathub.flatpakrepo

echo "ensure-flathub: OK (user remote flathub)"
