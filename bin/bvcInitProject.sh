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
  $(prog_basename "$PROGNAME")

Initialises the current directory as a Catalyst project by copying the bundled conf directory.
EOF_USAGE
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h) usage ;;
    *) error_banner "Unexpected argument for init: $1"; usage ;;
  esac
  shift
done

source_conf="${SCRIPT_DIR}/../conf"
target_conf="${PWD}/conf"

[ -d "$source_conf" ] || exit_1_banner "Bundled conf directory not found: ${source_conf}"

if [ -e "$target_conf" ]; then
  exit_1_banner "Current directory already contains ./conf; refusing to overwrite."
fi

cp -R "$source_conf" "$target_conf"
exit_0_banner "Catalyst project initialised"
