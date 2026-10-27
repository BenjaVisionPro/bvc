#!/usr/bin/env bash
# Internal launcher for a registered single-Gem Runtime host. The future public
# bvc worker interface will resolve these hosts from runtime configuration.
set -euo pipefail
PROGNAME=$0
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
. "${SCRIPT_DIR}/private/shFunctions"
load_bvc_config
setup_traps
usage() { printf '%s\n' 'Usage: bvcWorkerGem.sh start|stop|restart|status <deployment> <registered-worker>'; }
[ "$#" -eq 3 ] || { usage >&2; exit 1; }
action=$1
stoneName=$2
workerName=$3
case "$action" in start|stop|restart|status) ;; *) usage >&2; exit 1 ;; esac
bvc_validate_deployment_name "$stoneName"
bvc_validate_deployment_name "$workerName"
stoneDir="$(abs_from_cwd "$GSDEVKIT_STONES_DIR")/${stoneName}"
export GEMSTONE="${stoneDir}/product"
topaz="${GEMSTONE}/bin/topaz"
projectsRoot=$(abs_from_cwd "$PROJECTS_ROOT")
login="${BVC_TOPAZ_LOGIN:-${projectsRoot}/dev_tools/gt4gemstone/scripts/loginDataCurator.topaz}"
login=$(abs_from_cwd "$login")
template=$(conf_resolve 'gemstone/run-worker.topaz')
[ -x "$topaz" ] && [ -s "$login" ] && [ -s "$template" ] || exit_1_banner 'Missing Topaz product, login or worker runner.'
stateDir="${stoneDir}/workers/${workerName}"
runner="${stateDir}/run-worker.topaz"
stateTool="${SCRIPT_DIR}/private/workerState.py"
observe() { python3 "$stateTool" "$stateDir" "$runner" "$@"; }
if [ "$action" = status ]; then observe; exit 0; fi
mkdir -p "$stateDir"
bvc_lock "${stateDir}/.operation-lock"
export STONE=$stoneName BVC_WORKER_NAME=$workerName
export BVC_PROJECT_DIRECTORY="$PWD"
export BVC_WORKER_GEM_SCRIPT="${SCRIPT_DIR}/bvcWorkerGem.sh"
export BVC_DEPLOYMENT_NAME=$stoneName
export BVC_WORKER_STATE="${stateDir}/state.json"
export BVC_WORKER_STOP="${stateDir}/stop-request"
export GEMSTONE_LOGDIR="$stateDir"
export PATH="${GEMSTONE}/bin:${PATH}"
start_worker() {
  local phase token pid iteration
  phase=$(observe --field state)
  case "$phase" in
    running) observe; return 0 ;;
    starting) ;;
    stopped)
      rm -f -- "$BVC_WORKER_STOP" "$BVC_WORKER_STATE"
      cp -- "$template" "$runner"
      token=$(python3 -c 'import uuid; print(uuid.uuid4())')
      export BVC_WORKER_TOKEN=$token
      cp -- "${stoneDir}/gem.conf" "${stateDir}/gem.conf"
      if [ "${BVC_WORKER_DEBUG:-0}" = 1 ]; then
        printf '\n%s\n' 'GEM_LISTEN_FOR_DEBUG = TRUE;' >> "${stateDir}/gem.conf"
      fi
      pid=$(python3 -c 'import subprocess,sys; log=open(sys.argv[2],"ab"); process=subprocess.Popen(sys.argv[3:],cwd=sys.argv[1],stdin=subprocess.DEVNULL,stdout=log,stderr=subprocess.STDOUT,start_new_session=True); print(process.pid)' "$stoneDir" "${stateDir}/gem.log" "$topaz" -l -e "${stateDir}/gem.conf" -I "$login" -S "$runner")
      python3 -c 'import json,sys; from pathlib import Path; Path(sys.argv[1]).write_text(json.dumps({"pid":int(sys.argv[2]),"token":sys.argv[3]}))' "${stateDir}/launch.json" "$pid" "$token"
      ;;
    *) observe >&2; exit_1_banner 'Worker state needs inspection before starting.' ;;
  esac
  for ((iteration=0; iteration<200; iteration++)); do
    phase=$(observe --field state)
    case "$phase" in
      running) observe; return 0 ;;
      starting) sleep 0.05 ;;
      *) observe >&2; exit_1_banner "Worker failed to become ready; inspect ${stateDir}/gem.log" ;;
    esac
  done
  exit_1_banner "Worker readiness timed out; inspect ${stateDir}/gem.log"
}
stop_worker() {
  local phase token iteration
  phase=$(observe --field state)
  case "$phase" in stopped) observe; return 0 ;; running|starting) ;; *) observe >&2; exit_1_banner 'Worker state needs inspection before stopping.' ;; esac
  token=$(observe --field token)
  printf '%s\n' "$token" > "$BVC_WORKER_STOP"
  for ((iteration=0; iteration<200; iteration++)); do
    phase=$(observe --field state)
    case "$phase" in
      stopped) observe; return 0 ;;
      exited) observe >&2; exit_1_banner 'Gem exited without confirmed Runtime cleanup.' ;;
      cleanupPending|failed|unknown) observe >&2; exit_1_banner 'Runtime cleanup needs inspection.' ;;
      *) sleep 0.05 ;;
    esac
  done
  exit_1_banner "Worker shutdown timed out; Gem left available for diagnosis: ${stateDir}/gem.log"
}
case "$action" in start) start_worker ;; stop) stop_worker ;; restart) stop_worker > /dev/null; start_worker ;; esac
