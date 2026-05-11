#!/usr/bin/env bash
set -euo pipefail

PROGNAME=$0
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)

# shellcheck disable=SC1091
. "${SCRIPT_DIR}/private/shFunctions"

load_bvc_config
setup_traps
start_banner "$@"
information_banner "Delete Catalyst deployment"

usage() {
  cat 1>&2 <<EOF_USAGE
Usage:
  $(prog_basename "$PROGNAME") <deploymentName> [-f|--force]
EOF_USAGE
  exit 1
}

force=0
deploymentName=""
while [ $# -gt 0 ]; do
  case "$1" in
    -f|--force) force=1 ;;
    --help|-h) usage ;;
    --*) error_banner "Unknown option for delete: $1"; usage ;;
    *)
      if [ -z "$deploymentName" ]; then
        deploymentName="$1"
      else
        error_banner "Too many arguments for delete."
        usage
      fi
      ;;
  esac
  shift
done

[ -n "$deploymentName" ] || usage

if [ "$force" -ne 1 ]; then
  warning_banner "This will delete deployment '${deploymentName}' and all associated data."
  printf "Type the deployment name to continue: " 1>&2
  IFS= read -r confirmation
  if [ "$confirmation" != "$deploymentName" ]; then
    exit_1_banner "Delete cancelled"
  fi
fi

ensure_gsdevkit_ready
deleteStone.solo --registry="$DEFAULT_REGISTRY" -b "$deploymentName"
exit_0_banner "Deployment '${deploymentName}' deleted"
