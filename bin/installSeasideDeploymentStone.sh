#!/usr/bin/env bash
set -euo pipefail

PROGNAME=$0
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
. "${SCRIPT_DIR}/private/shFunctions"
load_bvc_config
setup_traps

case "${1:-}" in
  --help|-h) printf '%s\n' 'Usage: installSeasideDeploymentStone.sh <deployment> [version]'; exit 0 ;;
esac
[ "$#" -le 2 ] || exit_1_banner 'Too many arguments'
stoneName="${1:-$GEMSTONE_STONE_NAME}"
gemStoneVersion="${2:-$GEMSTONE_VERSION}"
bvc_validate_deployment_name "$stoneName"
registry=$DEFAULT_REGISTRY
stonesDir=$(abs_from_cwd "$GSDEVKIT_STONES_DIR")
stoneDir="${stonesDir}/${stoneName}"
projectsRoot=$(abs_from_cwd "$PROJECTS_ROOT")
gitDir_projects="${projectsRoot}/projects"
gitDir_devtools="${projectsRoot}/dev_tools"
installState="${stonesDir}/.${stoneName}.bvc-installing"
phase=seaside:creating

. "$(conf_resolve 'gemstone/installers/seaside_dev_tools.install')"
. "$(conf_resolve 'gemstone/installers/seaside_projects.install')"

save_phase() {
  phase="seaside:$1"
  printf '%s\n' "$phase" > "${installState}.tmp"
  mv "${installState}.tmp" "$installState"
}
step() {
  local previous=$1 next=$2
  shift 2
  if [ "$phase" = "seaside:${previous}" ]; then
    "$@"
    save_phase "$next"
  fi
}

[ -d "${STONES_HOME:-/nonexistent}" ] || exit_1_banner 'GsDevKit is required'
if deployment_exists "$registry" "$stoneName"; then
  [ -f "$installState" ] || exit_0_banner "Stone '${stoneName}' unchanged"
  grep -Eq "#stoneDirectorySpecName[[:space:]]*:[[:space:]]*'default_seaside'" \
    "${stoneDir}/.GDKStoneSpec.ston" || exit_1_banner 'Cannot resume a non-Seaside stone. Data has been preserved.'
  phase=$(cat "$installState")
  case "$phase" in
    seaside:created|seaside:configured|seaside:permissions|seaside:base|seaside:packaged|seaside:dictionary|seaside:gt|seaside:devtools|seaside:projects) ;;
    *) exit_1_banner "Installation state '${phase}' requires inspection. Data has been preserved." ;;
  esac
  [ -f "${stoneDir}/system.conf" ] || exit_1_banner 'Incomplete stone files. Data has been preserved.'
else
  [ ! -e "$stoneDir" ] || exit_1_banner "Unregistered stone directory already exists: ${stoneDir}"
  downloadGemStone.solo --registry="$registry" "$gemStoneVersion"
  updateClientLibs.solo --registry="$registry" "$gemStoneVersion"
  registerProduct.solo --registry="$registry" --fromDirectory="${STONES_HOME}/gemstone"
  "${SCRIPT_DIR}/bvcPullProjects.sh"
  mkdir -p "$stonesDir"
  registerStonesDirectory.solo --registry="$registry" --stonesDirectory="$stonesDir"
  save_phase creating
  createStone.solo --registry="$registry" --template=default_seaside "$stoneName" "$gemStoneVersion"
  save_phase created
fi

if [ "$phase" = seaside:created ]; then
  case "${OSTYPE:-}" in
    darwin*)
      if ! grep -q '^GEM_NATIVE_CODE_ENABLED=0;' "${stoneDir}/gem.conf"; then
        printf '%s\n' 'GEM_NATIVE_CODE_ENABLED=0;' >> "${stoneDir}/gem.conf"
      fi ;;
  esac
  updateCustomEnv.solo --registry="$registry" "$stoneName" \
    --addKey=ROWAN_PROJECTS_HOME --value="$gitDir_projects" --restart
  save_phase configured
fi
bvc_start_stone "$registry" "$stoneName"
bvc_refresh_gt4gemstone_properties "$registry"
export STONE=$stoneName
export GEMSTONE="${stoneDir}/product"
export ROWAN_PROJECTS_HOME=$gitDir_projects
export PATH="${stoneDir}/product/bin:${PATH}"
export BVC_FOUNDATION_REPOSITORY="${BVC_FOUNDATION_REPOSITORY:-tonel://${gitDir_projects}/CatalystFoundation/src}"
case "$BVC_FOUNDATION_REPOSITORY" in
  tonel://*)
    foundationSources=${BVC_FOUNDATION_REPOSITORY#tonel://}
    [ -d "$foundationSources" ] || exit_1_banner "Missing Foundation sources: ${foundationSources}"
    # The old reader fabricates a constant version. Fingerprint local source so
    # retries can load a corrected package without reloading the entire image.
    BVC_FOUNDATION_SOURCE_VERSION=$(find "$foundationSources" -type f -name '*.st' -exec cksum {} \; | LC_ALL=C sort | cksum | awk '{print $1}')
    export BVC_FOUNDATION_SOURCE_VERSION ;;
  *) export BVC_FOUNDATION_SOURCE_VERSION="${BVC_FOUNDATION_SOURCE_VERSION:-1}" ;;
esac
export BVC_FOUNDATION_REPORT="${BVC_FOUNDATION_REPORT:-${stoneDir}/portable-foundation-validation.ston}"
export GEMSTONE_WORKSPACE="${stoneDir}/.bvc-gt-package"
export RELEASED_PACKAGE_GEMSTONE_NAME=gt4gemstone-3.7
export GT4GEMSTONE_VERSION="${GT4GEMSTONE_VERSION:-dev}"
cd "$stoneDir"
step configured permissions seaside_permissions
step permissions base seaside_base
step base packaged seaside_package
step packaged dictionary seaside_dictionary
step dictionary gt seaside_gt
step gt devtools seaside_patches
step devtools projects install_seaside_projects
rm -f "$installState"
exit_0_banner "Seaside DevKit '${stoneName}' and portable Foundation are ready"
