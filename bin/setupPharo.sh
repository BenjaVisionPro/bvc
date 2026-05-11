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
information_banner "Installing Pharo"

# ---------------------------------------------------------
# Defaults (overridable via config/env/flags)
# ---------------------------------------------------------
INSTALL_DIR="$(abs_from_cwd "${PHARO_INSTALL_DIR}")"   # default from config: Pharo
PHARO_VER="${PHARO_VERSION}"                           # default from config: 130

print_help() {
  cat 1>&2 <<EOF
Usage: $(prog_basename "$0") [OPTIONS]

Options:
  --install-dir=PATH   Install directory (default: ${PHARO_INSTALL_DIR})
  --version=NUM        Pharo major version (e.g., 120 for 12.0; 130 for 13.0). Default: ${PHARO_VERSION}
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
# Requirements / Platform
# ---------------------------------------------------------
need curl
need bash   # the get.pharo.org scripts are bash installers

set_platform_and_architecture
: "${platform:?platform not set}"
# Native Windows (cmd.exe) is not supported; WSL/Linux/macOS are fine.
if [ "$platform" = "Win" ]; then
  exit_1_banner "Native Windows POSIX shell not supported. Run from WSL/macOS/Linux."
fi

# ---------------------------------------------------------
# Idempotence: skip if already installed
# A typical successful install leaves ./pharo-ui present.
# ---------------------------------------------------------
if [ -x "${INSTALL_DIR}/pharo-ui" ] || [ -f "${INSTALL_DIR}/pharo-ui" ]; then
  information_banner "Pharo already present in ${INSTALL_DIR} — skipping."
  exit_0_banner "Pharo unchanged"
fi

# ---------------------------------------------------------
# Install (Image + VM) using official get.pharo.org
# ---------------------------------------------------------
mkdir -p "${INSTALL_DIR}"
cd "${INSTALL_DIR}"

IMAGE_URL="https://get.pharo.org/${PHARO_VER}"
VM_URL="https://get.pharo.org/vm${PHARO_VER}"

spinner_start "Downloading Pharo image (${PHARO_VER})"
( curl -fsSL "${IMAGE_URL}" | bash ) >/dev/null 2>&1
spinner_stop

spinner_start "Downloading Pharo VM (${PHARO_VER})"
( curl -fsSL "${VM_URL}" | bash ) >/dev/null 2>&1
spinner_stop

# ---------------------------------------------------------
# Done
# ---------------------------------------------------------
information_banner "Pharo installed at: ${INSTALL_DIR}"
[ -x "./pharo-ui" ] && information_banner "Launcher: ${INSTALL_DIR}/pharo-ui"
exit_0_banner "Pharo setup complete"