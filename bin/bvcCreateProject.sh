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
  $(prog_basename "$PROGNAME") <projectName> [--template=templateName]
EOF_USAGE
  exit 1
}

templateName="default"
projectName=""

while [ $# -gt 0 ]; do
  case "$1" in
    --template=*) templateName=${1#*=} ;;
    --help|-h) usage ;;
    --*) error_banner "Unknown option for create: $1"; usage ;;
    *)
      if [ -z "$projectName" ]; then
        projectName="$1"
      else
        error_banner "Too many arguments for create."
        usage
      fi
      ;;
  esac
  shift
done

[ -n "$projectName" ] || usage

case "$projectName" in
  ''|.|..|*/*|*'..'*) exit_1_banner "Invalid project name: ${projectName}" ;;
  --*) exit_1_banner "Invalid project name: ${projectName}" ;;
esac

case "$templateName" in
  ''|.|..|*/*|*'..'*) exit_1_banner "Invalid template name: ${templateName}" ;;
  --*) exit_1_banner "Invalid template name: ${templateName}" ;;
esac

if [ -e "$projectName" ]; then
  exit_1_banner "Project directory already exists: ${projectName}"
fi

mkdir "$projectName"
(
  cd "$projectName"
  "${SCRIPT_DIR}/bvcInitProject.sh" "$projectName" --template="$templateName"
)

exit_0_banner "Catalyst project created: ${projectName}"
