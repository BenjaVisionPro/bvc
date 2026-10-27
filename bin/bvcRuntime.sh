#!/usr/bin/env bash
set -euo pipefail
PROGNAME=$0
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
. "${SCRIPT_DIR}/private/shFunctions"
load_bvc_config
setup_traps

usage() {
  printf '%s\n' 'Usage: bvc runtime start|configure <runtimeName> [configurationFile]' \
    '       bvc runtime stop|restart|status|remove <runtimeName>'
}
case "${1:-}" in --help|-h) usage; exit 0 ;; esac
[ "$#" -ge 2 ] && [ "$#" -le 3 ] || { usage >&2; exit 1; }
export BVC_RUNTIME_ACTION=$1 BVC_RUNTIME_NAME=$2
bvc_validate_deployment_name "$BVC_RUNTIME_NAME"
case "$BVC_RUNTIME_ACTION" in
  start|configure) ;;
  stop|restart|status|remove) [ "$#" -eq 2 ] || { usage >&2; exit 1; } ;;
  *) usage >&2; exit 1 ;;
esac
export BVC_RUNTIME_CONFIGURATION=''
if [ "$#" -eq 3 ]; then
  BVC_RUNTIME_CONFIGURATION=$(abs_from_cwd "$3")
  [ -r "$BVC_RUNTIME_CONFIGURATION" ] && [ -f "$BVC_RUNTIME_CONFIGURATION" ] ||
    exit_1_banner "Configuration file is not readable: ${BVC_RUNTIME_CONFIGURATION}"
fi
stoneDir="$(abs_from_cwd "$GSDEVKIT_STONES_DIR")/${GEMSTONE_STONE_NAME}"
[ -d "$stoneDir" ] || exit_1_banner "Deployment '${GEMSTONE_STONE_NAME}' does not exist."
recipe=$(conf_resolve 'gemstone/runtime.topaz')
[ -s "$recipe" ] || exit_1_banner 'Missing Runtime management recipe.'
if [ "$BVC_RUNTIME_ACTION" != status ]; then
  bvc_lock "${stoneDir}/.${BVC_RUNTIME_NAME}.runtime-lock"
fi
scratch=$(mktemp -d "${TMPDIR:-/tmp}/bvc-runtime.XXXXXX")
cleanup_runtime() {
  rm -rf -- "$scratch"
  if [ -n "${bvc_lock_dir:-}" ]; then
    rm -f -- "${bvc_lock_dir}/pid"
    rmdir -- "$bvc_lock_dir"
  fi
}
trap cleanup_runtime EXIT
export BVC_RUNTIME_RESULT="${scratch}/result.json"
runtime_failure_log() {
  sed -n '/^ERROR /{p;q;}' "${scratch}/topaz.log" >&2
  tail -80 "${scratch}/topaz.log" >&2
}
if ! "${SCRIPT_DIR}/bvcTopaz.sh" "$GEMSTONE_STONE_NAME" --script "$recipe" > "${scratch}/topaz.log" 2>&1; then
  runtime_failure_log
  exit 1
fi
if [ ! -s "$BVC_RUNTIME_RESULT" ]; then
  runtime_failure_log
  exit_1_banner 'Runtime command did not publish a result.'
fi
cat -- "$BVC_RUNTIME_RESULT"
printf '\n'
