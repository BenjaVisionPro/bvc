# Named Runtime lifecycle

Run these commands from the project directory. `GEMSTONE_STONE_NAME` selects the
existing, running stone; these operations do not provision or start a stone.

```sh
bvc runtime configure development /absolute/path/runtime.ston
bvc runtime start development
bvc runtime status development
bvc runtime configure development /absolute/path/updated-runtime.ston
bvc runtime restart development
bvc runtime stop development
bvc runtime remove development
```

`start` also accepts a configuration file. A new name requires a file. The file
uses `CRRuntimeConfigurationCodec` schema 1 or 2, with portable service classes
already loaded in the stone. It contains the whole Runtime configuration, not
one file per worker. The accepted value is stored in the stone; later start and
restart operations do not need the file. Reconfiguration increments its version;
start and restart retain the accepted version.

Configure validates before registering a new Runtime. A stopped Runtime remains
stopped. For a running Runtime, acceptance precedes reconciliation: a subsequent
activation failure does not roll back the accepted version. Use status to inspect
the accepted version, published service versions, worker process identities and
observed state. Commands return JSON. `starting` means convergence is pending;
`running` requires the common orchestration report for the current version and
topology, plus live published worker processes.

Stop retains the registered Runtime, configuration, worker evidence and application
data. Restart performs graceful stop followed by start. Remove requires stopped
workers, confirmed process exit and no unresolved control delivery, then removes
only that Runtime's registry entry and its native worker descriptors/bindings.
It does not delete the stone or application data.

Runtime commands use the common `CRRuntimeRegistry`. GemStone stores its durable
root under `UserGlobals at: #CRRuntimeRegistryRoot`; session-local announcers and
Runtime activations are reconstructed per Gem. Native host creation follows the
common Runtime planner. GemServer registration and configuration bindings commit
before launching a Gem. GsDevKit_stones continues to own stone lifecycle.

Runtime uses `CRGemStoneWorkerHost` and the default `CRGemStoneWorker` for
configured workers. Each WorkUnit declares its transaction requirement. Durable
transactional work commits dequeue, nested body outcome, acknowledgement and
completion evidence together. Nontransactional control work retains the existing
RcQueue claim/acknowledgement boundary and executes outside repository transactions.
Local schedules and reconciliation triggers remain in the activation-local queue.
An interrupted or uncertain delivery requires inspection; it is never silently
replayed. No execution profile selection is added to configuration.
Old ownership and activation generations are checked on submission, consumption
and publication. Automatic takeover after an unconfirmed worker failure remains
disabled; inspect the worker log and delivery before recovery.

### Reviewed process exit

A fatal completion-recording error invalidates the worker's transaction backend.
The worker then refuses service cleanup in that unsafe Gem and can leave native
state `cleanupPending` even after the process exits. Stop deliberately refuses
to treat that as graceful cleanup.

After preserving and reviewing the logs, launch identity, publication and delivery
state, a dedicated `bvc topaz` session can record an explicit exit review through
the Runtime. Pass the process observation captured during that inspection:

```smalltalk
runtime confirmExitedWorker: workerIdentifier
    process: inspectedProcessObservation
    reason: 'Inspection findings and preserved evidence location'.
```

This requires a fenced, stopping or stopped Runtime, confirmed exit of all its
Gems, the same inspected PID and launch token, a matching host generation, and
an empty queue with no claimed delivery for the reviewed worker. It refuses a
caller-owned transaction. A matching review is idempotent; it never executes,
acknowledges or restarts work.

Then use the ordinary `bvc runtime stop <name>`. Status reports effective process
state `stopped`, retains the original `nativeState`, and includes
`cleanupResolution.kind = reviewedProcessExit`. The stopped worker publication
retains the original process observation, publication, reconciliation state,
reason and review time in its `nativeExitReview` statistics. Native launch and
state files are unchanged. Retaining the stopped Runtime preserves this evidence;
remove remains a separate explicit operation.

The integration test `tests/runtime_lifecycle_native.py` is opt-in and requires a
provisioned development stone and a configuration containing an orchestrator and
a socket-free probe service on different hosts. It tests real Gems and fresh
management sessions, including version adoption, restart, stale ownership and
concurrent named creation. It removes its own successful test Runtimes. A failed
run preserves its evidence for inspection. No socket transport is started.

After loading production Runtime, prepare only the two test service/WorkUnit
fixtures from the verified Runtime checkout, then run the supplied configuration:

```sh
BVC_RUNTIME_REPOSITORY=tonel:///absolute/path/CatalystRuntime/src \
  bvc topaz <deployment> --script /absolute/path/bvc/config/gemstone/prepare-runtime-lifecycle.topaz
python3 /absolute/path/bvc/tests/runtime_lifecycle_native.py \
  --project /absolute/path/project --deployment <deployment> \
  --configuration /absolute/path/bvc/tests/fixtures/runtime-lifecycle.ston \
  --report /absolute/path/lifecycle-results.json
```

This preparation loads four fixture definitions and no GT UI/examples package.

## Quinn Connect service

The incremental `bin/bvcLoadConnect.sh <deployment>` recipe now selects
`BVC-Connect-Quic-Core`, `BVC-Connect-Quic-GemStone`, and
`BVC-Connect-Quic-Configuration`, reusing provisioned prerequisites. It verifies
native buffer ownership and Runtime configuration serialization without starting
a listener. Replace an older project-local `config/gemstone/load-portable-connect.topaz`
override with the current recipe when upgrading; project overrides take precedence.
The previous TCP/DTLS packages are retired.

Build Connect's Rust library for the Gem host and generate the complete Runtime
file with [Connect's configuration renderer](https://github.com/BenjaVisionPro/CatalystConnect/blob/main/scripts/runtime-configuration.py).
The file selects a QUIC service, absolute native library and identity paths,
trusted peer certificate, principal, operation allowlist and application class.
Use the ordinary configure/start/status/restart/stop/remove commands above. The
library is immutable once loaded: gracefully stop and restart the Gem to change
its native build. See [Connect](https://github.com/BenjaVisionPro/CatalystConnect)
for the wire/security boundary and current qualification limits.

## Native GT/GemStone interoperability

After rebuilding GT and loading Foundation, Runtime and Quinn Connect into a
native stone, run the opt-in qualification with the new immutable native library:

```sh
python3 /absolute/path/bvc/tests/connect_interop_native.py \
  --project /absolute/path/project \
  --deployment development \
  --connect /absolute/path/CatalystConnect \
  --library /absolute/path/connect-build/release/libcatalyst_connect.dylib \
  --output /absolute/path/new-qualification-directory
```

Use `libcatalyst_connect.so` on Linux. The identity tool must be beside the library
(as produced by Connect's build script). The output directory must be new. GT must
already have `CCQuicNativeExamples`, `CCNativeInteropRun` and `CCNativeMcpLease`
loaded; the runner does not alter image source. If GT already bound a Connect
library, pass that same immutable path. Keep private identity files in the output
directory out of source control.

Each run verifies copy and XOR at 0, 8, 256, 1024 and 4080 bytes: GT client to a
native GemStone server, GemStone client to a GT server, and GT client to a managed
server before and after restart. It checks payloads, admission/copy/call bounds,
process separation, positive native cleanup, unchanged Runtime identity/version,
and replacement of live Gems on restart. GT operations use the MCP lease; the
controller waits on the filesystem completion marker before joining.

By default the generated named Runtime is stopped and removed. To retain a
localhost development server, add `--runtime-name connect-dev --keep-runtime`.
An already registered name is rejected. The final `interop-evidence.json` records
the listening address and accepted configuration. That handler supports copy/XOR
only; higher-level CATP protocols remain separate work. On a failure, inspect the
retained logs and owner markers before retrying. No owner is killed and no MCP
server is reset by this runner.
