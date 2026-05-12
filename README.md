# bvc

BenjaVision Catalyst (`bvc`) command line tool for managing applications built with Catalyst DevKit.

## Install

To install the `bvc` command line tools in the default location (`/opt`), run:

```sh
curl -fsSL https://raw.githubusercontent.com/BenjaVisionPro/bvc/refs/heads/main/bin/install.sh | bash -s
```

To install in an alternate location, pass a prefix:

```sh
curl -fsSL https://raw.githubusercontent.com/BenjaVisionPro/bvc/refs/heads/main/bin/install.sh | bash -s -- --prefix "$HOME/catalyst"
```

## Create a new project

Create a new project directory with a starting configuration, then change to that directory.

```sh
bvc create <projectName>
cd <projectName>
```

Example:

```sh
bvc create ThatGameCatalyst
cd ThatGameCatalyst
```

This creates:

```text
ThatGameCatalyst/
  config/
    bvc/
      bvc_defaults
```

## Initialise an existing directory

Turn the current directory into a Catalyst project:

```sh
bvc init
```

The generated project config is copied from the default project template. It contains the full default shape with most values commented out; uncomment values to override them for the project.

## Run the project

Build Catalyst DevKit if needed, then launch it:

```sh
bvc devkit
```

## Launch Jadeite for Pharo

Build Jadeite for Pharo if needed, then launch it:

```sh
bvc j4p
```

## Pull project dependencies

Sync configured Catalyst project sets:

```sh
bvc pull
```

## Start a production server

Start a deployment, installing it first if necessary:

```sh
bvc start <deploymentName>
```

Example:

```sh
bvc start tgc-prod-test
```

Temporary Seaside install path:

```sh
bvc start <deploymentName> --with-seaside
```

`--with-seaside` only affects the first install when the deployment does not yet exist. Once installed, starting the deployment is the same either way.

## Stop a production server

```sh
bvc stop <deploymentName>
```

Example:

```sh
bvc stop tgc-prod-test
```

## Delete a production server

This deletes the server and associated data. It prompts for confirmation unless `--force` or `-f` is supplied.

```sh
bvc delete <deploymentName>
```

Example:

```sh
bvc delete tgc-prod-test
bvc delete tgc-prod-test --force
```

## Configuration

Config is layered from highest to lowest precedence:

1. Environment variables
2. Project config root: `${BVC_CONF_DIR:-config}/bvc/bvc_defaults`
3. Bundled toolkit defaults: `<toolkit>/config/bvc/bvc_defaults`
4. Hard-coded safety defaults in `bin/private/shFunctions`

`BVC_CONF_DIR` selects the project config directory only. The toolkit's bundled config always remains relative to the installed `bvc` toolkit. To use a non-default project config directory, set `BVC_CONF_DIR` in the environment before running `bvc`.
