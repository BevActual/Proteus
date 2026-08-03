#!/usr/bin/env bash
# login — greetd + proteus-session (reuses apply-greeter.sh)
set -euo pipefail
# shellcheck source=helpers.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

PROTEUS_ROOT="$(proteus_install_root)"
proteus_root bash "${PROTEUS_ROOT}/install/machine/apply-greeter.sh"
proteus_log "login OK"
