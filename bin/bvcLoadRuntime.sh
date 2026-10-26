#!/usr/bin/env bash
# Incremental portable Runtime load into an existing Seaside/GT DevKit stone.
set -euo pipefail

PROGNAME=$0
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
. "${SCRIPT_DIR}/private/shFunctions"
load_bvc_config
setup_traps

usage() {
  printf '%s\n' 'Usage: bvcLoadRuntime.sh <deployment>' \
    'Load and check the portable Runtime production group in an existing Seaside DevKit stone.'
}
case "${1:-}" in --help|-h) usage; exit 0 ;; esac
[ "$#" -eq 1 ] || { usage >&2; exit 1; }
stoneName=$1
bvc_validate_deployment_name "$stoneName"
registry=$DEFAULT_REGISTRY
stoneDir="$(abs_from_cwd "$GSDEVKIT_STONES_DIR")/${stoneName}"
bvc_lock "$(abs_from_cwd "$GSDEVKIT_STONES_DIR")/.${stoneName}.bvc-lock"
ensure_gsdevkit_ready
deployment_exists "$registry" "$stoneName" || exit_1_banner "Deployment '${stoneName}' does not exist; create a Seaside DevKit stone first."
grep -Eq "#stoneDirectorySpecName[[:space:]]*:[[:space:]]*'default_seaside'" \
  "${stoneDir}/.GDKStoneSpec.ston" || exit_1_banner 'This helper requires an existing Seaside DevKit stone.'

projectsRoot=$(abs_from_cwd "$PROJECTS_ROOT")
export BVC_RUNTIME_REPOSITORY="${BVC_RUNTIME_REPOSITORY:-tonel://${projectsRoot}/projects/CatalystRuntime/src}"
case "$BVC_RUNTIME_REPOSITORY" in
  tonel://*) runtimeSources=${BVC_RUNTIME_REPOSITORY#tonel://} ;;
  *) exit_1_banner 'Use a verified local tonel:// Runtime checkout for this temporary load path.' ;;
esac
[ -d "$runtimeSources" ] || exit_1_banner "Missing Runtime sources: ${runtimeSources}"
foundationSources="${BVC_FOUNDATION_REPOSITORY:-tonel://${projectsRoot}/projects/CatalystFoundation/src}"
case "$foundationSources" in
  tonel://*) foundationSources=${foundationSources#tonel://} ;;
  *) exit_1_banner 'Use a local tonel:// Foundation checkout for source fingerprinting.' ;;
esac
[ -d "$foundationSources" ] || exit_1_banner "Missing Foundation sources: ${foundationSources}"
# Both local projects share the temporary Tonel reader installed by Foundation.
# Fingerprint this complete source selection so a retry can load corrected code.
export BVC_FOUNDATION_SOURCE_VERSION
BVC_FOUNDATION_SOURCE_VERSION=$(find "$runtimeSources" "$foundationSources" -type f -name '*.st' -exec cksum {} \; | LC_ALL=C sort | cksum | awk '{print $1}')
export BVC_RUNTIME_REPORT="${BVC_RUNTIME_REPORT:-${stoneDir}/portable-runtime-validation.ston}"
recipe=$(conf_resolve 'gemstone/load-portable-runtime.topaz')
login="${projectsRoot}/dev_tools/gt4gemstone/scripts/loginDataCurator.topaz"
[ -s "$recipe" ] || exit_1_banner "Missing Runtime load recipe: ${recipe}"
[ -s "$login" ] || exit_1_banner "Missing DevKit login script: ${login}"

bvc_start_stone "$registry" "$stoneName"
export STONE=$stoneName
export GEMSTONE="${stoneDir}/product"
export PATH="${GEMSTONE}/bin:${PATH}"
cd "$stoneDir"
topaz -l -I "$login" -S "$recipe" < /dev/zero
exit_0_banner "Portable Runtime loaded and checked in '${stoneName}'"
