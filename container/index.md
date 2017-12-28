Welcome to futuswarm! Source at [github/futurice/futuswarm](https://github.com/futurice/futuswarm)

# Getting started

## CLI installation

Install the CLI, under __$HOME__

```
 # (edit your ~/.bashrc to include $HOME/.local/bin in PATH)
mkdir ~/.local/bin
curl CLI_LOCATION -o ~/.local/bin/CLI_NAME
chmod +rx ~/.local/bin/CLI_NAME
```

or system-wide (on macOS /usr/local is user writable)

```
curl CLI_LOCATION -o /usr/local/bin/CLI_NAME
chmod +rx /usr/local/bin/CLI_NAME
```

# My first Docker service

## Write your Dockerfile

An example "Hello World" Dockerfile:

```
git clone https://github.com/mixman/http-hello.git
```

## Build and Deploy

Name your docker image in "COMPANY/name:tag" -format and choose a deployment name.

```
$ docker build -t COMPANY/http-hello:tag .
$ CLI_NAME image:push -i COMPANY/http-hello -t tag
$ CLI_NAME app:deploy -i COMPANY/http-hello -t tag -n http-hello
```
