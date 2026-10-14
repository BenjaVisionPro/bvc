#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
. "${SCRIPT_DIR}/private/shFunctions"
load_bvc_config
setup_traps

stoneName="${1:?Deployment name is required}"
bvc_validate_deployment_name "$stoneName"
stoneDir="$(abs_from_cwd "$GSDEVKIT_STONES_DIR")/${stoneName}"
installState="$(abs_from_cwd "$GSDEVKIT_STONES_DIR")/.${stoneName}.bvc-installing"
completed="${stoneDir}/.bvc-catalyst-loaded"
stoneSpec="${stoneDir}/.GDKStoneSpec.ston"
grep -Eq "#stoneDirectorySpecName[[:space:]]*:[[:space:]]*'default_seaside'" "$stoneSpec" || \
  exit_1_banner "Cannot load Seaside projects into '${stoneName}': local Seaside stone specification required"

if [ -f "$completed" ]; then
  rm -f "$installState"
  exit_0_banner "Catalyst projects already installed in '${stoneName}'"
fi

projectsDir="$(project_set_dir projects)"
loginScript="$(project_set_dir dev_tools)/gt4gemstone/scripts/loginDataCurator.topaz"
missing=0
for project in CatalystFoundation CatalystRuntime CatalystProcess; do
  [ -f "${projectsDir}/${project}/src/BaselineOf${project}/BaselineOf${project}.class.st" ] || missing=1
done
[ -f "$loginScript" ] || missing=1
if [ "$missing" -eq 1 ]; then
  "${SCRIPT_DIR}/bvcPullProjects.sh"
fi
for project in CatalystFoundation CatalystRuntime CatalystProcess; do
  [ -f "${projectsDir}/${project}/src/BaselineOf${project}/BaselineOf${project}.class.st" ] || \
    exit_1_banner "Missing local baseline for ${project} under ${projectsDir}"
done
[ -f "$loginScript" ] || exit_1_banner "Missing GemStone login script: ${loginScript}"
loader=$(conf_resolve 'gemstone/installers/loadProjects.topaz')
export STONE="$stoneName"
export GEMSTONE="${stoneDir}/product"
export PATH="${GEMSTONE}/bin:$PATH"
cd "$stoneDir"

# The caller holds the deployment lock. Mark the whole load complete only
# after Topaz succeeds; a failed attempt reruns the same single load script.
printf '%s\n' seaside:projects > "$installState"
information_banner "Loading GemStone projects in '${stoneName}' (Metacello)"
PROJECTS_ROOT="$projectsDir" topaz -l -I "$loginScript" -S "$loader" < /dev/null
touch "$completed"
rm -f "$installState"
exit_0_banner "Catalyst Foundation, Runtime and Process installed in '${stoneName}'"
