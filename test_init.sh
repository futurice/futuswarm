#!/usr/bin/env bash
RUN_ID="${RANDOM}-test"
cd setup/
MODENV=n source init.sh
cd - 1>/dev/null

log() {
    echo "$(date +"%Y.%m.%d %H:%M:%S") $1" >>/tmp/test_swarm
}

nl_to_space() {
echo $(python -c "import re;o=\"\"\"$1\"\"\";print(re.sub('\n',' ',o))")
}

setup() {
log "setup: $BATS_TEST_NAME"
}

teardown() {
log "teardown: $BATS_TEST_NAME"
}

UP="${UP:-}"
function ensure_container_running {
    if [ -z "$UP" ]; then
        log "Start test 'test_swarm'"
        chmod 0600 server/server-key-for-tests
        chmod 0600 server/server-key-for-tests.pub

        > /tmp/test_swarm
        # swarm
        log "swarm:node:rm worker-1"
        docker node rm -f worker-1 >&/dev/null||true
        log "swarm:destroy"
        docker swarm leave --force >&/dev/null||true
        log "swarm:cleanup"
        docker node ls|grep Dow[n]|awk {'print $1'}|xargs docker node rm -f

        # local postgres (RDS mock)
        docker rm -f -v futuswarm-postgres >&/dev/null||true
        docker run --restart always --name futuswarm-postgres -e POSTGRES_PASSWORD="$RDS_PASS" -p 127.0.0.1:"$RDS_PORT":5432 -d postgres:9.6.3 >&/dev/null||true

        CLOUD=test
        SSH_PORT_SERVER=2222
        SSH_PORT_WORKER=2223
        HOST=localhost
        REMOTE_REGISTRY_PORT=$DOCKER_REGISTRY_PORT
        SSH_KEY="$(pwd)/server/server-key-for-tests"
        NODE_LIST="localhost"
        RESTART_SSH=false
        AWS_DEFAULT_REGION=eu-west-1
        AWS_ACCESS_KEY_ID="$AWS_KEY"
        AWS_SECRET_ACCESS_KEY="$AWS_SECRET"
        DOCKER_HOST_ADDR="$(echo "$SWARM_MAP"|cut -d, -f1)"
        WORKER_NODES="$DOCKER_HOST_ADDR"
        NODE_LIST_PUBLIC="$NODE_LIST_PUBLIC"

        log "swarm:init"
        docker swarm init >&/dev/null||true
        SWARM_MASTER=$(docker info|grep -w 'Node Address'|awk '{print $3}')
        SWARM_TOKEN=$(docker swarm join-token -q worker)
        log "swarm:rm worker-1"
        docker rm -f -v worker-1 >&/dev/null||true
        log "swarm:run worker-1"
        docker run -d --privileged --restart always --name worker-1 --hostname=worker-1 -p 127.0.0.1:12375:2375 -p 127.0.0.1:$SSH_PORT_WORKER:22 docker:18.01.0-ce-dind >&/dev/null||true
        log "swarm:join worker-1 to manager"
        docker --host=localhost:12375 swarm join --token ${SWARM_TOKEN} ${SWARM_MASTER}:2377 >&/dev/null||true

        # start manager
        cd server/
        log "manager:build 'servers' image"
        TAG=$(git rev-parse --short HEAD)
        docker build -t servers:$TAG .
        log "manager:rm old 'servers' container"
        docker rm -f -v servers >&/dev/null||true
        log "manager:run 'servers' container"
        docker run -d -p 127.0.0.1:$SSH_PORT_SERVER:22 --name servers \
            -v /var/run/docker.sock:/var/run/docker.sock \
            servers:$TAG
        cd -

        # setup node
        log "node:dind"
        cd server/
        ( NAME=worker-1 . ./prepare_dind.sh )
        cd -

        log "node:restricted_shell"
        cd setup/
        ( SSH_PORT=$SSH_PORT_WORKER . ./prepare_restricted_shell.sh)

        # restart node sshd
        log "node:restart ssh"
        ssh root@localhost -p $SSH_PORT_WORKER ${SSH_FLAGS:-} -o StrictHostKeyChecking=no -i $(pwd)/../server/server-key-for-tests bash -ls <<-"EOF"
        kill -HUP $(ps aux|grep "/usr/sbin/ssh[d]"|awk {'print $1'})
EOF
        cd -

        # setup manager
        cd setup/
        log "manager:host"
        ( SSH_PORT=$SSH_PORT_SERVER . ./prepare_host.sh )

        log "prepare db:postgres"
        SSH_PORT="$SSH_PORT_SERVER" SSH_USER=root SU=1 prepare_db "localhost"

        log "manager:docker"
        ( SSH_PORT=$SSH_PORT_SERVER . ./prepare_docker.sh >&/dev/null||true )

        log "manager:manager"
        ( SSH_PORT=$SSH_PORT_SERVER . ./prepare_manager.sh )

        log "manager:cli"
        ( SSH_PORT="$SSH_PORT_SERVER" . ./prepare_cli.sh )

        log "manager:secrets"
        ( . ./prepare_secrets.sh )

        log "manager:restricted_shell"
        ( SSH_PORT=$SSH_PORT_SERVER RESTART_SSH=false . ./prepare_restricted_shell.sh )

        log "manager:prepare_acl"
        ( SSH_PORT=$SSH_PORT_SERVER SSH_USER=root . ./prepare_acl.sh )

        log "manager:core_services"
        ( SSH_PORT=$SSH_PORT_SERVER SSH_USER=root . ./prepare_core_services.sh )

        log "manager:futuswarm_container"
        ( SSH_PORT=$SSH_PORT_SERVER SSH_USER=root . ./prepare_futuswarm_container.sh )

        log "manager:futuswarm_health_container"
        ( SSH_PORT=$SSH_PORT_SERVER SSH_USER=root . ./prepare_futuswarm_health_container.sh )

        log "prepare cli for local use"
        cp /tmp/cli /tmp/cli_local
        replaceinfile '/tmp/cli_local' '^SSH_USER=.*' "SSH_USER=client"
        replaceinfile '/tmp/cli_local' '^SSH_KEY=.*' "SSH_KEY=$SSH_KEY"
        replaceinfile '/tmp/cli_local' '^SSH_PORT=.*' "SSH_PORT=$SSH_PORT_SERVER"

        cd -

        log "DONE"
        UP="1"
    fi
}


client() {
local _SSH_USER="${1:-client}"
echo HOST=localhost REMOTE_REGISTRY_PORT=5000 SSH_USER="$_SSH_USER" SSH_KEY="server/server-key-for-tests" SSH_PORT=2222 NODE_LIST=localhost client/cli.sh
}

admin() {
echo bash admin.sh
}
