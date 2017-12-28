#!/usr/bin/env bash

rem_quote() {
    # remove quotes
    echo $(stdin)|tr -d '"'
}

nl2space() {
    # newline to space
    echo $(stdin)|tr '\n' ' '
}

tag_with_futuswarm() {
    aws ec2 create-tags --resources $1 --tags Key=futuswarm,Value=$CLOUD
}

tag_elb_with_futuswarm() {
    aws elb add-tags --load-balancer-names $1 --tags Key=futuswarm,Value=$CLOUD
}

ec2_ids() {
    echo $(stdin)|jq -r '.Reservations[].Instances[].InstanceId'
}

vpc() {
    aws ec2 describe-vpcs --filter Name=tag:$TAG_KEY,Values=$TAG
}

vpc_id() {
    echo $(stdin)|jq '.Vpcs[].VpcId'|rem_quote
}

vpcs() {
    aws ec2 describe-vpcs
}

vpc_peerings() {
    aws ec2 describe-vpc-peering-connections
}

# 1: from-vpc-id
# 2: to-vpc-id
vpc_peering_from_to() {
vpc_peerings|jq -r ".VpcPeeringConnections[]|select(.AccepterVpcInfo.VpcId==\"$2\" and .RequesterVpcInfo.VpcId==\"$1\")|.VpcPeeringConnectionId"
}

# 1: vpc-id
get_vpc() {
    VPCS="${VPCS:=$(vpcs)}"
    echo "$VPCS"|jq ".Vpcs[]|select(.VpcId==\"$1\")"
}

ig() {
    aws ec2 describe-internet-gateways --filter Name=tag:$TAG_KEY,Values=$TAG
}

ig_id() {
    echo $(stdin)|jq '.InternetGateways[].InternetGatewayId'|rem_quote
}

subnets() {
    aws ec2 describe-subnets --filter Name=tag:$PURPOSE_TAG_KEY,Values=$SUBNET_TAG_VALUE
}

subnet_in_az() {
    SUBNETS="${SUBNETS:=$(subnets)}"
    echo "$SUBNETS"|jq ".Subnets[]|select(.AvailabilityZone==\"$1\")"
}

SUBNET_COUNTER=0
next_subnet_id() {
    SUBNETS=${SUBNETS:=$(subnets)}
    ID=$SUBNET_COUNTER
    SUBNET_COUNTER=$(($SUBNET_COUNTER+1))
    if [ "$ID" -gt "$((SUBNETS_TOTAL-1))" ]; then
        ID=0
    fi
    echo $SUBNETS|jq -r "[.Subnets[].SubnetId][$ID]"
}

keypair() {
    aws ec2 describe-key-pairs --filter Name=key-name,Values=$EC2_KEY_PAIR
}

keypair_name() {
    echo $(stdin)|jq '.KeyPairs[].KeyName'|rem_quote
}

iam_certs() {
    aws iam list-server-certificates
}

iam_cert() {
    iam_certs|jq ".ServerCertificateMetadataList[]|select(.ServerCertificateName==\"$IAM_SERVER_CERTIFICATE_NAME\")"
}

iam_cert_arn() {
    iam_cert|jq -r '.Arn // empty'
}

sg() {
    aws ec2 describe-security-groups --filter Name=tag:$TAG_KEY,Values=$TAG --filter Name=tag:$PURPOSE_TAG_KEY,Values="$SG_NAME"
}

sg_by_name() {
    aws ec2 describe-security-groups --filter Name=tag:Name,Values=$1
}

sg_by_tag() {
    aws ec2 describe-security-groups --filter Name=tag:$1,Values=$2
}

sg_elb() {
    aws ec2 describe-security-groups --filter Name=tag:$TAG_KEY,Values=$TAG --filter Name=tag:$PURPOSE_TAG_KEY,Values="$SG_ELB_NAME"
}

sg_rds() {
    aws ec2 describe-security-groups --filter Name=tag:$TAG_KEY,Values=$TAG --filter Name=tag:$PURPOSE_TAG_KEY,Values="$SG_RDS_NAME"
}

sg_id() {
    echo $(stdin)|jq -r '.SecurityGroups[].GroupId'
}

routetables() {
    aws ec2 describe-route-tables
}

# 1: vpc_id
routetable_for_vpc() {
    ROUTETABLES=${ROUTETABLES:=$(routetables)}
    echo "$ROUTETABLES"|jq ".RouteTables[]|select(.VpcId==\"$1\")"
}

# routetable VpcId
routetable() {
    aws ec2 describe-route-tables --filter Name=vpc-id,Values=$1
}
routetable_id() {
    echo $(stdin)|jq '.RouteTables[].RouteTableId'|rem_quote
}

ec2_instances() {
    aws ec2 describe-instances
}

ec2_instance_by_name() {
    aws ec2 describe-instances --filter Name=tag:Name,Values=$1
}

instances() {
    aws ec2 describe-instances --filter Name=tag:$TAG_KEY,Values=$TAG
}

instances_running() {
    aws ec2 describe-instances --filter Name=tag:$TAG_KEY,Values=$TAG Name="instance-state-name",Values="running"
}

instances_count() {
    instances|jq '.Reservations[].Instances|length'|paste -sd+ -|bc
}

instance_ids() {
    echo $(stdin)|ec2_ids
}

instance_statuses() {
    local IDS=$(instances|instance_ids|nl2space)
    aws ec2 describe-instance-status --instance-ids $IDS
}

elbs() {
    aws elb describe-load-balancers
}

elb() {
    aws elb describe-load-balancers --load-balancer-names "$1"
}

jq_elb_dnsname() {
    echo $(stdin)|jq -r '.LoadBalancerDescriptions|first|.DNSName'
}

ec2_ips() {
    echo $(stdin)|jq -r '[.Reservations[].Instances[]|[.PublicIpAddress,.PrivateIpAddress]]'
}

SUBNET_COUNTER=0
get_next_subnet() {
    if [ "$SUBNET_COUNTER" -eq "${#SUBNET_IDS[@]}" ]; then
        SUBNET_COUNTER=0
    fi
    echo ${SUBNET_IDS[$SUBNET_COUNTER]}
    SUBNET_COUNTER=$(($SUBNET_COUNTER+1))
}

# node index
# - uses global $CLUSTER variable
node() {
    echo $CLUSTER|jq -r ".[$1]|@csv"|nl2space|sed 's/"//g'
}
# public_ip index
public_ip() {
    echo $(node $1)|cut -f$(($1+1)) -d' '|cut -f1 -d,
}
# private_ip index
private_ip() {
    echo $(node $1)|cut -f$(($1+1)) -d' '|cut -f2 -d,
}

post_create() {
    echo "No post_create fn defined, skipping..."
}

# generate_instances NAME (POST_CREATE_FUNCTION)
generate_instances() {
    NAME="$1"
    yellow "Creating ($COUNT) EC2 instance(s): instance-type='$INSTANCE_TYPE' label='$LABEL' role='$SWARM_ROLE'"
    IDS=$(aws ec2 run-instances --image-id $AMI \
        --count $COUNT \
        --instance-type $INSTANCE_TYPE \
        --key-name $EC2_KEY_PAIR \
        --security-group-ids $(sg|sg_id) \
        --subnet-id $SUBNET_ID \
        --block-device-mappings "DeviceName=$BLOCKDEVICE,Ebs={VolumeSize=$BLOCKDEVICE_SIZE,VolumeType=$BLOCKDEVICE_VOLUME_TYPE}" \
        --associate-public-ip-address|jq -r '.Instances[].InstanceId'| tr '\n' ' ')
    echo " Initialized: $IDS"

    on_instance_creation

    ${2:-post_create}
}

instance_prepare() {
    ( HOST=$HOST SSH_FLAGS="-o LogLevel=quiet" . ./prepare_host.sh )
}

ec2_running() {
    local IDS="$(echo $1|jq -r '.ids')"
    local COUNT="$(echo $1|jq -r '.count')"
    local R=$(aws ec2 describe-instance-status --instance-ids $IDS)
    local STATUS=$(echo "$R"|jq -r -c -M '.InstanceStatuses[].InstanceState.Name')
    local STATUS_ONELINE="$(echo $STATUS|nl2space)"
    local CUR_STATE=$(echo $STATUS|sed 's/[[:space:]]//g')
    local REQ_STATE="$(replicate_str running "$COUNT")"
    echo "$IDS: Waiting to reach 'running' state -- [ $STATUS_ONELINE]" > $WAIT_FOR_FILE
    [[ "$CUR_STATE" == "$REQ_STATE" ]]
}

ec2_healthy() {
    local IDS="$(echo $1|jq -r '.ids')"
    local COUNT="$(echo $1|jq -r '.count')"
    local R=$(aws ec2 describe-instance-status --instance-ids $IDS)
    local STATUS=$(echo "$R"|jq -r -c -M '.InstanceStatuses[]|(.SystemStatus.Status,.InstanceStatus.Status)')
    local STATUS_ONELINE="$(echo $STATUS|nl2space)"
    local CUR_STATE=$(echo $STATUS|sed 's/[[:space:]]//g')
    local REQ_STATE="$(replicate_str okok "$COUNT")"
    echo "$IDS: Health checks (takes a few mins) -- [ $STATUS_ONELINE]" > $WAIT_FOR_FILE
    [[ "$CUR_STATE" == "$REQ_STATE" ]]
}

on_instance_creation() {
    for id in ${IDS[@]}; do
        aws ec2 create-tags --resources $id --tags Key=Name,Value=$NAME Key=$TAG_KEY,Value=$TAG
        sleep .2
    done

    # NOTE: using wait_for as 'aws .. wait' sometimes errors or timeouts
    local M='{"ids":"'$IDS'","count":"'$COUNT'"}'
    wait_for ec2_running "$M" "$IDS: Waiting to reach 'running' state" 15
    wait_for ec2_healthy "$M" "$IDS: Health checks (takes a few mins)" 15

    sleep 1
}

# 1: numericID
subnet_strategy() {
    if [[ "$EC2_SUBNET_STRATEGY" == "static" ]]; then
        echo $(echo $(subnet_in_az "$SUBNET")|jq -r '.SubnetId')
    elif [[ "$EC2_SUBNET_STRATEGY" == "static-random" ]]; then
        echo $(next_subnet_id)
    elif [[ "$EC2_SUBNET_STRATEGY" == "circular" ]]; then
        echo $(next_subnet_id)
    else
        red "unknown subnet strategy"
        safe_exit 1
    fi
}

# INSTANCE_TYPE=X
# CLUSTER_SIZE=X
# create_aws_instances NAME POST_CREATE_FN
# - name is also PURPOSE_TAG_KEY's value
create_aws_instances() {
    local IDS_COUNT=$(countCharsIn "$IDS" "-")
    local TOTAL=$(($CLUSTER_SIZE-$IDS_COUNT))
    local _NAME="$1"
    local _FN=${2:-'post_create'}
    if [ "$IDS_COUNT" -ne "$CLUSTER_SIZE" ]; then
        local COUNT=$TOTAL
        local SUBNET_ID=$(subnet_strategy)
        generate_instances "$_NAME" "$_FN" &
        wait $(jobs -p)
    fi
}

aws_dns() {
    # AWS DNS is 169.254.169.253 or base of VPC range +2
    IPNUM=$(($(echo $VPC_CIDR|cut -f4 -d/)+2))
    IPNUM=$(echo $VPC_CIDR|cut -f1 -d/|cut -f1,2,3 -d.|awk -v x="$IPNUM" '{print $1"."x}')
    if [ ! -z "$AWS_DNS" ]; then
        echo $AWS_DNS
    else
        echo $IPNUM
    fi
}

node_list() {
    swarm_instances|jq -r ".Reservations[].Instances[]|.PublicIpAddress"
}

# 1:alias 2:region
kms_key_for_alias() {
    local ALIASES=$(aws kms list-aliases --region="$2")
    echo $(echo $ALIASES|jq -r ".Aliases[]|select(.AliasName==\"$1\")|.TargetKeyId")
}

# 1:alias 2:region
kms_arn_for_alias() {
    KMS_KEY_ID=$(kms_key_for_alias "$1" "$2")
    aws kms describe-key --key-id=$KMS_KEY_ID
    local ALIASES=$(aws kms list-aliases --region="$2")
    echo $(echo $ALIASES|jq -r ".Aliases[]|select(.AliasName==\"$1\")|.TargetKeyId")
}

rds_db_host() {
    _R=$(aws rds describe-db-instances --db-instance-identifier="$1")
    if [[ "$?" -ne 0 ]]; then
        echo -n "$_R" 1>&2
        safe_exit 1
    else
        echo $_R|jq -r '.DBInstances|first|.Endpoint.Address'
    fi
}

elasticache_clusters() {
    aws elasticache describe-cache-clusters --show-cache-node-info
}

elasticache_cluster() {
    aws elasticache describe-cache-clusters --cache-cluster-id=$1 --show-cache-node-info
}

jq_elasticache_node_address() {
    echo $(stdin)|jq -r '.CacheClusters|first|.CacheNodes|first|.Endpoint.Address'
}

mk_swarm_map() {
I=$(instances)
D=""
for ip in ${NODE_LIST[@]}; do
R=$(run_sudo $ip <<EOF
docker info --format '{{json .}}'|jq -r '.Name'
EOF
)
D+="$ip,$R "
done
echo "$D"|sed 's/.$//'
}

manager_ip() {
SWARM_MANAGER_LIST="$(swarm_manager_instances|jq -r '.Reservations[].Instances[]|.PublicIpAddress')"
FST_MAN_SERVER="$(echo $SWARM_MANAGER_LIST|cut -f1 -d' ')"
FST_MAN_PUBLIC="$(echo $FST_MAN_SERVER|cut -f1 -d,)"
echo "$FST_MAN_PUBLIC"
}

# 1: host
prepare_db() {
# create master database, under which schemas are created and restrict public-schema creation
local _RDS_HOST="${RDS_HOST:-$(rds_db_host $RDS_NAME)}"
REMOTE=$(cat <<EOF
PGPASSWORD="$RDS_PASS" psql -h "$_RDS_HOST" -p "$RDS_PORT" -U "$RDS_USER" postgres -c "create database $RDS_DB_NAME";
PGPASSWORD="$RDS_PASS" psql -h "$_RDS_HOST" -p "$RDS_PORT" -U "$RDS_USER" postgres -c "REVOKE CREATE ON SCHEMA public FROM PUBLIC;"
EOF
)
R=$(run_sudo "$1" "$REMOTE" 2>&1)
}

REXRAY_CONFIG=rexray.yml
rexray_config_file() {
echo "/tmp/$REXRAY_CONFIG"
}
prepare_rexray_config() {
local F="$(rexray_config_file)"
cp $REXRAY_CONFIG $F
replaceinfile $F 'AWS_KEY' "$AWS_KEY"
replaceinfile $F 'AWS_SECRET' "$AWS_SECRET"
replaceinfile $F 'SECURITY_GROUPS' "$SECURITY_GROUPS"
replaceinfile $F 'AWS_REGION' "$AWS_REGION"
}

get_sg_tag() {
echo $(stdin)|jq -r ".SecurityGroups[].Tags[]|select(.Key==\"$1\")|.Value // empty"
}
