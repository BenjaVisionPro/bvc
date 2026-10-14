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
  bvc run
EOF_USAGE
  exit "${1:-1}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h) usage 0 ;;
    *) error_banner "Unknown option for run: $1"; usage ;;
  esac
  shift
done

gt_dir="$(abs_from_cwd "${GT_INSTALL_DIR}")"
gt_dir=${gt_dir%/}
GT_INSTALL_DIR=$gt_dir
bvc_lock "${gt_dir}.run-lock"
if gt_running; then
  exit_0_banner 'DevKit/app is already running'
fi

if ! gt_installed; then
  information_banner "DevKit not found locally; syncing project sets before build."
  "${SCRIPT_DIR}/bvcPullProjects.sh"
  "${SCRIPT_DIR}/bvcBuildDevKit.sh"
else
  bvc_refresh_gt4gemstone_properties "${DEFAULT_REGISTRY}"
fi

[ -d "$gt_dir" ] || exit_1_banner "DevKit install directory not found: ${gt_dir}"
exe_path="$(gt_executable "$gt_dir")"

[ -x "$exe_path" ] || exit_1_banner "DevKit executable not found: ${exe_path}"

image_file="${gt_dir}/${GT_APP_NAME}.image"
information_banner "Launching DevKit from ${exe_path} with image ${image_file}"
(
  cd "$gt_dir"
  nohup "$exe_path" --interactive "$image_file" >> "${gt_dir}/bvc.log" 2>&1 &
  printf '%s\n' "$!" > "${gt_dir}/.bvc.pid"
  disown || true
)
sleep 1
gt_running || exit_1_banner "DevKit exited during launch. See ${gt_dir}/bvc.log"
exit_0_banner "DevKit launched"
