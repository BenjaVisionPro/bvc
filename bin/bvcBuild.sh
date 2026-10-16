#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
. "${SCRIPT_DIR}/private/shFunctions"
load_bvc_config
setup_traps

case "${1:-}" in
  -h|--help)
    printf '%s\n' 'Usage: bvc build' \
      'Build the DevKit/app and install the configured Rowan GemStone deployment, then run both.'
    exit 0 ;;
esac
if [ "$#" -gt 0 ]; then
  exit_1_banner 'Usage: bvc build'
fi

# Use exactly the same installation/start paths as the individual commands.
"${SCRIPT_DIR}/bvcStartDeployment.sh" "${GEMSTONE_STONE_NAME}"
"${SCRIPT_DIR}/bvcLaunchDevKit.sh"
exit_0_banner "DevKit/app and GemStone deployment '${GEMSTONE_STONE_NAME}' are running"
