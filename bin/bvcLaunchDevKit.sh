#!/usr/bin/env bash
set -euo pipefail

PROGNAME=$0
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)

# shellcheck disable=SC1091
. "${SCRIPT_DIR}/private/shFunctions"

load_bvc_config
setup_traps
start_banner "$@"
information_banner "Launch Catalyst DevKit"

usage() {
  cat 1>&2 <<EOF_USAGE
Usage:
  $(prog_basename "$PROGNAME")
EOF_USAGE
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h) usage ;;
    *) error_banner "Unknown option for devkit: $1"; usage ;;
  esac
  shift
done

ensure_gsdevkit_ready
ensure_registry_exists "$DEFAULT_REGISTRY"

if ! gt_installed; then
  information_banner "DevKit not found locally; syncing project sets before build."
  "${SCRIPT_DIR}/bvcPullProjects.sh"
  "${SCRIPT_DIR}/bvcBuildDevKit.sh"
else
  bvc_refresh_gt4gemstone_properties "${DEFAULT_REGISTRY}"
fi

gt_dir="$(abs_from_cwd "${GT_INSTALL_DIR}")"
[ -d "$gt_dir" ] || exit_1_banner "DevKit install directory not found: ${gt_dir}"

case "$(uname -s)" in
  Darwin) exe_path="${gt_dir}/${GT_APP_NAME}.app/Contents/MacOS/GlamorousToolkit-cli" ;;
  Linux)  exe_path="${gt_dir}/bin/GlamorousToolkit-cli" ;;
  *)      exit_1_banner "Unsupported platform for DevKit launch. Use macOS, Linux, or WSL." ;;
esac

[ -x "$exe_path" ] || exit_1_banner "DevKit executable not found: ${exe_path}"

image_file="${GT_APP_NAME}.image"
information_banner "Launching DevKit from ${exe_path} with image ${image_file}"
(
  cd "$gt_dir"
  nohup "$exe_path" --interactive "$image_file" >/dev/null 2>&1 &
  disown || true
)
exit_0_banner "DevKit launched"
