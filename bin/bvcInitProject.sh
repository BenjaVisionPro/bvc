#!/usr/bin/env bash
set -euo pipefail

PROGNAME=$0
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)

# shellcheck disable=SC1091
. "${SCRIPT_DIR}/private/shFunctions"

load_bvc_config
setup_traps
start_banner "$@"
information_banner "Initialise Catalyst project"

usage() {
  cat 1>&2 <<EOF_USAGE
Usage:
  $(prog_basename "$PROGNAME") [projectName] [--template=templateName]

Initialises the current directory as a Catalyst project by copying a project template.
If projectName is omitted, the current directory name is used.
EOF_USAGE
  exit 1
}

templateName="default"
projectName=""

while [ $# -gt 0 ]; do
  case "$1" in
    --template=*) templateName=${1#*=} ;;
    --help|-h) usage ;;
    --*) error_banner "Unknown option for init: $1"; usage ;;
    *)
      if [ -z "$projectName" ]; then
        projectName="$1"
      else
        error_banner "Too many arguments for init."
        usage
      fi
      ;;
  esac
  shift
done

if [ -z "$projectName" ]; then
  projectName="${PWD##*/}"
fi

case "$projectName" in
  ''|.|..|*/*|*'..'*) exit_1_banner "Invalid project name: ${projectName}" ;;
  --*) exit_1_banner "Invalid project name: ${projectName}" ;;
esac

case "$templateName" in
  ''|.|..|*/*|*'..'*) exit_1_banner "Invalid template name: ${templateName}" ;;
  --*) exit_1_banner "Invalid template name: ${templateName}" ;;
esac

source_template="${BVC_TOOLKIT_ROOT}/templates/project/${templateName}"
target_config="${PWD}/config"
target_defaults="${target_config}/bvc/bvc_defaults"

[ -d "$source_template" ] || exit_1_banner "Project template not found: ${source_template}"
[ -d "$source_template/config" ] || exit_1_banner "Project template is missing config directory: ${source_template}/config"

if [ -e "$target_defaults" ]; then
  exit_1_banner "Current directory already contains config/bvc/bvc_defaults; refusing to overwrite."
fi

if [ -e "$target_config" ] && [ ! -d "$target_config" ]; then
  exit_1_banner "Current directory contains a non-directory ./config; refusing to overwrite."
fi

mkdir -p "$target_config"
cp -R "${source_template}/config/." "$target_config/"

[ -f "$target_defaults" ] || exit_1_banner "Template did not create expected file: ${target_defaults}"

# Replace the project name placeholder using awk for macOS/Linux portability.
tmp_defaults="${target_defaults}.tmp.$$"
awk -v projectName="$projectName" '{ gsub(/BVC_PROJECT_NAME:=MyProjectName/, "BVC_PROJECT_NAME:=" projectName); print }' "$target_defaults" > "$tmp_defaults"
mv "$tmp_defaults" "$target_defaults"

exit_0_banner "Catalyst project initialised: ${projectName}"
