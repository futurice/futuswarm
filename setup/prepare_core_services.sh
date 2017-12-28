#!/usr/bin/env bash
source init.sh

HOST="${HOST:-$(manager_ip)}"

yellow "Building SSO-proxy image..."
SSO_IMAGE=futurice/sso-proxy
SSO_NAME=sso-proxy
SSO_TAG=$(git rev-parse --short HEAD)

# defaults
cp -R ../proxy /tmp/proxy/
# CONFIG_DIR overrides
if [ -d "$CDIR/proxy/" ]; then
    cp $CDIR/proxy/* /tmp/proxy/
fi

cd /tmp/proxy
docker build -t "$SSO_IMAGE:$SSO_TAG" . 1>/dev/null
cd - 1>/dev/null

cd ../client
yellow "Pushing SSO-proxy docker image to Swarm..."
start_sso_proxy() {
( SU=true \
    . ./cli.sh image:push -i "$SSO_IMAGE" -t "$SSO_TAG" )
}
start_sso_proxy
cd - 1>/dev/null

REMOTE=$(cat <<EOF
docker network create --driver overlay proxy||true
EOF
)
R=$(run_sudo $HOST "$REMOTE")
echo "$R"|grep -v "already exists"

SERVICE_EXISTS="$(does_service_exist $SSO_NAME)"
rg_status "$SERVICE_EXISTS" "'$SSO_NAME' is a Swarm service"

if [[ -n "$SERVICE_EXISTS" ]]; then
yellow " updating '$SSO_NAME' with given tag '$SSO_TAG'"
SSH_ARGS="-t sudo" sudo_client $HOST "docker service update --image $SSO_IMAGE:$SSO_TAG $SSO_NAME --detach"

else

yellow " creating $SSO_NAME service"
REMOTE=$(cat <<EOF
docker service create \
    --name $SSO_NAME \
    -p 80:80 \
    -p 443:443 \
    --network proxy \
    --constraint 'node.role==manager' \
    --detach \
    $SSO_IMAGE:$SSO_TAG
EOF
)
SSH_ARGS="-t sudo" sudo_client $HOST "'$REMOTE'"
fi

SERVICE_EXISTS="$(does_service_exist swarm-listener)"
rg_status "$SERVICE_EXISTS" "Docker Flow Proxy: 'swarm-listener' is a Swarm service"
if [[ -n "$SERVICE_EXISTS" ]]; then
    :
else
yellow " creating DFP:swarm-listener service"
REMOTE=$(cat <<EOF
docker service create --name swarm-listener \
    --network proxy \
    --mount "type=bind,source=/var/run/docker.sock,target=/var/run/docker.sock" \
    -e DF_NOTIFY_CREATE_SERVICE_URL=http://proxy:8080/v1/docker-flow-proxy/reconfigure \
    -e DF_NOTIFY_REMOVE_SERVICE_URL=http://proxy:8080/v1/docker-flow-proxy/remove \
    --constraint 'node.role==manager' \
    --detach \
    vfarcic/docker-flow-swarm-listener
EOF
)
SSH_ARGS="-t sudo" sudo_client "$HOST" "'$REMOTE'"
fi

SERVICE_EXISTS="$(does_service_exist proxy)"
rg_status "$SERVICE_EXISTS" "Docker Flow Proxy: 'proxy' is a Swarm service"
if [[ -n "$SERVICE_EXISTS" ]]; then
    :
else
yellow " creating DFP:proxy service"
REMOTE=$(cat <<EOF
docker service create --name proxy \
    -p 81:80 \
    -p 444:443 \
    --network proxy \
    -e MODE=swarm \
    -e LISTENER_ADDRESS=swarm-listener \
    -e EXTRA_FRONTEND="http-request set-header X-Forwarded-Proto https if { ssl_fc }" \
    -e DEFAULT_PORTS="81,444:ssl" \
    -e TIMEOUT_HTTP_REQUEST=300 \
    --constraint 'node.role==manager' \
    --detach \
    vfarcic/docker-flow-proxy
EOF
)
SSH_ARGS="-t sudo" sudo_client "$HOST" "'$REMOTE'"
fi


