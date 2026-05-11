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
information_banner "Bootstrapping GsDevKit_stones"

usage() {
  cat << EOF 1>&2
Usage: $(prog_basename "$PROGNAME") [-v]... [-p <parent_dir>] [-n <devKit_root_directory_name>]

Options:
  -p, --parent-dir DIR     Parent directory for install (default: /opt)
  -n, --name NAME          DevKit root directory name under parent (default: GsDevKit)
  -v                       Increase verbosity (can be repeated)
  -h, --help               Show this help

Notes:
- If STONES_HOME is not set, this script prints the exact lines to add to your shell profile,
  then exits. Re-run after setting STONES_HOME.
EOF
  exit 1
}

#===============================================
# Verbose feedback
#===============================================
info() {
  msg="$1"; lvl="$2"
  : "${verbose_level:=0}"
  if [ "${verbose_level}" -ge "${lvl}" ]; then
    information_banner "$msg"
  fi
}

#===============================================
# Create directory if it doesn't exist
#===============================================
conditionallyCreateDirectory() {
  dir="$1"
  if [ -d "$dir" ]; then
    info "$dir already exists. Delete it to recreate, then rerun." 1
  else
    info "Creating $dir" 1
    mkdir -p "$dir"
  fi
}

#===============================================
# Platform check (no Windows)
#===============================================
platform="$(uname -s 2>/dev/null || echo unknown)"
case "$platform" in
  MINGW*|MSYS*|CYGWIN*)
    exit_1_banner "This script is server-only and cannot be used on Windows."
    ;;
esac

#===============================================
# Defaults + flags
#===============================================
parentDirectory="/opt"
installDirectoryName="GsDevKit"
verbose_level=0

# Simple flag parser (POSIX)
while [ $# -gt 0 ]; do
  case "$1" in
    -p|--parent-dir)
      shift; [ $# -gt 0 ] || usage
      parentDirectory="$1"
      ;;
    -n|--name)
      shift; [ $# -gt 0 ] || usage
      installDirectoryName="$1"
      ;;
    -v)
      verbose_level=$((verbose_level + 1))
      ;;
    -h|--help)
      usage
      ;;
    *)
      error_banner "Unknown option: $1"
      usage
      ;;
  esac
  shift
done

#===============================================
# Derived paths
#===============================================
workingDirectory="$(pwd)"
installPath="${parentDirectory}/${installDirectoryName}"
stonesGitRoot="${installPath}/git"
stonesGitInstall="${stonesGitRoot}/GsDevKit_stones"
stonesHome="${installPath}"
stonesDataHome="${installPath}/data"
superDoitRoot="${stonesGitRoot}/superDoit"

info "parentDirectory=${parentDirectory}" 2
info "installDirectoryName=${installDirectoryName}" 2
info "installPath=${installPath}" 2
info "stonesGitRoot=${stonesGitRoot}" 2
info "stonesGitInstall=${stonesGitInstall}" 2
info "stonesHome=${stonesHome}" 2
info "stonesDataHome=${stonesDataHome}" 2
info "superDoitRoot=${superDoitRoot}" 2

#===============================================
# Requirements
#===============================================
need git
need ssh
need curl

#===============================================
# Ensure STONES_HOME is set by the user
#===============================================
if [ -z "${STONES_HOME:-}" ]; then
  information_banner "Add the following to your shell profile (then open a new terminal):"
  cat <<EOF 1>&2
# GsDevKit_stones
export STONES_HOME=${stonesHome}
export STONES_DATA_HOME=\$STONES_HOME/data
export PATH=\$STONES_HOME/git/superDoit/bin:\$STONES_HOME/git/GsDevKit_stones/bin:\$PATH
EOF
  exit_1_banner "STONES_HOME must be defined in your environment. See instructions above."
fi

#===============================================
# Verify GitHub SSH works (helps avoid mid-script failure)
#===============================================
information_banner "Testing ssh connection to github.com"
if ssh -T git@github.com 2>&1 | grep -qi "success"; then
  information_banner "GitHub SSH OK"
else
  exit_1_banner "Set up your GitHub SSH credentials before re-running this script."
fi

#===============================================
# Sudo warm-up (only if needed)
#===============================================
if [ ! -d "${parentDirectory}" ] || [ ! -w "${parentDirectory}" ]; then
  information_banner "Elevating privileges to prepare ${parentDirectory} (you may be prompted)"
  sudo -v || exit_1_banner "sudo is required to create ${parentDirectory}"
fi

#===============================================
# Prepare directories
#===============================================
if [ ! -d "${parentDirectory}" ]; then
  info "Creating ${parentDirectory}" 1
  sudo mkdir -p "${parentDirectory}"
fi

# Ensure ownership for current user (so we can write under parentDirectory)
current_user="${USER:-$(id -un 2>/dev/null || echo unknown)}"
info "Setting owner of ${parentDirectory} to ${current_user}" 2
sudo chown "${current_user}" "${parentDirectory}" || :
chmod u+rwx "${parentDirectory}" || :

# GemStone shared dir under /opt/gemstone (if missing)
if [ ! -d "/opt/gemstone" ]; then
  info "Creating GemStone directories in /opt/gemstone" 1
  sudo mkdir -p /opt/gemstone/locks
  sudo chmod -R a+rwx /opt/gemstone
else
  info "/opt/gemstone already exists. Delete to recreate, then rerun." 1
fi

# Install root and subdirs
conditionallyCreateDirectory "${installPath}"
conditionallyCreateDirectory "${stonesDataHome}"
conditionallyCreateDirectory "${installPath}/gemstone"
conditionallyCreateDirectory "${stonesGitRoot}"

#===============================================
# Clone GsDevKit_stones (idempotent)
#===============================================
if [ -d "${stonesGitInstall}/.git" ]; then
  information_banner "GsDevKit_stones already cloned at ${stonesGitInstall} — skipping clone."
else
  information_banner "Cloning GsDevKit_stones → ${stonesGitInstall}"
  ( cd "${stonesGitRoot}" && git clone git@github.com:GsDevKit/GsDevKit_stones.git )
fi

#===============================================
# Install GsDevKit_stones + superDoit (idempotent)
#===============================================
if [ -x "${stonesGitInstall}/bin/install.sh" ]; then
  information_banner "Installing GsDevKit_stones and superDoit"
  ( cd "${stonesGitInstall}/bin" && ./install.sh )
else
  exit_1_banner "install.sh not found in ${stonesGitInstall}/bin"
fi

#===============================================
# Configure shared memory (best-effort)
#===============================================
if [ -x "${superDoitRoot}/dev/setSharedMemory.sh" ]; then
  info "Configuring shared memory" 1
  "${superDoitRoot}/dev/setSharedMemory.sh" || warning_banner "Shared memory configuration returned non-zero status."
else
  warning_banner "superDoit shared memory script not found at ${superDoitRoot}/dev/setSharedMemory.sh"
fi

#===============================================
# Finish
#===============================================
cd "${workingDirectory}"
exit_0_banner "GsDevKit bootstrap finished"