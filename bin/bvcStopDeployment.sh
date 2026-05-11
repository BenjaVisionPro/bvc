#!/usr/bin/env bash
set -euo pipefail

PROGNAME=$0
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)

# shellcheck disable=SC1091
. "${SCRIPT_DIR}/private/shFunctions"

load_bvc_config
setup_traps
start_banner "$@"
information_banner "Stop Catalyst deployment"

usage() {
  cat 1>&2 <<EOF_USAGE
Usage:
  $(prog_basename "$PROGNAME") <deploymentName>
EOF_USAGE
  exit 1
}

[ $# -eq 1 ] || usage
case "$1" in --*|'') usage ;; esac
deploymentName="$1"

ensure_gsdevkit_ready
stopStone.solo --registry="$DEFAULT_REGISTRY" -b "$deploymentName"
exit_0_banner "Deployment '${deploymentName}' stopped"
