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
  exit "${1:-1}"
}

with_seaside=0
deploymentName=""

while [ $# -gt 0 ]; do
  case "$1" in
    --with-seaside) with_seaside=1 ;;
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
    seaside:projects)
      bvc_start_stone "$DEFAULT_REGISTRY" "$deploymentName"
      "${SCRIPT_DIR}/installSeasideProjects.sh" "$deploymentName"
      exit_0_banner "Deployment '${deploymentName}' installed and running" ;;
    seaside*) exit_1_banner "Seaside installation '${deploymentName}' is incomplete and requires inspection before retrying. Data has been preserved." ;;
    ''|rowan:*) ;;
    *) exit_1_banner "Unknown installation state for '${deploymentName}': ${install_phase}" ;;
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
  if grep -Eq "#stoneDirectorySpecName[[:space:]]*:[[:space:]]*'default_seaside'" \
      "${stones_dir}/${deploymentName}/.GDKStoneSpec.ston" 2>/dev/null; then
    "${SCRIPT_DIR}/installSeasideProjects.sh" "$deploymentName"
  fi
  exit_0_banner "Deployment '${deploymentName}' started"
fi

if [ "$with_seaside" -eq 1 ]; then
  information_banner "Deployment '${deploymentName}' not found; installing devkit stone with Seaside path."
  "${SCRIPT_DIR}/installSeasideDeploymentStone.sh" "$deploymentName"
else
  information_banner "Deployment '${deploymentName}' not found; installing rowan stone."
  "${SCRIPT_DIR}/installDeploymentStone.sh" "$deploymentName"
fi
