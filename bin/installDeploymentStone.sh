#!/usr/bin/env bash
set -euo pipefail

PROGNAME=$0
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)

# shellcheck disable=SC1091
. "${SCRIPT_DIR}/private/shFunctions"

# Load layered config (ENV > project config > bundled toolkit config > safety net)
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
stonesDir="$(abs_from_cwd "${GSDEVKIT_STONES_DIR}")"
installState="${stonesDir}/.${stoneName}.bvc-installing"
phase=rowan:creating
save_phase() {
  phase="$1"
  printf '%s\n' "$phase" > "${installState}.tmp"
  mv "${installState}.tmp" "$installState"
}

# New projects root model
projectsRoot="$(abs_from_cwd "${PROJECTS_ROOT}")"
gitDir_projects="${projectsRoot}/projects"
gitDir_devtools="${projectsRoot}/dev_tools"

# Ensure root exists (per-set dirs will be ensured by setupProjects)
[ -d "${projectsRoot}" ] || mkdir -p "${projectsRoot}"

# ---------------------------------------------------------
# Completed stones are unchanged. Incomplete Rowan installs resume without
# recreating extents or reloading steps already recorded as successful.
# ---------------------------------------------------------
if registryReport.solo --registry="$registry" --stone="$stoneName" >/dev/null 2>&1; then
  [ -f "$installState" ] || exit_0_banner "Stone '${stoneName}' unchanged"
  stoneSpec="${stonesDir}/${stoneName}/.GDKStoneSpec.ston"
  if ! grep -Eq "#stoneDirectorySpecName[[:space:]]*:[[:space:]]*'default_rowan3'" "$stoneSpec"; then
    exit_1_banner "Cannot resume '${stoneName}' with the Rowan installer: its local stone specification is missing or uses another template. Data has been preserved."
  fi
  phase=$(cat "$installState")
  # Before step tracking was introduced the marker was empty. Existing Rowan
  # stones from that version resume configuration and package loading.
  case "$phase" in
    '') phase=rowan:created ;;
    rowan:created|rowan:configured|rowan:devtools|rowan:projects) ;;
    *) exit_1_banner "Installation state '${phase}' requires inspection before resuming '${stoneName}'. Data has been preserved." ;;
  esac
  [ -f "${stonesDir}/${stoneName}/system.conf" ] || \
    exit_1_banner "Stone '${stoneName}' has incomplete files; refusing to recreate it automatically"
  information_banner "Resuming '${stoneName}' after ${phase#rowan:}"
else
  if [ -e "${stonesDir}/${stoneName}" ]; then
    exit_1_banner "Unregistered stone directory already exists: ${stonesDir}/${stoneName}. Refusing to overwrite it."
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
  save_phase rowan:creating
  createStone.solo --registry="$registry" --template=default_rowan3 "$stoneName" "$gemStoneVersion"
  save_phase rowan:created
fi

# The deployment is registered immediately after createStone.solo. Refresh the
# DevKit connectors now, before later install tooling mutates the shell
# environment (STONE, GEMSTONE_WORKSPACE, PATH, working directory, etc.).
bvc_refresh_gt4gemstone_properties "${registry}"

# Configure once; a retry never appends duplicate configuration lines.
if [ "$phase" = rowan:created ]; then
  # macOS: disable native code (JIT) for this stone
  case "${OSTYPE:-}" in
    darwin*)
      warning_banner "Disabling Native Code for stone '${stoneName}' (macOS)"
      if ! grep -q '^GEM_NATIVE_CODE_ENABLED=0;' "${stonesDir}/${stoneName}/gem.conf"; then
        printf '%s\n' "GEM_NATIVE_CODE_ENABLED=0;" >> "${stonesDir}/${stoneName}/gem.conf"
      fi
      ;;
  esac

  # ---------------------------------------------------------
  # Environment for tooling (ROWAN) — MUST point to projects set
  # ---------------------------------------------------------
  information_banner "Setting ROWAN_PROJECTS_HOME=${gitDir_projects}"
  export ROWAN_PROJECTS_HOME="${gitDir_projects}"
  updateCustomEnv.solo --registry="$registry" "$stoneName" \
    --addKey=ROWAN_PROJECTS_HOME --value="$ROWAN_PROJECTS_HOME" --restart
  save_phase rowan:configured
fi
# Package loaders need this even when configuration was completed previously.
export ROWAN_PROJECTS_HOME="${gitDir_projects}"

# ---------------------------------------------------------
# Start the stone & show status
# ---------------------------------------------------------
information_banner "Starting stone '${stoneName}'"
bvc_start_stone "$registry" "$stoneName"
gslist.solo -l || true

# ---------------------------------------------------------
# Load baseline projects into the stone
# ---------------------------------------------------------
cd "${stonesDir}/${stoneName}"

if [ "$phase" = rowan:configured ]; then
  # Jadeite requirement: turn on unicodeComparisonMode
  enableUnicodeCompares.topaz -lq
  information_banner "Installing dev tools projects from ${gitDir_devtools}"
  install_devtools_projects "${gitDir_devtools}"
  save_phase rowan:devtools
fi

# Install User Projects (from projects set dir)
if [ "$phase" = rowan:devtools ]; then
  information_banner "Installing user projects from ${gitDir_projects}"
  install_projects "${gitDir_projects}"
  save_phase rowan:projects
fi

# Restore working directory
cd "${workingDirectory}"
rm -f "$installState"

exit_0_banner "Stone '${stoneName}' created"
