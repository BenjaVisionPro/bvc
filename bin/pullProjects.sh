#! /usr/bin/env sh
set -eu

PROGNAME=$0
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)

# shellcheck disable=SC1091
. "${SCRIPT_DIR}/private/shFunctions"

# Layered config (ENV > CWD/*.bvc > $BVC_CONF_DIR/bvc/bvc_defaults > bundled > safety net)
load_bvc_config

setup_traps
start_banner "$@"
information_banner "Sync Project Sets"

usage() {
  cat 1>&2 <<EOF
Usage:
  $(prog_basename "$PROGNAME") [--registry=NAME]

Behavior:
  1) Ensure configured project sets are present from conf/projectSets.
  2) Delegate clone/update behavior to gsDevKit_stones project set commands.

Defaults:
  registry:      ${DEFAULT_REGISTRY}
  projects root: $(abs_from_cwd "${PROJECTS_ROOT}")
EOF
  exit 1
}

registry="${DEFAULT_REGISTRY}"
while [ $# -gt 0 ]; do
  case "$1" in
    --registry=*) registry=${1#*=} ;;
    --help|-h)    usage ;;
    --*)          error_banner "Unknown option: $1"; usage ;;
    *)            error_banner "Unexpected positional: $1"; usage ;;
  esac
  shift
done

if [ -z "${STONES_HOME:-}" ] || [ ! -d "${STONES_HOME:-/nonexistent}" ]; then
  error_banner "STONES_HOME is not set or does not exist."
  exit_1_banner "Run 'bvc init' before syncing project sets."
fi

projectsRoot="$(abs_from_cwd "${PROJECTS_ROOT}")"
[ -d "${projectsRoot}" ] || mkdir -p "${projectsRoot}"

information_banner "Registry:      ${registry}"
information_banner "Projects root: ${projectsRoot}"

# Ensure project sets/directories/repositories are synced via gsDevKit_stones.
"${SCRIPT_DIR}/setupProjects.sh" --registry="${registry}"
exit_0_banner "Project sets synced"
