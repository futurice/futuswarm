#!/usr/bin/env bash
source init.sh

# REX-Ray container storage orchestration -- https://rexray.thecodeteam.com/
# NOTES:
# - requires all instances to exist on same subnet for EBS volumes (default configuration) to work
# - installing same version gives dpkg errors
# - installs latest available version by default

rexray_version_num() {
echo "${1:-$REXRAY_VERSION}"|sed 's~\.~~g'
}

_SKIP_REXCONF="${SKIP_REXCONF:-}"
IS_RUNNING=$(run_sudo $HOST "is_running rexray")
IS_INSTALLED=$(run_sudo $HOST "is_installed rexray")
UPGRADE_REXRAY="${UPGRADE_REXRAY:-no}"
FORCE_RESTART="${FORCE_RESTART:-no}"
NAME="REX-Ray"

if [ "$_SKIP_REXCONF" == "" ]; then
prepare_rexray_config
fi

install_rexray() {
REMOTE=$(cat <<-"EOF"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -qq -o=Dpkg::Use-Pty=0 -y nfs-common
curl -sSL https://dl.bintray.com/emccode/rexray/install|sh -
EOF
)
run_sudo $HOST "$REMOTE"||true
synchronize "$(rexray_config_file)" /etc/rexray/$REXRAY_CONFIG $HOST
}

restart_rexray() {
REMOTE=$(cat <<EOF
service rexray restart
EOF
)
run_sudo $HOST "$REMOTE"
}

REMOTE=$(cat <<-"EOF"
dpkg -l|grep rexray|awk '{print $3}'|cut -d- -f1
EOF
)
REXRAY_DAEMON_VERSION=$(run_sudo $HOST "$REMOTE")

rg_status "$IS_INSTALLED" "$HOST: $NAME '$REXRAY_DAEMON_VERSION' is installed"
rg_status "$IS_RUNNING" "$HOST: $NAME is running"
if [[ "$IS_INSTALLED" == "yes" ]]; then
    if [[ "$IS_RUNNING" == "yes" ]]; then
        :
    else
        restart_rexray
    fi
else
    yellow "$HOST: Installing $NAME '$REXRAY_VERSION'..."
    install_rexray
    yellow "$HOST: Restarting $NAME..."
    restart_rexray
fi

# force?
if [[ "$FORCE_RESTART" == "yes" ]]; then
    yellow "$HOST: Restarting $NAME..."
    restart_rexray
fi

# upgrade
if [[ "$UPGRADE_REXRAY" == "yes" ]]; then
    if [ "$(rexray_version_num "$REXRAY_DAEMON_VERSION")" -ge "$(rexray_version_num "$REXRAY_VERSION")" ]; then
        yellow "$HOST: Already running '$REXRAY_DAEMON_VERSION' >= "$REXRAY_VERSION"..."
    else
        yellow "$HOST: Upgrading $NAME '$REXRAY_DAEMON_VERSION' to '$REXRAY_VERSION'..."
        install_rexray
        yellow "$HOST: Restarting $NAME..."
        restart_rexray
    fi
fi

