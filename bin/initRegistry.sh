#! /usr/bin/env sh
set -eu

PROGNAME=$0
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)

# shellcheck disable=SC1091
. "${SCRIPT_DIR}/private/shFunctions"

# Load layered config (ENV > CWD/*.bvc > $BVC_CONF_DIR/bvc/bvc_defaults > bundled > safety net)
load_bvc_config

setup_traps
start_banner "$@"
information_banner "BenjaVision Catalyst Toolkit — Initialize Registry"

# ----------------------------------------
# Helpers
# ----------------------------------------
registry_exists() {
  name="$1"
  registryReport.solo --registry="$name" >/dev/null 2>&1
}

# ----------------------------------------
# Args
#   Accept either:
#     - no args  → use ${DEFAULT_REGISTRY}
#     - --registry=NAME
#     - single positional NAME
# ----------------------------------------
registry="${DEFAULT_REGISTRY}"
pos_seen=0
while [ $# -gt 0 ]; do
  case "$1" in
    --registry=*) registry=${1#*=} ;;
    --*)          error_banner "Unknown option: $1"; exit 1 ;;
    *)
      if [ $pos_seen -eq 0 ]; then
        registry="$1"; pos_seen=1
      else
        error_banner "Too many arguments. Usage: $(prog_basename "$PROGNAME") [--registry=NAME|NAME]"
        exit 1
      fi
      ;;
  esac
  shift
done

# ----------------------------------------
# Preconditions (caller usually ensures this, but be defensive)
# ----------------------------------------
if [ -z "${STONES_HOME:-}" ] || [ ! -d "${STONES_HOME:-/nonexistent}" ]; then
  error_banner "STONES_HOME is not set or does not exist."
  exit_1_banner "Run 'bvc init' (or setupGsDevKit_stones.sh) before initializing a registry."
fi

# ----------------------------------------
# Create-once semantics
# - If registry exists: leave it unchanged (do NOT re-register product dir)
# - If not: create it and register the shared product directory
# ----------------------------------------
if registry_exists "$registry"; then
  information_banner "GsDevKit registry '${registry}' already exists — leaving unchanged."
  exit_0_banner "Registry '${registry}' present"
fi

information_banner "Creating registry '${registry}'"
createRegistry.solo "$registry" --ensure

information_banner "Registering shared product directory: ${STONES_HOME}/gemstone"
registerProductDirectory.solo \
  --registry="$registry" \
  --productDirectory="${STONES_HOME}/gemstone"

exit_0_banner "Registry '${registry}' initialized"