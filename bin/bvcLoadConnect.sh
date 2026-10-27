#!/usr/bin/env bash
# Incremental portable Connect load into the existing native Runtime stone.
set -euo pipefail
PROGNAME=$0
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
. "${SCRIPT_DIR}/private/shFunctions"
load_bvc_config
setup_traps
[ "$#" -eq 1 ] || { printf '%s\n' 'Usage: bvcLoadConnect.sh <deployment>' >&2; exit 1; }
stoneName=$1
bvc_validate_deployment_name "$stoneName"
stoneDir="$(abs_from_cwd "$GSDEVKIT_STONES_DIR")/${stoneName}"
bvc_lock "$(abs_from_cwd "$GSDEVKIT_STONES_DIR")/.${stoneName}.bvc-lock"
projectsRoot=$(abs_from_cwd "$PROJECTS_ROOT")
export BVC_CONNECT_REPOSITORY="${BVC_CONNECT_REPOSITORY:-tonel://${projectsRoot}/projects/CatalystConnect/src}"
case "$BVC_CONNECT_REPOSITORY" in
  tonel://*) sources=${BVC_CONNECT_REPOSITORY#tonel://} ;;
  *) exit_1_banner 'Use a verified local tonel:// Connect checkout.' ;;
esac
[ -d "$sources" ] || exit_1_banner "Missing Connect sources: ${sources}"
export BVC_FOUNDATION_SOURCE_VERSION
BVC_FOUNDATION_SOURCE_VERSION=$(find "$sources" -type f -name '*.st' -exec cksum {} \; | LC_ALL=C sort | cksum | awk '{print $1}')
export BVC_CONNECT_REPORT="${BVC_CONNECT_REPORT:-${stoneDir}/portable-connect-validation.json}"
recipe=$(conf_resolve 'gemstone/load-portable-connect.topaz')
"${SCRIPT_DIR}/bvcTopaz.sh" "$stoneName" --script "$recipe"
