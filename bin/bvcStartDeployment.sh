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
  $(prog_basename "$PROGNAME") <deploymentName>
EOF_USAGE
  exit "${1:-1}"
}

deploymentName=""

while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h) usage 0 ;;
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
bvc_validate_deployment_name "$deploymentName"
stones_dir="$(abs_from_cwd "$GSDEVKIT_STONES_DIR")"
bvc_lock "${stones_dir}/.${deploymentName}.bvc-lock"
ensure_gsdevkit_ready
ensure_registry_exists "$DEFAULT_REGISTRY"

if [ -f "${stones_dir}/.${deploymentName}.bvc-installing" ]; then
  install_phase=$(cat "${stones_dir}/.${deploymentName}.bvc-installing")
  case "$install_phase" in
    ''|rowan:*) ;;
    *) exit_1_banner "Unsupported installation state for '${deploymentName}': ${install_phase}. Only Rowan installations can be resumed. Data has been preserved." ;;
  esac
  # The Rowan installer resumes its own recorded steps, including legacy empty
  # markers. It verifies the stone template before touching an existing stone.
  information_banner "Resuming installation of deployment '${deploymentName}'"
  "${SCRIPT_DIR}/installDeploymentStone.sh" "$deploymentName"
  exit_0_banner "Deployment '${deploymentName}' installed and running"
fi

if deployment_exists "$DEFAULT_REGISTRY" "$deploymentName"; then
  information_banner "Deployment '${deploymentName}' exists; starting it."
  bvc_start_stone "$DEFAULT_REGISTRY" "$deploymentName"
  exit_0_banner "Deployment '${deploymentName}' started"
fi

information_banner "Deployment '${deploymentName}' not found; installing Rowan stone."
"${SCRIPT_DIR}/installDeploymentStone.sh" "$deploymentName"
