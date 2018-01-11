#!/usr/bin/env bash
source init.sh

# Prepare CLI for end users
cp ../client/cli.sh /tmp/cli
rm -f /tmp/.futuswarm_cli_version

HOST="${HOST:-$(manager_ip)}"
UPLOAD="${UPLOAD:-y}"

replaceinfile '/tmp/cli' '^HOST=.*' "HOST=$HOST"
replaceinfile '/tmp/cli' '^CONTAINER_PORT=.*' "CONTAINER_PORT=$DOCKER_CONTAINER_PORT"
replaceinfile '/tmp/cli' '^COMPANY=.*' "COMPANY=$COMPANY"
replaceinfile '/tmp/cli' '^OPEN_DOMAIN=.*' "OPEN_DOMAIN=$OPEN_DOMAIN"
replaceinfile '/tmp/cli' '^DOCKER_REGISTRY_PORT=.*' "DOCKER_REGISTRY_PORT=$DOCKER_REGISTRY_PORT"

python - <<PEOF
CS=open('commands.sh').read().replace('#!/usr/bin/env bash','')
import commands;commands.replace_block('/tmp/cli','commands',CS);
PEOF

_CV="$(cli_version)"
replaceinfile '/tmp/cli' '^CLI_VERSION=.*' "CLI_VERSION=$_CV"

if [ "$UPLOAD" == "y" ]; then
    synchronize /tmp/cli /opt/ $HOST

    BUCKET_EXISTS=$(aws s3api list-buckets|jq ".Buckets[]|select(.Name==\"$SWARM_S3_BUCKET\")")
    rg_status "$BUCKET_EXISTS" "S3 bucket '$SWARM_S3_BUCKET' exists"
    if [ -z "$BUCKET_EXISTS" ]; then
        aws s3api create-bucket --bucket $SWARM_S3_BUCKET --region $AWS_REGION --create-bucket-configuration LocationConstraint=$AWS_REGION
    fi
    aws s3api put-object --bucket $SWARM_S3_BUCKET --key cli --body /tmp/cli --grant-read uri=http://acs.amazonaws.com/groups/global/AllUsers 1>/dev/null
else
    yellow "Skipping CLI upload to Manager '$HOST' and S3 '$(cli_location)'"
fi
