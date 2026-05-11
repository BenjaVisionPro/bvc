#!/usr/bin/env bash
set -euo pipefail

PROGNAME=$0
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)

# shellcheck disable=SC1091
. "${SCRIPT_DIR}/private/shFunctions"

load_bvc_config
setup_traps
start_banner "$@"
information_banner "Launch Jadeite for Pharo"

usage() {
  cat 1>&2 <<EOF_USAGE
Usage:
  $(prog_basename "$PROGNAME")
EOF_USAGE
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h) usage ;;
    *) error_banner "Unknown option for j4p: $1"; usage ;;
  esac
  shift
done

ensure_gsdevkit_ready
ensure_registry_exists "$DEFAULT_REGISTRY"

if ! j4p_installed; then
  information_banner "Jadeite for Pharo not found locally; syncing project sets before build."
  "${SCRIPT_DIR}/bvcPullProjects.sh"
  "${SCRIPT_DIR}/bvcBuildJadeiteForPharo.sh"
fi

j4p_dir="$(abs_from_cwd "${J4P_INSTALL_DIR}")"
[ -d "$j4p_dir" ] || exit_1_banner "Jadeite for Pharo install directory not found: ${j4p_dir}"

rowan_home="$(abs_from_cwd "${PROJECTS_ROOT}/dev_tools")"
information_banner "Launching J4P from ${j4p_dir} (ROWAN_PROJECTS_HOME=${rowan_home})"
(
  cd "$j4p_dir"
  ROWAN_PROJECTS_HOME="$rowan_home" ./pharo-ui --
)
