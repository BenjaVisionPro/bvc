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

--with-seaside creates a Seaside/GT DevKit stone and loads portable Foundation.
It only selects the installer for new or incomplete deployments.
EOF_USAGE
  exit "${1:-1}"
}

deploymentName=""
with_seaside=0

while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h) usage 0 ;;
    --with-seaside) with_seaside=1 ;;
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
installer=installDeploymentStone.sh
install_kind=rowan
if [ "$with_seaside" -eq 1 ]; then
  installer=installSeasideDeploymentStone.sh
  install_kind=seaside
fi

if [ -f "${stones_dir}/.${deploymentName}.bvc-installing" ]; then
  install_phase=$(cat "${stones_dir}/.${deploymentName}.bvc-installing")
  if [ "$install_kind" = rowan ]; then
    case "$install_phase" in
      ''|rowan:*) ;;
      *) exit_1_banner "Unsupported installation state for '${deploymentName}': ${install_phase}. Only Rowan installations can be resumed without --with-seaside. Data has been preserved." ;;
    esac
  else
    case "$install_phase" in
      seaside:*) ;;
      *) exit_1_banner "Cannot resume '${install_phase}' with --with-seaside. Data has been preserved." ;;
    esac
  fi
  # Each installer verifies the actual stone template before resuming its
  # recorded steps. Only Rowan accepts the legacy empty marker.
  information_banner "Resuming installation of deployment '${deploymentName}'"
  "${SCRIPT_DIR}/${installer}" "$deploymentName"
  exit_0_banner "Deployment '${deploymentName}' installed and running"
fi

if deployment_exists "$DEFAULT_REGISTRY" "$deploymentName"; then
  information_banner "Deployment '${deploymentName}' exists; starting it."
  bvc_start_stone "$DEFAULT_REGISTRY" "$deploymentName"
  exit_0_banner "Deployment '${deploymentName}' started"
fi

information_banner "Deployment '${deploymentName}' not found; installing ${install_kind} stone."
"${SCRIPT_DIR}/${installer}" "$deploymentName"
