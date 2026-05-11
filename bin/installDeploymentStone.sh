#!/usr/bin/env bash
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
information_banner "Install deployment stone"

usage() {
  cat 1>&2 <<EOF
Usage:
  $(prog_basename "$PROGNAME") [deploymentName [gemstoneVersion]]

Where:
  deploymentName       Name of the deployment stone (default: ${GEMSTONE_STONE_NAME})
  gemstoneVersion      GemStone version (default: ${GEMSTONE_VERSION})

Registry is internal and comes from DEFAULT_REGISTRY in config.
EOF
  exit 1
}

# ---------------------------------------------------------
# Args
# 0 args -> defaults
# 1 arg  -> <deploymentName>
# 2 args -> <deploymentName> <gemstoneVersion>
# ---------------------------------------------------------
registry="${DEFAULT_REGISTRY}"
gemStoneVersion="${GEMSTONE_VERSION}"
stoneName="${GEMSTONE_STONE_NAME}"

pos1=""
pos2=""

while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h) usage ;;
    --*)      error_banner "Unknown option: $1"; usage ;;
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
  exit_1_banner "GsDevKit is required before installing a deployment."
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
"${SCRIPT_DIR}/bvcPullProjects.sh"

# ---------------------------------------------------------
# Stones directory (where local stones live)
# ---------------------------------------------------------
information_banner "Ensuring stones directory: ${stonesDir}"
[ -d "${stonesDir}" ] || mkdir -p "${stonesDir}"

information_banner "Registering stones directory: ${stonesDir}"
registerStonesDirectory.solo --registry="$registry" --stonesDirectory="${stonesDir}"

# ---------------------------------------------------------
# Create the stone (template: default_rowan3)
# ---------------------------------------------------------
information_banner "Creating stone '${stoneName}' (template: default_rowan3)"
createStone.solo --registry="$registry" --template=default_rowan3 "$stoneName" "$gemStoneVersion"

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

# Install Dev Tools (from dev_tools set dir)
information_banner "Installing dev tools projects from ${gitDir_devtools}"
install_devtools_projects "${gitDir_devtools}"

# Install User Projects (from projects set dir)
information_banner "Installing user projects from ${gitDir_projects}"
install_projects "${gitDir_projects}"

# Restore working directory
cd "${workingDirectory}"

exit_0_banner "Stone '${stoneName}' created"
