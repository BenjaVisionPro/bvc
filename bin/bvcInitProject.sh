#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
. "${SCRIPT_DIR}/private/shFunctions"
setup_traps

usage() {
  printf '%s\n' 'Usage: bvc init [directory] [--template=NAME]' \
    'Initialise the current directory, or create and initialise the supplied directory.'
  exit "${1:-1}"
}

directory=''
templateName=default
for arg in "$@"; do
  case "$arg" in
    -h|--help) usage 0 ;;
    --template=*) templateName=${arg#*=} ;;
    -*) error_banner "Unknown option: $arg"; usage ;;
    *) [ -z "$directory" ] || usage; directory=$arg ;;
  esac
done
case "$templateName" in
  ''|.|..|*/*|*'..'*) exit_1_banner "Invalid template name: $templateName" ;;
esac
source_template="${SCRIPT_DIR}/../templates/project/${templateName}"
[ -f "${source_template}/config/bvc/bvc_defaults" ] || \
  exit_1_banner "Project template not found or missing defaults: ${templateName}"

mkdir -p -- "${directory:-.}"
cd -- "${directory:-.}"
projectName=${PWD##*/}
# This value is embedded in a sourced shell config, so accept a simple name.
case "$projectName" in
  ''|*[!a-zA-Z0-9._\ -]*) exit_1_banner "Unsupported project directory name: ${projectName}" ;;
esac

load_bvc_config
target_config=$BVC_PROJECT_CONFIG_ROOT
target_defaults="${target_config}/bvc/bvc_defaults"
if [ -f "$target_defaults" ]; then
  exit_0_banner "Catalyst project already initialised: ${PWD}"
fi
if [ -e "$target_defaults" ]; then
  exit_1_banner "Cannot write project defaults: ${target_defaults}"
fi

# Never overwrite files in an existing project. Copy the template's root files
# too (notably .gitignore); BVC_CONF_DIR only relocates its config directory.
mkdir -p "$target_config"
cp -Rn "${source_template}/config/." "$target_config/"
while IFS= read -r -d '' entry; do
  [ "${entry##*/}" = config ] && continue
  [ -e "./${entry##*/}" ] || cp -R "$entry" ./
done < <(find "$source_template" -mindepth 1 -maxdepth 1 -print0)

tmp_defaults="${target_defaults}.tmp.$$"
awk -v projectName="$projectName" \
  '{ gsub(/BVC_PROJECT_NAME:=MyProjectName/, "BVC_PROJECT_NAME:=" projectName); print }' \
  "$target_defaults" > "$tmp_defaults"
mv "$tmp_defaults" "$target_defaults"
exit_0_banner "Catalyst project initialised: ${PWD}"
