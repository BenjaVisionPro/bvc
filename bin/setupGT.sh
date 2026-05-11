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
information_banner "Initialising Glamorous Toolkit"

# ---------------------------------------------------------
# Defaults (overridable via config/env)
# ---------------------------------------------------------
INSTALL_DIR="$(abs_from_cwd "${GT_INSTALL_DIR}")"
APP_NAME="${GT_APP_NAME}"
# If not overridden by flag, individual scripts will be resolved via conf_resolve()
LOAD_SCRIPTS_DIR=""
# Resolve/normalize projects root now so we can pass it to GT when loading projects
PROJECTS_ROOT_ABS="$(abs_from_cwd "${PROJECTS_ROOT}")"

# ---------------------------------------------------------
# Helpers
# ---------------------------------------------------------
print_help() {
	cat 1>&2 <<EOF
Usage: $(prog_basename "$0") [OPTIONS]

Options:
  --install-dir=PATH      Install directory (default: ${GT_INSTALL_DIR})
  --app-name=NAME         Application name (default: ${GT_APP_NAME})
  --load-scripts-dir=DIR  Startup scripts dir (overrides per-file conf_resolve)
  --help                  Show this help
EOF
}

# ---------------------------------------------------------
# Parse flags
# ---------------------------------------------------------
for arg in "$@"; do
	case "$arg" in
		--install-dir=*)      INSTALL_DIR=$(abs_from_cwd "${arg#*=}") ;;
		--app-name=*)         APP_NAME=${arg#*=} ;;
		--load-scripts-dir=*) LOAD_SCRIPTS_DIR=${arg#*=} ;;
		--help)               print_help; exit 0 ;;
		*)                    error_banner "Unknown option: $arg"; print_help; exit 1 ;;
	esac
done

# ---------------------------------------------------------
# Idempotence: skip if already installed
# ---------------------------------------------------------
if [ -e "${INSTALL_DIR}/${APP_NAME}.image" ]; then
	information_banner "GT already installed at ${INSTALL_DIR} — skipping."
	exit_0_banner "GT unchanged"
fi

information_banner "Install dir:     ${INSTALL_DIR}"
information_banner "App name:        ${APP_NAME}"
if [ -n "${LOAD_SCRIPTS_DIR}" ]; then
  information_banner "Load scripts:    ${LOAD_SCRIPTS_DIR} (override)"
else
  information_banner "Load scripts:    resolved via conf_resolve (CONF_DIR → bundled)"
fi
information_banner "Projects root:   ${PROJECTS_ROOT_ABS}"

# ---------------------------------------------------------
# Requirements
# ---------------------------------------------------------
need curl
need unzip

# ---------------------------------------------------------
# Platform + architecture
# ---------------------------------------------------------
set_platform_and_architecture
: "${platform:?platform not set by set_platform_and_architecture}"
: "${architecture:?architecture not set by set_platform_and_architecture}"

# ---------------------------------------------------------
# Resolve GT artifact
# ---------------------------------------------------------
information_banner "Detecting GT build for: ${architecture}"
downloadFile="$(curl -fsSL "https://dl.feenk.com/gt/GlamorousToolkit${architecture}-release")"
[ -n "${downloadFile:-}" ] || exit_1_banner "Could not resolve GT download file for ${architecture}"
downloadLink="https://dl.feenk.com/gt/${downloadFile}"

# ---------------------------------------------------------
# Prepare install location
# ---------------------------------------------------------
information_banner "Creating install location: ${INSTALL_DIR}"
mkdir -p "${INSTALL_DIR}"

# ---------------------------------------------------------
# Download & unzip
# ---------------------------------------------------------
information_banner "Downloading GT from: ${downloadLink}"
curl -fSLo "${downloadFile}" "${downloadLink}"
unzip -qq -d "${INSTALL_DIR}" "${downloadFile}"
rm -f "${downloadFile}"

# ---------------------------------------------------------
# Determine CLI/executable layout
# ---------------------------------------------------------
case "${platform}" in
	Mac)
		cli_rel="GlamorousToolkit.app/Contents/MacOS/GlamorousToolkit-cli"
		exe_rel="GlamorousToolkit.app"
		app_rel="${APP_NAME}.app"
		;;
	Linux)
		cli_rel="bin/GlamorousToolkit-cli"
		exe_rel="bin/GlamorousToolkit"
		app_rel="bin/${APP_NAME}"
		;;
	Win)
		cli_rel="bin/GlamorousToolkit-cli"
		exe_rel="bin/GlamorousToolkit.exe"
		app_rel="bin/${APP_NAME}.exe"
		;;
	*)
		exit_1_banner "Unsupported platform: ${platform}"
		;;
esac

cli_path="${INSTALL_DIR}/${cli_rel}"
exe_path="${INSTALL_DIR}/${exe_rel}"
app_path="${INSTALL_DIR}/${app_rel}"

[ -x "${cli_path}" ] || exit_1_banner "GT CLI not found/executable at: ${cli_path}"

# ---------------------------------------------------------
# Hook scripts
# If --load-scripts-dir is provided, use it directly.
# Otherwise resolve each script via conf_resolve (CONF_DIR first, then bundled).
# ---------------------------------------------------------
if [ -n "${LOAD_SCRIPTS_DIR}" ]; then
  preLoad_st="${LOAD_SCRIPTS_DIR%/}/preLoad.st"
  loadProjects_st="${LOAD_SCRIPTS_DIR%/}/loadProjects.st"
  postLoad_st="${LOAD_SCRIPTS_DIR%/}/postLoad.st"
else
  preLoad_st="$(conf_resolve 'gt/startup_scripts/preLoad.st')"
  loadProjects_st="$(conf_resolve 'gt/startup_scripts/loadProjects.st')"
  postLoad_st="$(conf_resolve 'gt/startup_scripts/postLoad.st')"
fi

[ -f "${preLoad_st}" ]      || exit_1_banner "Missing preLoad.st (checked override and bundled locations)"
[ -f "${loadProjects_st}" ] || exit_1_banner "Missing loadProjects.st (checked override and bundled locations)"
[ -f "${postLoad_st}" ]     || exit_1_banner "Missing postLoad.st (checked override and bundled locations)"

# ---------------------------------------------------------
# Execute loads
# ---------------------------------------------------------
spinner_start "Running preLoad.st"
"${cli_path}" "${INSTALL_DIR}/GlamorousToolkit.image" st "${preLoad_st}" --interactive --save --quit
spinner_stop

# Remove base image; keep the branded image
rm -f "${INSTALL_DIR}/GlamorousToolkit.image" "${INSTALL_DIR}/GlamorousToolkit.changes" 2>/dev/null || :

spinner_start "Running loadProjects.st"
# IMPORTANT: pass the projects root to the GT process for this step only
PROJECTS_ROOT="${PROJECTS_ROOT_ABS}/projects" \
"${cli_path}" "${INSTALL_DIR}/${APP_NAME}.image" st "${loadProjects_st}" --save --quit
spinner_stop

spinner_start "Running postLoad.st"
"${cli_path}" "${INSTALL_DIR}/${APP_NAME}.image" st "${postLoad_st}" --interactive --save --quit
spinner_stop

# ---------------------------------------------------------
# Brand executable/bundle to app name
# ---------------------------------------------------------
mv -f "${exe_path}" "${app_path}"

# ---------------------------------------------------------
# Done
# ---------------------------------------------------------
information_banner "GT installed:     ${INSTALL_DIR}"
information_banner "Executable:       ${app_path}"
information_banner "Image:            ${APP_NAME}.image"
exit_0_banner "Setup complete"