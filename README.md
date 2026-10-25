# BVC — BenjaVision Catalyst

BVC is the command line installation and project tool for developers building
Catalyst applications. It takes you from a project directory to a running local
GT/Pharo DevKit, and provides separate commands for configured GemStone
deployments. Use it when you want a repeatable entry point for setting up,
building, and running Catalyst while keeping your project's configuration in
your own repository.

## Features

- Bootstrap Catalyst tooling with a configurable installation prefix.
- Initialise projects from templates without replacing existing project files.
- Build and run a local DevKit; reuse an application that is already running.
- Install, start, list, stop, and deliberately delete GemStone deployments.
- Configure project sets, startup scripts, and environment defaults per project.
- Detect concurrent operations and retain interrupted setup for a retry.

BVC assembles the components selected by your configuration. It does not make
an unfinished component production-ready or automatically build every C++,
Unreal, or Swift integration. Some bundled loader paths still need
machine-specific configuration, as described below.

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
bvc run
```

This initializes the project and builds and launches the GT/Pharo DevKit/app
without installing or starting a GemStone deployment. Existing installations
are reused. Run commands from the project directory. Use `bvc build` when you
also want to install/start the configured GemStone deployment; individual
components still need their own GemStone qualification.

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
start/stop commands reuse completed installation steps.

New GemStone deployments use the `default_rowan3` template. The Rowan installer
loads the developer tools, then Catalyst Foundation, Runtime and Process through
their Rowan specifications. Project-specific hooks in
`config/gemstone/installers/dev_tools.install` and `projects.install` can override
the bundled recipes. The Runtime recipe expects its prerequisites to be
provisioned separately.

Seaside and GemStone DevKit-stone builds are currently unsupported;
`--with-seaside` has been removed. The DevKit/app still runs in Pharo/GT through
`bvc run`, and `bvc build` starts both that app and the Rowan deployment.
Existing stones are never converted automatically.

Deletion requires typing the deployment name. For an intentional unattended
deletion, use `bvc delete <deployment> --force`.

### Interrupted operations

New DevKit builds are assembled in a temporary directory and published only after
all startup scripts succeed. Failed builds can be retried. An existing incomplete
DevKit directory is preserved: move it aside before retrying so any live work is
not overwritten.

A failed GemStone installation is marked incomplete. Rerunning
`bvc start <deployment>` or `bvc build` resumes configuration and package loading from the last completed step, preserving the stone and its data. The
failed step is retried, so custom installer hooks must support being rerun.
Older empty markers on existing Rowan stones resume configuration and loading.
Incomplete stone creation and unsupported installation markers require
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

The bundled project set uses `catalyst-groups` as the checkout directory for
`BenjaVision-Catalyst/catalyst-groups`. The GT loader loads the `CatalystGroups`
baseline's `Development` group after Runtime and Process, including the Groups
core, local Runtime integration, inspector views, tests and examples. Groups is not added to the
GemStone installer. Existing project-specific project sets or startup scripts
must include the equivalent entries if they replace the bundled configuration.

Before replacing a development image, recover its pending source edits through
GT into an independent clean checkout, verify the export against the live image,
then test, commit and push. Keep the current image open until recovery is verified;
updating a project set does not preserve unsaved image source by itself.

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

## License

This repository is licensed under the [Catalyst Developer License](LICENSE).

Each developer using Catalyst for development needs an active
BenjaVision-Catalyst subscription: **$5 per month, billed annually at $60 per
developer**, including access to the BenjaVision-Catalyst repository. New products,
updates, bug fixes, and recompilation require active developer subscriptions.
Automated build machines do not need separate subscriptions.

Products lawfully built during active subscriptions may continue to be used,
hosted, sold, and distributed indefinitely without runtime royalties. Customers
and operators do not need subscriptions solely to use or distribute those builds.
Commercial and proprietary products are permitted; this license does not require
you to publish your own source code.

Existing license grants and separately licensed third-party material remain
unaffected. See [LICENSE](LICENSE) for the complete terms.
