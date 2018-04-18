#!/usr/bin/env bash
source init.sh

H="/root"
# aws
REMOTE=$(cat <<EOF
export DEBIAN_FRONTEND=noninteractive
apt-get -qq update
apt-get -qq install -y python python-pip

pip install -q setuptools pip awscli==1.14.1

mkdir -p $H/.aws
echo """
[default]
aws_access_key_id = $AWS_KEY
aws_secret_access_key = $AWS_SECRET
""" > $H/.aws/credentials

echo """
[default]
output = json
region = $AWS_REGION
""" > $H/.aws/config
EOF
)
run_sudo $HOST "$REMOTE"
