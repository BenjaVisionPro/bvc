# bvc

BenjaVision Catalyst (bvc) command line tool for managing applications built with Catalyst DevKit.

### Install

To install the bvc command line tools in the default location (/opt) execute the following in a terminal.

```
curl -fsSL https://benjavision.com/catalyst/install.sh | bash -s

```

If you want to install it in an alternate location pass the path
```
curl -fsSL https://benjavision.com/catalyst/install.sh | bash -s -- --prefix "$HOME/catalyst"

```



### Create a new project

Create a new project directory with a starting configuration, then change to that directory.

```
bvc create <projectName>
cd <projectName>
```
eg.
```
bvc create ThatGameCatalyst
cd ThatGameCatalyst
```

### Run the project (building it first if necessary)

```
bvc devkit
```

### Start a production server (building it first if necessary)
```
bvc start <deploymentName>
```
eg.
```
bvc start tgc-prod-test
```

### Stop a production server
```
bvc stop <deploymentName>
```
eg.
```
bvc stop tgc-prod-test
```

### Delete a production server

This will delete the server and all associated data.

```
bvc delete <deploymentName>
```
eg.
```
bvc delete tgc-prod-test
```
