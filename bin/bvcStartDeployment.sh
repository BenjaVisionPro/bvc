#!/usr/bin/env bash
set -euo pipefail

PROGNAME=$0
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)

# shellcheck disable=SC1091
. "${SCRIPT_DIR}/private/shFunctions"

load_bvc_config
setup_traps
start_banner "$@"
information_banner "Start Catalyst deployment"

usage() {
  cat 1>&2 <<EOF_USAGE
Usage:
  $(prog_basename "$PROGNAME") <deploymentName> [--with-seaside]

Notes:
  --with-seaside only affects first install when the deployment does not yet exist.
EOF_USAGE
  exit 1
}

with_seaside=0
deploymentName=""

while [ $# -gt 0 ]; do
  case "$1" in
    --with-seaside) with_seaside=1 ;;
    --help|-h) usage ;;
    --*) error_banner "Unknown option for start: $1"; usage ;;
    *)
      if [ -z "$deploymentName" ]; then
        deploymentName="$1"
      else
        error_banner "Too many arguments for start."
        usage
      fi
      ;;
  esac
  shift
done

[ -n "$deploymentName" ] || usage

ensure_gsdevkit_ready
ensure_registry_exists "$DEFAULT_REGISTRY"

if deployment_exists "$DEFAULT_REGISTRY" "$deploymentName"; then
  information_banner "Deployment '${deploymentName}' exists; starting it."
  startStone.solo --registry="$DEFAULT_REGISTRY" "$deploymentName" -b
  exit_0_banner "Deployment '${deploymentName}' started"
fi

if [ "$with_seaside" -eq 1 ]; then
  information_banner "Deployment '${deploymentName}' not found; installing with temporary Seaside path."
  "${SCRIPT_DIR}/installSeasideDeploymentStone.sh" "$deploymentName"
else
  information_banner "Deployment '${deploymentName}' not found; installing."
  "${SCRIPT_DIR}/installDeploymentStone.sh" "$deploymentName"
fi
