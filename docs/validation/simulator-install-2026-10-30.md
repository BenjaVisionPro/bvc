# Simulator rebuild integration

30 October 2026. Simulator Core source: `catalyst-simulator` commit `de70a61`.

- All 59 CLI/worker contract tests pass (`python3 -B -m unittest discover -s tests -v`).
  Launch tests require host process inspection; sandboxed macOS `ps` is denied.
  External runtimes and stones in this suite are temporary stubs.
- The bundled project-set data parses through STON, and the complete GT startup
  script parses through the live GT Smalltalk parser. Simulator selects `Tests`.
- Shell syntax checks pass for both installer helpers and the Seaside launcher.
- `load-portable-simulator.topaz` ran successfully through bvc Topaz against the
  existing GemStone 3.7.5 `bvc_foundation_portable` stone. Its
  [native report](simulator-core-install-2026-10-30.ston) records exact source
  definition comparison, graph movement, model digest and checkpoint continuation.
- Failure/retry tests cover Rowan Simulator failure, missing Seaside sources and
  failures in either Seaside project recipe, preserving the same stone/data and
  completed developer-tool steps.

The Rowan installer selects `CatalystSimulatorCore.ston` with the lowercase
checkout alias. The Seaside recipe loads the unchanged Tonel exports directly
after Foundation; neither installer selects Simulator Tests. Fresh GT image and
Rowan/Seaside stone rebuild qualification remains the next gate. Project-local
configuration overrides must incorporate the new bundled entries explicitly.
