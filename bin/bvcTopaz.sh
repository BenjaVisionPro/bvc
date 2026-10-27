#!/usr/bin/env bash
# Attach only: no provisioning, automatic commits or stone lifecycle changes.
set -euo pipefail
PROGNAME=$0
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
. "${SCRIPT_DIR}/private/shFunctions"
load_bvc_config
usage() { printf '%s\n' 'Usage: bvc topaz <deployment> [--script FILE]'; }
case "${1:-}" in --help|-h) usage; exit 0 ;; esac
[ "$#" -ge 1 ] || { usage >&2; exit 1; }
stoneName=$1
shift
bvc_validate_deployment_name "$stoneName"
script=
if [ "$#" -gt 0 ]; then
  [ "$#" -eq 2 ] && [ "$1" = --script ] || { usage >&2; exit 1; }
  script=$(abs_from_cwd "$2")
  [ -s "$script" ] || exit_1_banner "Missing or empty Topaz script: ${script}"
fi
stoneDir="$(abs_from_cwd "$GSDEVKIT_STONES_DIR")/${stoneName}"
[ -f "${stoneDir}/.GDKStoneSpec.ston" ] || exit_1_banner "Missing deployment: ${stoneName}"
export GEMSTONE="${stoneDir}/product"
topaz="${GEMSTONE}/bin/topaz"
[ -x "$topaz" ] || exit_1_banner "Missing linked Topaz: ${topaz}"
projectsRoot=$(abs_from_cwd "$PROJECTS_ROOT")
login="${BVC_TOPAZ_LOGIN:-${projectsRoot}/dev_tools/gt4gemstone/scripts/loginDataCurator.topaz}"
login=$(abs_from_cwd "$login")
[ -s "$login" ] || exit_1_banner "Missing Topaz login file: ${login}; set BVC_TOPAZ_LOGIN"
export STONE=$stoneName
export BVC_PROJECT_DIRECTORY="$PWD"
export BVC_WORKER_GEM_SCRIPT="${SCRIPT_DIR}/bvcWorkerGem.sh"
export BVC_DEPLOYMENT_NAME=$stoneName
export PATH="${GEMSTONE}/bin:${PATH}"
cd "$stoneDir"
if [ -z "$script" ]; then
  exec "$topaz" -l -I "$login"
fi
batch=$(mktemp "${TMPDIR:-/tmp}/bvc-topaz.XXXXXX")
trap 'rm -f -- "$batch"' EXIT
{
  printf '%s\n' 'iferr 1 stk' 'iferr 2 stack' 'iferr 3 exit'
  cat -- "$script"
  printf '\n%s\n' 'errorCount' 'exit'
} > "$batch"
# EOF is deliberate. Never use /dev/zero as a substitute for a valid script.
"$topaz" -l -I "$login" -S "$batch" < /dev/null
