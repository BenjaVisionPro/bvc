#!/usr/bin/env bash
set -euo pipefail

PROGNAME=$0
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)

# shellcheck disable=SC1091
. "${SCRIPT_DIR}/private/shFunctions"

# Load layered config (ENV > project config > bundled toolkit config > safety net)
load_bvc_config

setup_traps
start_banner "$@"
information_banner "Build Catalyst DevKit"

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

# Use the effective flag values consistently in image naming and connectors.
GT_INSTALL_DIR=${INSTALL_DIR%/}
GT_APP_NAME=$APP_NAME
bvc_lock "${GT_INSTALL_DIR}.build-lock"

# ---------------------------------------------------------
# Idempotence: skip if already installed
# ---------------------------------------------------------
if gt_installed; then
	information_banner "GT already installed at ${INSTALL_DIR} — skipping build."
	bvc_refresh_gt4gemstone_properties "${DEFAULT_REGISTRY}"
	exit_0_banner "GT unchanged"
fi

# Build privately and publish only after every load succeeds. An interrupted
# build can then be retried without an intermediate image looking installed.
if [ -e "$GT_INSTALL_DIR" ]; then
  exit_1_banner "Incomplete DevKit at ${GT_INSTALL_DIR}. Move it aside to preserve any live work, then rerun."
fi
BUILD_DIR=$(mktemp -d "${GT_INSTALL_DIR}.build.XXXXXX")
INSTALL_DIR=$BUILD_DIR
trap 'spinner_stop; [ -z "${BUILD_DIR:-}" ] || rm -rf -- "$BUILD_DIR"; rm -f "${bvc_lock_dir}/pid"; rmdir "$bvc_lock_dir"' EXIT

information_banner "Install dir:     ${INSTALL_DIR}"
information_banner "App name:        ${APP_NAME}"
if [ -n "${LOAD_SCRIPTS_DIR}" ]; then
  information_banner "Load scripts:    ${LOAD_SCRIPTS_DIR} (override)"
else
  information_banner "Load scripts:    resolved via conf_resolve (project config → toolkit config)"
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
curl -fSLo "${INSTALL_DIR}/download.zip" "${downloadLink}"
unzip -qq -d "${INSTALL_DIR}" "${INSTALL_DIR}/download.zip"
rm -f "${INSTALL_DIR}/download.zip"

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
			exit_1_banner "Native Windows shells are not supported. Use WSL/Linux on Windows."
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
# Otherwise resolve each script via conf_resolve (project config first, then toolkit config).
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
GT_APP_NAME="${APP_NAME}" \
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
if [ "$exe_path" != "$app_path" ]; then
  mv "${exe_path}" "${app_path}"
fi
[ -f "${INSTALL_DIR}/${APP_NAME}.image" ] || exit_1_banner 'Build did not produce the application image'
mv "$BUILD_DIR" "$GT_INSTALL_DIR"
BUILD_DIR=''
INSTALL_DIR=$GT_INSTALL_DIR

# ---------------------------------------------------------
# gt4gemstone connectors
# ---------------------------------------------------------
bvc_refresh_gt4gemstone_properties "${DEFAULT_REGISTRY}"

# ---------------------------------------------------------
# Done
# ---------------------------------------------------------
information_banner "GT installed:     ${INSTALL_DIR}"
information_banner "Executable:       $(gt_executable)"
information_banner "Image:            ${APP_NAME}.image"
exit_0_banner "DevKit build complete"
