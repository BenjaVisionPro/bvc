#! /usr/bin/env sh
set -eu

PROGNAME=$0
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)

# shellcheck disable=SC1091
. "${SCRIPT_DIR}/private/shFunctions"

# Layered config: ENV > CWD/*.bvc > $BVC_CONF_DIR/bvc/bvc_defaults > bundled > safety net
load_bvc_config

setup_traps
start_banner "$@"
information_banner "Installing Jadeite 4 Pharo"

# ---------------------------------------------------------
# Defaults (overridable via config/env/flags)
# ---------------------------------------------------------
INSTALL_DIR="$(abs_from_cwd "${J4P_INSTALL_DIR}")"   # e.g. Jadeite4Pharo
PHARO_VER="${J4P_PHARO_VERSION}"                     # e.g. 120 (Pharo 12.0)

print_help() {
  cat 1>&2 <<EOF
Usage: $(prog_basename "$0") [OPTIONS]

Options:
  --install-dir=PATH   Install directory (default: ${J4P_INSTALL_DIR})
  --version=NUM        Pharo major version (e.g., 120 for 12.0). Default: ${J4P_PHARO_VERSION}
  --help               Show this help
EOF
}

# ---------------------------------------------------------
# Parse flags
# ---------------------------------------------------------
for arg in "$@"; do
  case "$arg" in
    --install-dir=*) INSTALL_DIR="$(abs_from_cwd "${arg#*=}")" ;;
    --version=*)     PHARO_VER="${arg#*=}" ;;
    --help)          print_help; exit 0 ;;
    *)               error_banner "Unknown option: $arg"; print_help; exit 1 ;;
  esac
done
# strip trailing slash except root
case "$INSTALL_DIR" in /) : ;; *) INSTALL_DIR=${INSTALL_DIR%/} ;; esac

information_banner "Install dir:   ${INSTALL_DIR}"
information_banner "Pharo version: ${PHARO_VER}"

# ---------------------------------------------------------
# Idempotence: skip if already installed
# ---------------------------------------------------------
if [ -x "${INSTALL_DIR}/pharo-ui" ] || [ -f "${INSTALL_DIR}/pharo-ui" ]; then
  information_banner "Jadeite4Pharo already present at ${INSTALL_DIR} — skipping."
  exit_0_banner "J4P unchanged"
fi

# ---------------------------------------------------------
# Perform setup (delegates to setupPharo.sh)
# ---------------------------------------------------------
information_banner "Setting up Pharo ${PHARO_VER} in ${INSTALL_DIR}"
"${SCRIPT_DIR}/setupPharo.sh" \
  --install-dir="${INSTALL_DIR}" \
  --version="${PHARO_VER}"

# ---------------------------------------------------------
# Copy Jadeite startup.st (from projects root)
# ---------------------------------------------------------
git_dir="$(abs_from_cwd "${PROJECTS_ROOT}/dev_tools")"
startup_src="${git_dir}/JadeiteForPharo/startup.st"
if [ -f "${startup_src}" ]; then
  cp "${startup_src}" "${INSTALL_DIR}/"
  information_banner "Copied startup.st from ${startup_src}"
else
  warning_banner "startup.st not found at ${startup_src} — skipping copy"
fi

exit_0_banner "Jadeite4Pharo setup complete"