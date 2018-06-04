#!/usr/bin/env bash
source init.sh

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
HOST="${HOST:-$(manager_ip)}"
FORCE="${FORCE:-false}"

# Prepare "Hello World" container
mk_virtualenv
source_virtualenv

# health
FS_HEALTH="futuswarm-health"
SERVICE_EXISTS="$(does_service_exist $FS_HEALTH)"
rg_status "$SERVICE_EXISTS" "'$FS_HEALTH' is a Swarm service"
if [[ -n "$SERVICE_EXISTS" ]]; then
    :
else
rm -rf /tmp/$FS_HEALTH
# defaults
cp -R $FUTUSWARM_HEALTH_DIR /tmp/$FS_HEALTH
cd /tmp/$FS_HEALTH
git init . 1>/dev/null
git add -A 1>/dev/null
git commit -am "-.-" 1>/dev/null
TAG=$(git rev-parse --short HEAD)
docker build -t $FS_HEALTH:$TAG . 1> /dev/null
cd - 1>/dev/null

push_image $FS_HEALTH $TAG

yellow " creating $FS_HEALTH"
FMT_LOG_OPTS="${LOG_OPTS//__NAME__/$FS_HEALTH}"
REMOTE=$(cat <<EOF
docker service create --name $FS_HEALTH \
    --network proxy \
    --endpoint-mode dnsrr \
    --constraint 'node.role==manager' \
    --detach=false \
    $FMT_LOG_OPTS \
    $FS_HEALTH:$TAG
EOF
)
SSH_ARGS="-t sudo" sudo_client "$HOST" "'$REMOTE'"
fi

cd "$SCRIPT_DIR"

deactivate_virtualenv
