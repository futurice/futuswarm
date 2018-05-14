#!/usr/bin/env bash
source init.sh

# Initial configuration for EC2 instances on creation

if [ "$APT_FORCE_IPV4" == "true" ]; then
REMOTE=$(cat <<-"EOF"
echo 'Acquire::ForceIPv4 "true";'|tee /etc/apt/apt.conf.d/99force-ipv4
EOF
)
run_sudo $HOST "$REMOTE"
fi

REMOTE=$(cat <<EOF
export DEBIAN_FRONTEND=noninteractive
apt-get -qq update
apt-get -qq install -o=Dpkg::Use-Pty=0 -y ca-certificates curl dnsutils iputils-ping unzip rsync jq bc ntp postgresql-client bsdmainutils 1>/dev/null

apt-get -qq install -y python python-pip
pip install -q setuptools==39.0.1 pip==10.0.1 awscli==1.15.19 dateparser==0.7.0

EOF
)
run_sudo $HOST "$REMOTE"

synchronize commands.sh /opt/ $HOST
synchronize commands.py /opt/ $HOST
