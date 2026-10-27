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

Each managed local worker has an RcQueue control inbox. A claimed control delivery
remains visible until local execution completes and acknowledgement commits.
An interrupted or uncertain delivery requires inspection; it is never silently
replayed. This does not provide transactional delivery for arbitrary local
application work. Persistent transactional workers retain their existing profile.
Old ownership and activation generations are checked on submission, consumption
and publication. Automatic takeover after an unconfirmed worker failure remains
disabled; inspect the worker log and delivery before recovery.

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
