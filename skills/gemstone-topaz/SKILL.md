---
name: gemstone-topaz
description: Develop, inspect, test and debug Catalyst GemStone adapters in a running stone using linked Topaz. Use for native GemStone sessions and Gem launch diagnostics; shared GT-managed source continues through GT MCP.
---

# GemStone Topaz

Use the bvc checkout on PATH or this skill's ../../bin/bvc. Start in the deployment's project directory so bvc resolves its config, stone product and login file. `bvc topaz` attaches to an existing stone; it does not create/start a stone or commit changes automatically.

```sh
bvc topaz <deployment>
bvc topaz <deployment> --script /absolute/path/check.topaz
```

For interactive debugging, use exec_command with tty:true and retain its session_id; send commands through write_stdin. Start with a short yield. Batch mode prints the failing stack and exits nonzero; use interactive mode when the stack must remain available. See [native workflow](references/native-workflow.md) for debugger commands, source export and the current development stone.

GemStone-specific adapters may be compiled, tested and exported directly from GemStone when the user requests native development. Shared Runtime/Connect/Foundation classes remain authoritative in live GT: inspect/compile/export those through GT MCP. Do not edit GT-managed .st files externally or change Git metadata in GT-registered checkouts. Export native compiled source to an independent checkout and verify a native package snapshot round trip before commit/push. Reconcile shared changes through GT rather than silently replacing them in the stone.

Run only the requested tests and operations. Topaz sessions can commit live data; establish which stone and transaction mode are in use before mutating. Use a dedicated session for tests owning begin/commit/abort. A transaction belongs to the Gem session, not independently to each Smalltalk process. Socket I/O and external effects cannot be rolled back. Keep socket state, executable activations and local locks in SessionTemps/TransientValue rather than the persistent descriptor graph.

Honor the project's normal commit/push workflow after passing checks. Native GemStone results and GT/double results are separate evidence. Native C++/GT tests still require CCNativeMcpLease and its outside-GT completion marker.
