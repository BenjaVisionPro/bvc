#! /usr/bin/env sh
set -eu

PROGNAME=$0
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)

# shellcheck disable=SC1091
. "${SCRIPT_DIR}/private/shFunctions"

# Layered config (ENV > CWD/*.bvc > $BVC_CONF_DIR/bvc/bvc_defaults > bundled > safety net)
load_bvc_config

setup_traps
start_banner "$@"
information_banner "Setup Project Sets"

usage() {
  cat 1>&2 <<EOF
Usage:
  $(prog_basename "$PROGNAME") [--registry=NAME]

Behavior (deterministic order):
  1) dev_tools.ston (if present)
  2) projects.ston  (if present; this one is REGISTERED)
  3) All other *.ston files (alphabetical)

For each set <name>:
  - createProjectSet.solo --projectSet=<name> --from=<file>
  - ensure dir: \${PROJECTS_ROOT}/<name>
  - cloneProjectsFromProjectSet.solo into that dir
  - **registerProjectDirectory.solo only for 'projects'**

Defaults:
  registry:      ${DEFAULT_REGISTRY}
  projects root: $(abs_from_cwd "${PROJECTS_ROOT}")

Examples:
  $(prog_basename "$PROGNAME")
  $(prog_basename "$PROGNAME") --registry=myReg
EOF
  exit 1
}

# ---------------------------------------------------------
# Args (optional: --registry=NAME)
# ---------------------------------------------------------
registry="${DEFAULT_REGISTRY}"
while [ $# -gt 0 ]; do
  case "$1" in
    --registry=*) registry=${1#*=} ;;
    --help|-h)    usage ;;
    --*)          error_banner "Unknown option: $1"; usage ;;
    *)            error_banner "Unexpected positional: $1"; usage ;;
  esac
  shift
done

# ---------------------------------------------------------
# Sanity checks
# ---------------------------------------------------------
if [ -z "${STONES_HOME:-}" ] || [ ! -d "${STONES_HOME:-/nonexistent}" ]; then
  error_banner "STONES_HOME is not set or does not exist."
  exit_1_banner "Run 'bvc init' to set up GSDevKit before setting up project sets."
fi

# Resolve the active projectSets directory:
#   Prefer CONF_DIR override; otherwise bundled ../conf.
if [ -d "${CONF_DIR}/projectSets" ]; then
  projectSetsDir="${CONF_DIR}/projectSets"
elif [ -d "${SCRIPT_DIR}/../conf/projectSets" ]; then
  projectSetsDir="${SCRIPT_DIR}/../conf/projectSets"
else
  error_banner "No projectSets directory found."
  exit_1_banner "Expected at: \${CONF_DIR}/projectSets or bundled ../conf/projectSets"
fi

projectsRoot="$(abs_from_cwd "${PROJECTS_ROOT}")"
[ -d "${projectsRoot}" ] || mkdir -p "${projectsRoot}"

information_banner "Registry:      ${registry}"
information_banner "Sets dir:      ${projectSetsDir}"
information_banner "Projects root: ${projectsRoot}"

# ---------------------------------------------------------
# Helper to process a single set by name (if its .ston exists)
# ---------------------------------------------------------
process_set() {
  _name="$1"
  _ston="${projectSetsDir}/${_name}.ston"

  [ -f "${_ston}" ] || return 1

  targetDir="${projectsRoot}/${_name}"

  information_banner "Processing project set '${_name}' from '${_ston}'"

  information_banner "Creating project set '${_name}'"
  createProjectSet.solo --registry="${registry}" --projectSet="${_name}" --from="${_ston}"

  information_banner "Ensuring directory: ${targetDir}"
  [ -d "${targetDir}" ] || mkdir -p "${targetDir}"

  # Register only for 'projects'
  if [ "${_name}" = "projects" ]; then
    information_banner "Registering project directory for 'projects': ${targetDir}"
    registerProjectDirectory.solo --registry="${registry}" --projectDirectory="${targetDir}"
  fi

  information_banner "Cloning projects for set '${_name}' into ${targetDir}"
  cloneProjectsFromProjectSet.solo --registry="${registry}" --projectSet="${_name}" \
    --projectDirectory="${targetDir}"

  return 0
}

# ---------------------------------------------------------
# Deterministic ordering:
#   1) dev_tools
#   2) projects
#   3) others (alphabetical, excluding the two above)
# ---------------------------------------------------------
set_found=0

# 1) dev_tools first (if present)
if process_set "dev_tools"; then
  set_found=1
fi

# 2) projects second (if present)
if process_set "projects"; then
  set_found=1
fi

# 3) All other *.ston (alphabetical), excluding dev_tools/projects
set +f
for ston in "${projectSetsDir}"/*.ston; do
  [ -f "${ston}" ] || continue
  base="${ston##*/}"          # e.g., foo.ston
  name="${base%.ston}"        # e.g., foo
  case "$name" in
    dev_tools|projects) continue ;;
  esac
  if process_set "${name}"; then
    set_found=1
  fi
done
set -f

if [ "${set_found}" -eq 0 ]; then
  error_banner "No *.ston files found in ${projectSetsDir}"
  exit_1_banner "Add one or more project set files (e.g., dev_tools.ston, projects.ston)"
fi

exit_0_banner "Project sets setup complete"