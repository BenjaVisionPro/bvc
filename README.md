# bvc

BenjaVision Catalyst (`bvc`) is a small command line tool for building and running
Catalyst applications. The DevKit is the application and local server. GemStone
provides persistent deployments, installed with the same procedure on development
and production machines.

## Install

Install in the default location (`/opt`):

```sh
curl -fsSL https://raw.githubusercontent.com/BenjaVisionPro/bvc/refs/heads/main/bin/install.sh | bash -s
```

Or choose an installation prefix:

```sh
curl -fsSL https://raw.githubusercontent.com/BenjaVisionPro/bvc/refs/heads/main/bin/install.sh | bash -s -- --prefix "$HOME/catalyst"
```

The supported hosts are macOS and Linux, including WSL. Initial setup needs Git,
curl, unzip, and GitHub SSH access for the bundled project repositories. GsDevKit
is installed under `${STONES_HOME:-/opt/GsDevKit}` when needed; its host setup may
require sudo. BVC establishes the tooling environment for its child commands,
so a successful bootstrap continues without opening another shell.

## Quick start

```sh
bvc init MyGame
cd MyGame
bvc build
```

This initializes the project, installs and starts its configured GemStone
deployment, and builds and launches the DevKit/app. Existing installations are
reused. Run commands from the project directory.

## Commands

| Command | Behavior |
| --- | --- |
| `bvc init [directory]` | Initialize the current directory, or create and initialize the supplied directory. |
| `bvc build` | Build the DevKit/app and install the configured GemStone deployment if needed, then run both. |
| `bvc run` | Build the DevKit/app if missing, then launch it. Does not install or start a GemStone deployment. |
| `bvc start <deployment>` | Install a GemStone deployment if missing, then start it. |
| `bvc stop <deployment>` | Stop the GemStone deployment and its netldi. Does not stop the DevKit/app. |
| `bvc list` | List registered GemStone deployments and process state. |
| `bvc delete <deployment>` | Delete a GemStone deployment and its data, with confirmation. |

Use `bvc <command> --help` for options.

### Initialize a project

```sh
bvc init                        # Current directory
bvc init MyGame                 # New or existing directory
bvc init MyGame --template=default
```

Initialization copies the template configuration and root files, including
`.gitignore`, without replacing existing project files. Running it again on an
initialized directory succeeds without changing the configuration. The directory
name supplies the initial application name.

### Build and run

```sh
bvc build                       # GemStone plus DevKit/app
bvc run                         # DevKit/app only
```

`build` uses `GEMSTONE_STONE_NAME` from configuration (default: `bvc_dev`). Give
each project its own deployment name when working on multiple projects. It uses
the same installation and startup routines as `start` and `run`.

`run` may install GsDevKit tooling to fetch project dependencies during the first
build, but it never creates or starts a GemStone deployment. Once the app is
built, running it does not require a GemStone installation.

An app already launched by BVC is reused. Launch output is retained in
`${GT_INSTALL_DIR}/bvc.log`. Quit the app through its own UI; source management
also belongs inside the DevKit.

### GemStone deployments

```sh
bvc start mygame-production
bvc list
bvc stop mygame-production
bvc delete mygame-production
```

These commands operate on the current machine, including when invoked on a
production machine. Starting an existing deployment preserves its data. Repeated
start/stop commands reuse completed installation steps. Existing Seaside stones
created before Catalyst loading was added receive those missing steps on start.

The existing Seaside installation path is available on first installation:

```sh
bvc start mygame-production --with-seaside
bvc build --with-seaside
```

`--with-seaside` does not convert an existing deployment. It uses the existing
Seaside/GT installation recipe. Seaside DevKit stones do not currently support
Rowan: their packages must load through Metacello, using GemStone-specific
packages where appropriate. After Seaside and GT support, the recipe loads:

1. Upstream GsApplicationTools Core and [Magritte3 Core](https://github.com/GsDevKit/Magritte3).
2. NeoCSV and NeoJSON.
3. Catalyst Foundation, Runtime and Process.

Catalyst loads directly from each local checkout's `src` directory, using
`gitlocal://<projects-directory>/<project>/src`, as in the Pharo loader.
One sequential `config/gemstone/installers/loadProjects.topaz` script loads them
all, mirroring the Pharo/GT loader while omitting Pharo/GT-only projects. Package
and platform selection belongs in the project baselines. The script can be
overridden per project. The shell invokes it once and records only whether the
whole load succeeded.

New Seaside installations also load GsApplicationTools `Core` through Metacello
from `github://GsDevKit/gsApplicationTools/repository`, the upstream default used
by Catalyst Runtime. The JupiterJones fork is neither cloned nor installed.
Compatibility with a GemStone 3.7.5 Seaside DevKit stone still needs live testing.
Completed Catalyst loads are not repeated. The Rowan Runtime recipe expects its
prerequisites to be provisioned separately.

Deletion requires typing the deployment name. For an intentional unattended
deletion, use `bvc delete <deployment> --force`.

### Interrupted operations

New DevKit builds are assembled in a temporary directory and published only after
all startup scripts succeed. Failed builds can be retried. An existing incomplete
DevKit directory is preserved: move it aside before retrying so any live work is
not overwritten.

A failed GemStone installation is marked incomplete. For Rowan deployments,
rerunning `bvc start <deployment>` or `bvc build` resumes configuration and package
loading from the last completed step, preserving the stone and its data. The
failed step is retried, so custom installer hooks must support being rerun.
Older empty markers on existing Rowan stones resume configuration and loading.
Seaside project loading is one operation. Success is recorded in the stone's
`.bvc-catalyst-loaded` file. A failure leaves the deployment incomplete; correct
the source or dependency and rerun `bvc start <deployment>` (or `bvc build` for
the configured deployment). The whole load script is retried, preserving the
stone and its data; there are no per-project checkpoints.
Incomplete stone creation and earlier Seaside/GT bootstrap failures still require
inspection before resuming; they are never silently recreated or treated as ready.

Concurrent operations on the same installation are rejected with a lock path.
Normal exits release the lock. After a hard kill, inspect its `pid` file and
remove the lock directory only after confirming the owning process has exited.

## Configuration

Configuration precedence, highest first:

1. Environment variables.
2. Project configuration: `${BVC_CONF_DIR:-config}/bvc/bvc_defaults`.
3. Bundled toolkit defaults: `<toolkit>/config/bvc/bvc_defaults`.
4. Safety defaults in `bin/private/shFunctions`.

For example, in a project's `bvc_defaults`:

```sh
: "${BVC_PROJECT_NAME:=MyGame}"
: "${GEMSTONE_STONE_NAME:=mygame-production}"
```

Set `BVC_CONF_DIR` before invoking BVC to use another project configuration
directory. Relative paths resolve from the project directory; the bundled
configuration always stays relative to the installed toolkit.

Project-specific project sets, GemStone installers, and GT startup scripts can
replace their bundled equivalents. The bundled GT loader currently includes
local SpartaSkia/Bloc checkout paths and a local Font Awesome metadata path;
provide a project loader at `config/gt/startup_scripts/loadProjects.st` or adjust
those dependencies for the build machine. Runtime downloads and repository
branches are not yet locked to reproducible revisions.

## Previous command names

`bvc init <directory>` replaces `bvc create <directory>`. `bvc run` replaces
`bvc devkit`. Dependency fetching remains automatic; the existing
`bin/bvcPullProjects.sh` and `bin/bvcLaunchJadeiteForPharo.sh` helpers remain
available for direct use, outside the small public command set.

## Development checks

```sh
python3 -m unittest discover -s tests -v
```

These tests use temporary directories and stub external downloads, GT, and
GemStone commands. They exercise command boundaries, reruns, configuration,
launch detection, and failure propagation without changing real deployments.
They do not replace a build with real runtimes and project packages.
