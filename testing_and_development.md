
# Testing and development

Bats can be used to test much of the installation in a local Docker Swarm.

## Install Bats

https://github.com/sstephenson/bats

There seems to be a fork with improvements at https://github.com/bats-core/bats-core (TODO: test).

## Run unit tests

This example uses specifics for Docker MacOS. Adjust to meet Linux/Windows equivalents.
* MacOS Docker Host hostname is "host.docker.internal" and "localhost" for Linux.

```sh
CLOUD=test \
    AWS_DEFAULT_REGION= \
    AWS_KEY= \
    AWS_SECRET='' \
    REGISTRY_USER='' \
    REGISTRY_PASS='' \
    RDS_USER='' \
    RDS_PASS='' \
    RDS_HOST="host.docker.internal" \
    SWARM_MAP="host.docker.internal:2223,worker-1" \
    SSH_FLAGS="-o UserKnownHostsFile=/dev/null" \
    bats test_swarm.sh
```

* RDS_USER, RDS_PASS, RDS_HOST are used to configure a local Postgres instance to mimic RDS usage.
* SSH_FLAGS configuration means not needing to clear `~/.ssh/known_hosts` localhost -entries between runs.
* (optional) CONFIG_DIR= specify settings directory

## After local swarm up from running unit tests

A specially configured CLI that works against the local Docker Swarm is available.

```sh
/tmp/cli_local app:list
/tmp/cli_local app:deploy -n hello_world -i mixman/hello-world
```

## Updating client-server communication files when developing

```sh
docker cp setup/commands.sh servers:/opt/
docker cp server/server.sh servers:/srv/
docker cp setup/commands.sh worker-1:/opt/
docker cp server/server.sh worker-1:/srv/
```

