# Native development workflow

## Resolve and connect

`bvc topaz` reads normal ENV > project config > toolkit defaults. It uses `stones/<deployment>/product/bin/topaz -l`, sets GEMSTONE and STONE, and loads `git_root/dev_tools/gt4gemstone/scripts/loginDataCurator.topaz`. Set BVC_TOPAZ_LOGIN to an existing alternative login file for other users or installations. Keep credentials out of tracked skills and scripts.

The current experimental project is `/opt/git/BenjaVisionPro/catalyst-workspace/recovery/bvc-seaside-20261027/experiment`; the existing stone is `bvc_foundation_portable`, GemStone 3.7.5 arm64.Darwin. Foundation/Magritte and seven portable Runtime packages are loaded. Its config selects registry `bvc_foundation_trial` and STONES_DATA_HOME under the sibling `registry-data` directory. These are development-session facts, not universal defaults. Check current project files and stone state before assuming they still exist. Do not substitute the similarly named incomplete `bvc_foundation_dev` stone.

For a basic inspection script:

```text
run
STON toString: {(System gemEnvironmentVariable: 'STONE'). System transactionMode. System inTransaction}
%
```

Batch mode supplies stack/exit handlers and a final errorCount/exit. It never supplies commit. Check process status as well as the output. Use real script files and EOF; a missing -S script combined with /dev/zero can flood logs indefinitely.

## Debug in a retained interactive session

Useful Topaz commands (check `help <command>` for exact syntax):

```text
iferr 1 stk
iferr 2 stack
run
self error: 'debug probe'
%
stk
stack
frame 1
list
inspect receiver
```

`stk` gives a compact stack; `stack` includes receiver/temporary details. `frame <n>` selects a context. Use `list`, `inspect`, `send`, `step`, and `continue` after checking their help and selected context. `abort` changes repository view and can invalidate objects; capture the failure first. End an owned inspection session with `logout` then `exit` when it is no longer needed.

For another Gem, the documented `debuggem <pid> <token>` protocol requires that the target explicitly enable debug listening (`System listenForDebugConnection` / `waitForDebug`). The token comes from that target. Do not enable listeners globally or interrupt unrelated workers. Remote debugging is a capability to test on a dedicated worker, not an assumption of this skill.

## Native compilation and export

Topaz `method: ClassName` / `classmethod: ClassName` accepts method text terminated by `%`; `category:` sets the protocol. Inspect the compiled method with `ClassName sourceCodeAt: #selector`. Compile/initialize classes and commit only as required by the native change. Native syntax differs from Pharo (for example inherited slot/argument shadowing is rejected).

The current stone uses Monticello plus the pinned GemStone Tonel port. `MCPackage named:` and `MCWorkingCopy` can inspect package snapshots. Inspect the installed Tonel writer APIs before exporting: loading the reader does not qualify all optional writer dependencies. Verify exported definitions against the live native snapshot, keeping platform-specific method ownership intact. Never create a hand-transcribed Tonel export and call it verified source.

## Manuals

- [Topaz 3.7 guide](https://downloads.gemtalksystems.com/docs/GemStone64/3.7.x/GS64-Topaz-3.7/MAIN.htm): development, stack inspection, breakpoints and remote debugging.
- [Programming guide](https://downloads.gemtalksystems.com/docs/GemStone64/3.7.x/GS64-ProgGuide-3.7/MAIN.htm): transactions, RcQueue/RcPipe, sockets and SessionTemps.
- [gsApplicationTools](https://github.com/GsDevKit/gsApplicationTools): startup, manualBegin and backlog patterns. Treat its wrappers as source material; Runtime owns its execution/transaction model.
