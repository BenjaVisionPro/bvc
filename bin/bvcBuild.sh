#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
. "${SCRIPT_DIR}/private/shFunctions"
load_bvc_config
setup_traps

case "${1:-}" in
  -h|--help)
    printf '%s\n' 'Usage: bvc build [--with-seaside]' \
      'Build the DevKit/app and configured GemStone deployment, then run both.'
    exit 0 ;;
esac
case "$#:${1:-}" in
  0:|1:--with-seaside) ;;
  *) exit_1_banner 'Usage: bvc build [--with-seaside]' ;;
esac

# Use exactly the same installation/start paths as the individual commands.
"${SCRIPT_DIR}/bvcStartDeployment.sh" "${GEMSTONE_STONE_NAME}" "$@"
"${SCRIPT_DIR}/bvcLaunchDevKit.sh"
exit_0_banner "DevKit/app and GemStone deployment '${GEMSTONE_STONE_NAME}' are running"
