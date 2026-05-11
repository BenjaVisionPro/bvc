#! /usr/bin/env sh
set -eu

PROGNAME=$0
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)

# shellcheck disable=SC1091
. "${SCRIPT_DIR}/private/shFunctions"

# Load layered config (ENV > CWD/*.bvc > $BVC_CONF_DIR/bvc/bvc_defaults > bundled > safety net)
load_bvc_config

# ---------------------------------------------------------
# Required installers (fatal if missing)
# Must provide:
#   - install_devtools_projects <gitDirForDevTools>
#   - install_projects <gitDirForProjects>
# ---------------------------------------------------------
# shellcheck disable=SC1090
. "$(conf_resolve 'gemstone/installers/dev_tools.install')"
# shellcheck disable=SC1090
. "$(conf_resolve 'gemstone/installers/projects.install')"

setup_traps
start_banner "$@"
information_banner "Create Development Stone"

usage() {
  cat 1>&2 <<EOF
Usage:
  $(prog_basename "$PROGNAME") [--registry=NAME] [stoneName [gemstoneVersion]]

Where:
  --registry=NAME       Registry to use (default: ${DEFAULT_REGISTRY})
  stoneName             Name of the stone (default: ${GEMSTONE_STONE_NAME})
  gemstoneVersion       GemStone version (default: ${GEMSTONE_VERSION})

Examples:
  $(prog_basename "$PROGNAME")
  $(prog_basename "$PROGNAME") myStone
  $(prog_basename "$PROGNAME") myStone 3.7.4.3
  $(prog_basename "$PROGNAME") --registry=myReg myStone 3.7.4.3
EOF
  exit 1
}

# ---------------------------------------------------------
# Args
# 0 args -> defaults
# 1 arg  -> <stoneName>
# 2 args -> <stoneName> <gemstoneVersion>
# Optional --registry=NAME can appear anywhere.
# ---------------------------------------------------------
registry="${DEFAULT_REGISTRY}"
gemStoneVersion="${GEMSTONE_VERSION}"
stoneName="${GEMSTONE_STONE_NAME}"

pos1=""
pos2=""

while [ $# -gt 0 ]; do
  case "$1" in
    --registry=*) registry=${1#*=} ;;
    --help|-h)    usage ;;
    --*)          error_banner "Unknown option: $1"; usage ;;
    *)
      if [ -z "$pos1" ]; then
        pos1="$1"
      elif [ -z "$pos2" ]; then
        pos2="$1"
      else
        error_banner "Too many positional arguments."
        usage
      fi
      ;;
  esac
  shift
done

# Apply positionals over defaults
if [ -n "$pos1" ] && [ -z "$pos2" ]; then
  stoneName="$pos1"
elif [ -n "$pos1" ] && [ -n "$pos2" ]; then
  stoneName="$pos1"
  gemStoneVersion="$pos2"
fi

information_banner "Registry: ${registry}"
information_banner "Version : ${gemStoneVersion}"
information_banner "Stone   : ${stoneName}"

# ---------------------------------------------------------
# Sanity checks
# ---------------------------------------------------------
if [ -z "${STONES_HOME:-}" ] || [ ! -d "${STONES_HOME:-/nonexistent}" ]; then
  error_banner "STONES_HOME is not set or does not exist."
  exit_1_banner "Run 'bvc init' to set up GSDevKit before creating a stone."
fi

# ---------------------------------------------------------
# Paths (CWD-relative by design)
# ---------------------------------------------------------
workingDirectory="$(pwd)"
projectPath="${workingDirectory}"
stonesDir="${projectPath}/${GSDEVKIT_STONES_DIR}"

# New projects root model
projectsRoot="$(abs_from_cwd "${PROJECTS_ROOT}")"
gitDir_projects="${projectsRoot}/projects"
gitDir_devtools="${projectsRoot}/dev_tools"

# Ensure root exists (per-set dirs will be ensured by setupProjects)
[ -d "${projectsRoot}" ] || mkdir -p "${projectsRoot}"

# ---------------------------------------------------------
# If the stone already exists, leave it alone
# ---------------------------------------------------------
if registryReport.solo --registry="$registry" --stone="$stoneName" >/dev/null 2>&1; then
  information_banner "Stone '${stoneName}' already exists in registry '${registry}' — leaving it unchanged."
  information_banner "To recreate: stop the stone, delete its directory (in '${stonesDir}/${stoneName}' or '${STONES_HOME}/${stoneName}'), then rerun."
  exit_0_banner "Stone '${stoneName}' unchanged"
fi

# ---------------------------------------------------------
# Products (GemStone VM + client libs) and registration
# ---------------------------------------------------------
information_banner "Installing GemStone ${gemStoneVersion}"
downloadGemStone.solo   --registry="$registry" "$gemStoneVersion"
updateClientLibs.solo   --registry="$registry" "$gemStoneVersion"

information_banner "Registering GemStone ${gemStoneVersion}"
registerProduct.solo    --registry="$registry" --fromDirectory="${STONES_HOME}/gemstone"

# ---------------------------------------------------------
# Project sets + repo updates
# Ensures configured sets are synced via gsDevKit_stones project-set commands.
# ---------------------------------------------------------
information_banner "Syncing project sets under ${projectsRoot}"
"${SCRIPT_DIR}/pullProjects.sh" --registry="${registry}"

# ---------------------------------------------------------
# Stones directory (where local stones live)
# ---------------------------------------------------------
information_banner "Ensuring stones directory: ${stonesDir}"
[ -d "${stonesDir}" ] || mkdir -p "${stonesDir}"

information_banner "Registering stones directory: ${stonesDir}"
registerStonesDirectory.solo --registry="$registry" --stonesDirectory="${stonesDir}"

# ---------------------------------------------------------
# Create the stone (template: default_seaside)
# ---------------------------------------------------------
information_banner "Creating stone '${stoneName}' (template: default_seaside)"
createStone.solo --registry="$registry" --template=default_seaside "$stoneName" "$gemStoneVersion"

# macOS: disable native code (JIT) for this stone
case "${OSTYPE:-}" in
  darwin*)
    warning_banner "Disabling Native Code for stone '${stoneName}' (macOS)"
    printf '%s\n' "GEM_NATIVE_CODE_ENABLED=0;" >> "${stonesDir}/${stoneName}/gem.conf"
    ;;
esac

# ---------------------------------------------------------
# Environment for tooling (ROWAN) — MUST point to projects set
# ---------------------------------------------------------
information_banner "Setting ROWAN_PROJECTS_HOME=${gitDir_projects}"
export ROWAN_PROJECTS_HOME="${gitDir_projects}"
updateCustomEnv.solo --registry="$registry" "$stoneName" \
  --addKey=ROWAN_PROJECTS_HOME --value="$ROWAN_PROJECTS_HOME" --restart

# ---------------------------------------------------------
# Start the stone & show status
# ---------------------------------------------------------
information_banner "Starting stone '${stoneName}'"
startStone.solo --registry="$registry" "$stoneName" -b
gslist.solo -l || true

# ---------------------------------------------------------
# Load baseline projects into the stone
# ---------------------------------------------------------
cd "${stonesDir}/${stoneName}"

# Jadeite requirement: turn on unicodeComparisonMode
enableUnicodeCompares.topaz -lq


#
# ---------------------------------------------------------
# This is the seaside stone load script.
# ---------------------------------------------------------
#

# We need to update a bunch of stuff so that GT works. 
# At this stage we should have the GT scripts in a known location

gtScriptsDir="${gitDir_devtools}/gt4gemstone/scripts"
PATH="${stonesDir}/${stoneName}/product/bin:$PATH"
export STONE=${stoneName}

# ensure scripts are executable
pushd ${gtScriptsDir}
#chmod 755 ./*.sh
#chmod 755 ./seaside/*.sh
#chmod 755 ./release/*.sh
popd

# Update permissions to allow GT and Seaside to coexist
information_banner "Expand permissions. using ${gtScriptsDir}/loginSystemUser.topaz"
topaz -l -I ${gtScriptsDir}/loginSystemUser.topaz  -S ${gtScriptsDir}/seaside/seaside-permissions.topaz < /dev/zero

# Install Seaside
information_banner "Install seaside. using ${gtScriptsDir}/loginDataCurator.topaz"
topaz -l -I ${gtScriptsDir}/loginDataCurator.topaz  -S ${gtScriptsDir}/seaside/installSeaside.topaz < /dev/zero




#
# ---------------------------------------------------------
# Hack together a GT devkit
# ---------------------------------------------------------
#

export GEMSTONE_WORKSPACE=${gitDir_devtools}/devkit_workspace
export RELEASED_PACKAGE_GEMSTONE_NAME="gt4gemstone-3.7"
gtGsPackageDirectory=${GEMSTONE_WORKSPACE}/${RELEASED_PACKAGE_GEMSTONE_NAME}
export GT4GEMSTONE_VERSION=dev
rm -Rf ${GEMSTONE_WORKSPACE}
mkdir -p ${GEMSTONE_WORKSPACE}

# Package the release
information_banner "Package GlamorousToolkitGlobals hacky install."
touch dummy.image
ROWAN_PROJECTS_HOME=${gitDir_devtools} "${gtScriptsDir}/release/package-release.sh"
"${gtGsPackageDirectory}/seaside/patch-dictionaries.sh"
rm dummy.image

# Install GT Symbol Dict
information_banner "Add GlamorousToolkitGlobals symbol dictionary."
topaz -l -I "${gtGsPackageDirectory}/loginDataCurator.topaz"  -S "${gtGsPackageDirectory}/seaside/gt-symbol-dictionary.topaz" < /dev/zero

# Install GT
information_banner "Install GT"
"${gtGsPackageDirectory}/seaside/inputRelease.sh" -s "${STONE}"

# Patch seaside code for GT compatibility
echo "Apply Gt/Seaside patches"
topaz -l -I "${gtGsPackageDirectory}/loginDataCurator.topaz" -S "${gtGsPackageDirectory}/seaside/seaside-gt-patches.topaz" < /dev/zero



# Restore working directory
cd "${workingDirectory}"

exit_0_banner "Stone '${stoneName}' created"
