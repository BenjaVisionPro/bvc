#!/usr/bin/env bash
set -euo pipefail

PROGNAME=$0
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)

# shellcheck disable=SC1091
. "${SCRIPT_DIR}/private/shFunctions"

load_bvc_config
setup_traps
start_banner "$@"
# information_banner "List stones"

usage() {
  cat 1>&2 <<EOF_USAGE
Usage:
  $(prog_basename "$PROGNAME")
EOF_USAGE
  exit 1
}

[ $# -eq 0 ] || usage

ensure_gsdevkit_ready
ensure_registry_exists "$DEFAULT_REGISTRY"

information_banner "Registered stones:"
registry_report_file=$(mktemp "${TMPDIR:-/tmp}/bvc-registry-report.XXXXXX")
cleanup() { rm -f "$registry_report_file"; }
trap 'cleanup; spinner_stop' EXIT

registryReport.solo --registry="$DEFAULT_REGISTRY" > "$registry_report_file"

registered_count=0
while IFS= read -r deploymentName; do
  if [ -n "$deploymentName" ]; then
    printf '  %s\n' "$deploymentName"
    registered_count=$((registered_count + 1))
  fi
done < <(bvc_parse_registry_stones < "$registry_report_file")

if [ "$registered_count" -eq 0 ]; then
  printf '  %s\n' '(none)'
fi

printf '\n' 1>&2
information_banner "Running stones from gslist.solo -lc:"
gslist.solo -lc
