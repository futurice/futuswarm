#!/usr/bin/env bash
source init.sh

# ubuntu 16.04
# https://docs.docker.com/engine/installation/linux/ubuntu/
IS_INSTALLED=$(run_sudo $HOST "is_installed docker")
IS_RUNNING=$(run_sudo $HOST "is_running docker")
DOCKER_DAEMON_VERSION=$(run_sudo $HOST "docker_daemon_version")
UPGRADE_DOCKER="${UPGRADE_DOCKER:-no}"
FORCE_RESTART="${FORCE_RESTART:-no}"
NAME="Docker"

install_docker() {
REMOTE=$(cat <<-"EOF"
export DEBIAN_FRONTEND=noninteractive
apt-get -qq update
apt-get -qq -y install \
    linux-image-extra-$(uname -r) \
    linux-image-extra-virtual &>/dev/null
apt-get -qq -y install apt-transport-https \
                        curl \
                        ca-certificates \
                        software-properties-common 1>/dev/null
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add - 1>/dev/null
apt-key fingerprint 0EBFCD88 1>/dev/null
add-apt-repository \
       "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
       $(lsb_release -cs) \
       stable" 1>/dev/null
add-apt-repository \
       "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
       $(lsb_release -cs) \
       edge" 1>/dev/null
apt-get update -qq
apt-cache madison docker-ce 1>/dev/null
EOF
)
run_sudo $HOST "$REMOTE"

REMOTE=$(cat <<EOF
apt-get -qq -y install docker-ce=$DOCKER_VERSION
EOF
)
run_sudo $HOST "$REMOTE"
}

restart_docker() {
# enable experimental features
SERVICE_CMD="ExecStart=/usr/bin/dockerd -H fd:// --experimental"
REMOTE=$(cat <<EOF
/etc/init.d/docker stop 1>/dev/null
replaceinfile '/lib/systemd/system/docker.service' '^ExecStart=.*' "$SERVICE_CMD"
systemctl daemon-reload||echo 'systemd not running or misconfigured'
/etc/init.d/docker restart 1>/dev/null
EOF
)
run_sudo $HOST "$REMOTE"
}


rg_status "$IS_INSTALLED" "$HOST: $NAME '$DOCKER_DAEMON_VERSION' is installed"
rg_status "$IS_RUNNING" "$HOST: $NAME is running"
if [[ "$IS_INSTALLED" == "yes" ]]; then
    if [[ "$IS_RUNNING" == "yes" ]]; then
        :
    else
        restart_docker
    fi
else
    yellow "$HOST: Installing $NAME '$DOCKER_VERSION'..."
    install_docker
    yellow "$HOST: Restarting $NAME..."
    restart_docker
fi

# force?
if [[ "$FORCE_RESTART" == "yes" ]]; then
    yellow "$HOST: Restarting $NAME..."
    restart_docker
fi

# upgrade
if [[ "$UPGRADE_DOCKER" == "yes" ]]; then
    if [ $(docker_version_num "$DOCKER_DAEMON_VERSION") -ge $(docker_version_num "$DOCKER_VERSION") ]; then
        yellow "$HOST: Already running '$DOCKER_DAEMON_VERSION' >= '$DOCKER_VERSION'..."
    else
        yellow "$HOST: Upgrading $NAME '$DOCKER_DAEMON_VERSION' to '$DOCKER_VERSION'..."
        install_docker
        yellow "$HOST: Restarting $NAME..."
        restart_docker
    fi
fi

