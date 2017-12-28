#!/usr/bin/env bash
source init.sh

# Initial configuration for EC2 instances on creation

REMOTE=$(cat <<EOF
export DEBIAN_FRONTEND=noninteractive
apt-get -qq update
apt-get -qq install -y ca-certificates curl dnsutils iputils-ping unzip rsync jq bc ntp postgresql-client bsdmainutils 1>/dev/null
EOF
)
run_sudo $HOST "$REMOTE"

synchronize commands.sh /opt/ $HOST
synchronize commands.py /opt/ $HOST
