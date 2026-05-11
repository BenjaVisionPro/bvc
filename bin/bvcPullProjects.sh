#!/usr/bin/env bash
set -euo pipefail

PROGNAME=$0
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)

# shellcheck disable=SC1091
. "${SCRIPT_DIR}/private/shFunctions"

load_bvc_config
setup_traps
start_banner "$@"
information_banner "Sync Catalyst project sets"

usage() {
  cat 1>&2 <<EOF_USAGE
Usage:
  $(prog_basename "$PROGNAME")

Syncs configured project sets using the registry from DEFAULT_REGISTRY.
EOF_USAGE
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h) usage ;;
    *) error_banner "Unexpected argument for pull: $1"; usage ;;
  esac
  shift
done

ensure_gsdevkit_ready
ensure_registry_exists "$DEFAULT_REGISTRY"

projectsRoot="$(abs_from_cwd "${PROJECTS_ROOT}")"
[ -d "${projectsRoot}" ] || mkdir -p "${projectsRoot}"

information_banner "Registry:      ${DEFAULT_REGISTRY}"
information_banner "Projects root: ${projectsRoot}"

"${SCRIPT_DIR}/setupProjects.sh" --registry="${DEFAULT_REGISTRY}"
exit_0_banner "Project sets synced"
