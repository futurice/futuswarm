#!/usr/bin/env bash

swarm_instances() {
    aws ec2 describe-instances --filter Name=tag:$PURPOSE_TAG_KEY,Values=$SWARM_TAG_VALUE Name="instance-state-name",Values="running"
}

swarm_manager_instances() {
    aws ec2 describe-instances --filter Name=tag:$PURPOSE_TAG_KEY,Values=$SWARM_TAG_VALUE Name=tag:$SWARM_ROLE_KEY,Values=$SWARM_MANAGER_VALUE Name="instance-state-name",Values="running"
}

swarm_node_instances() {
    aws ec2 describe-instances --filter Name=tag:$PURPOSE_TAG_KEY,Values=$SWARM_TAG_VALUE Name=tag:$SWARM_ROLE_KEY,Values=$SWARM_NODE_VALUE Name="instance-state-name",Values="running"
}

proxy_instances() {
    aws ec2 describe-instances --filter Name=tag:$SWARM_ROLE_KEY,Values=$SWARM_MANAGER_VALUE Name="instance-state-name",Values="running"
}

# 1: name
proxy_elb() {
    elbs|jq '.LoadBalancerDescriptions'|jq "map(select(.LoadBalancerName==\"$1\"))|first // empty"
}

proxy_elbv2() {
    v2elbs|jq '.LoadBalancers'|jq "map(select(.LoadBalancerName==\"$1\"))|first // empty"
}

proxy_ip() {
    echo $(stdin)|jq -r '.DNSName'
}

prepare_host() {
    INSTANCES=$(instances)
    for id in ${IDS[@]}; do
        HOST=$(echo $INSTANCES|jq -r ".Reservations[].Instances[]|select(.InstanceId==\"$id\")|.PublicIpAddress")
        HOST=$HOST instance_prepare
    done
}

exit_on_aws_error() {
if [[ $? -ne 0 ]]; then
    red "Error communicating with AWS. Try again shortly."
    safe_exit 1
fi
}

create_swarm_instances() {
local SWARM_ROLE="$1"
if [[ "$SWARM_ROLE" == "manager" ]]; then
    local INSTANCES="$(swarm_manager_instances)"
    local SWARM_ROLE_VALUE="$SWARM_MANAGER_VALUE"
    exit_on_aws_error
elif [[ "$SWARM_ROLE" == "worker" ]]; then
    local INSTANCES="$(swarm_node_instances)"
    local SWARM_ROLE_VALUE="$SWARM_NODE_VALUE"
    exit_on_aws_error
else
    red "SWARM_ROLE is either manager/worker"
    safe_exit 1
fi

# cache
local SUBNETS=$(subnets)

# go thru all managers/workers
while IFS= read -r row; do
    create_swarm_instance "${row}" &
done < <(echo "$SWARM_NODES"|jq -r -c ".${SWARM_ROLE}s[]|@base64")
wait $(jobs -p)

}

create_swarm_instance() {
    local NODES=$(echo ${1}|b64dec)
    _jq() {
        echo "$NODES"|jq -r "$1"
    }
    local SWARM_ROLE="$SWARM_ROLE"
    local SUBNET=$(_jq '.subnet // empty')
    if [[ -z "$SUBNET" ]]; then
        SUBNET="$EC2_SUBNET_AS"
    fi
    local LABEL=$(_jq '.label // empty')
    local INSTANCE_TYPE=$(_jq '.type')
    local CLUSTER_SIZE=$(_jq '.count')
    local BLOCKDEVICE_SIZE=$(_jq '.blockdevice.size')
    local IDS=$(echo "$INSTANCES"|jq ".Reservations[]|.Instances[]|select(.Tags[].Key==\"$SWARM_NODE_LABEL_KEY\" and .Tags[].Value==\"$LABEL\")"|jq -r '.InstanceId')

    local IDS_COUNT=$(countCharsIn "$IDS" "-")
    if [ $IDS_COUNT -gt $CLUSTER_SIZE ]; then
        red "ERROR: More instances running than specified (role=$SWARM_ROLE,label=$LABEL) -- check https://console.aws.amazon.com/ec2/"
        exit 1
    fi
    test $IDS_COUNT -eq $CLUSTER_SIZE
    rg_status "$(exit_code_ok $?)" "($IDS_COUNT/$CLUSTER_SIZE) EC2 instances created (role=$SWARM_ROLE, label=$LABEL)"

    node_post_create() {
        for id in ${IDS[@]}; do
            aws ec2 create-tags --resources $id --tags Key=$SWARM_ROLE_KEY,Value=$SWARM_ROLE_VALUE Key=$PURPOSE_TAG_KEY,Value=$SWARM_TAG_VALUE Key=$SWARM_NODE_LABEL_KEY,Value="$LABEL"
        done
        sleep 1
        prepare_host
    }

    create_aws_instances "$SWARM_TAG_VALUE" 'node_post_create'
}

configure_swarm_nodes() {
( SU=true \
    . ./cli.sh admin:node:default_tags )
}

