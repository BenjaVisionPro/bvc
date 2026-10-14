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
  exit "${1:-1}"
}

case "${1:-}" in --help|-h) usage 0 ;; esac

[ $# -eq 1 ] || usage
case "$1" in --*|'') usage ;; esac
deploymentName="$1"
bvc_validate_deployment_name "$deploymentName"

ensure_gsdevkit_ready
bvc_lock "$(abs_from_cwd "$GSDEVKIT_STONES_DIR")/.${deploymentName}.bvc-lock"
if bvc_stone_running "$deploymentName"; then
  stopStone.solo --registry="$DEFAULT_REGISTRY" -b "$deploymentName"
else
  stopNetldi.solo --registry="$DEFAULT_REGISTRY" "$deploymentName"
fi
exit_0_banner "Deployment '${deploymentName}' stopped"
