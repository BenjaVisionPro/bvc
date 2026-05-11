#!/usr/bin/env bash
set -euo pipefail

PROGNAME=$0
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)

# shellcheck disable=SC1091
. "${SCRIPT_DIR}/private/shFunctions"

load_bvc_config
setup_traps
start_banner "$@"
information_banner "Create Catalyst project"

usage() {
  cat 1>&2 <<EOF_USAGE
Usage:
  $(prog_basename "$PROGNAME") <projectName>
EOF_USAGE
  exit 1
}

[ $# -eq 1 ] || usage
projectName="$1"

case "$projectName" in
  ''|.|..|*/*|*'..'*) exit_1_banner "Invalid project name: ${projectName}" ;;
  --*) exit_1_banner "Invalid project name: ${projectName}" ;;
esac

if [ -e "$projectName" ]; then
  exit_1_banner "Project directory already exists: ${projectName}"
fi

mkdir "$projectName"
(
  cd "$projectName"
  "${SCRIPT_DIR}/bvcInitProject.sh"
)

exit_0_banner "Catalyst project created: ${projectName}"
