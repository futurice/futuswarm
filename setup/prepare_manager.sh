#!/usr/bin/env bash
source init.sh

H="/root"

# awscli, secret
REMOTE=$(cat <<EOF
pip install -q secret==0.8
pip install -q boto3==1.7.19

mkdir -p $H/.secret
echo """
[default]
vault=$SECRETS_S3_BUCKET
vaultkey=$KMS_ALIAS
region=$SECRETS_REGION
""" > $H/.secret/credentials

EOF
)
run_sudo $HOST "$REMOTE"

# Registry

if [ $(docker_version_num) -lt 1709 ]; then
REMOTE="docker login -u $REGISTRY_USER -p '$REGISTRY_PASS'"
else
REMOTE=$(cat <<EOF
docker login -u $REGISTRY_USER --password-stdin <<< '$REGISTRY_PASS'
EOF
)
fi
R=$(run_sudo $HOST "$REMOTE")
rg_status "$(exit_code_ok $? 0)" "Docker private registry access configured for '$REGISTRY_USER'"

R=$(run_user $HOST <<< "[[ -a '/root/.docker/config.json' ]]")
rg_status "$(exit_code_ok $? 0)" "Docker configuration file exists"

R=$(run_user $HOST <<< "cat /root/.docker/config.json|jq -r '.auths.\"https://index.docker.io/v1/\".auth // empty'")
rg_status "$R" "Token for Docker Hub created successfully"
