#!/usr/bin/env bash
# install-console-software — thin wrapper over the overlay `console` stage.
# SoT for console packages: vm/install/proteus-console.packages (multilib,
# Steam + lib32, RetroArch + cores, pad udev) — see vm/install/console.sh.
# Usage (guest): sudo bash /mnt/proteus/vm/guest/install-console-software.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)"

echo "==> install-console-software → vm/install/console.sh"
bash "${ROOT}/vm/install/console.sh"

echo "==> done"
command -v steam >/dev/null && echo "  steam: $(command -v steam)" || echo "  steam: MISSING"
command -v retroarch >/dev/null && echo "  retroarch: $(command -v retroarch)" || echo "  retroarch: MISSING"
command -v gamescope >/dev/null && echo "  gamescope: $(command -v gamescope)" || echo "  gamescope: MISSING"
