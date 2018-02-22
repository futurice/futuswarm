#!/usr/bin/env bash
source init.sh

NAME="$1"

if [ -z "$NAME" ]; then
    red "NAME unset"
    safe_exit 1
fi

SUBNET_IDS=$(echo $(subnets|jq -r '.Subnets[].SubnetId'))
_EC_SUBNET_GROUPS=$(aws elasticache describe-cache-subnet-groups)
_EC_SUBNET_GROUP=$(echo "$_EC_SUBNET_GROUPS"|jq -r ".CacheSubnetGroups|map(select(.CacheSubnetGroupName==\"$EC_SUBNET_GROUP_NAME\"))|first // empty")
rg_status "$_EC_SUBNET_GROUP" "ElastiCache subnet group found ($EC_SUBNET_GROUP_NAME)"
if [ -z "$_EC_SUBNET_GROUP" ]; then
_EC_SUBNET_GROUP=$(aws elasticache create-cache-subnet-group --cache-subnet-group-name $EC_SUBNET_GROUP_NAME \
    --cache-subnet-group-description $EC_SUBNET_GROUP_DESCRIPTION \
    --subnet-ids $SUBNET_IDS)
fi

EC2_SG_ID=$(sg|sg_id)

_EC_INSTANCES=$(elasticache_clusters)
_EC_INSTANCE=$(echo "$_EC_INSTANCES"|jq -r ".CacheClusters|map(select(.CacheClusterId==\"$NAME\"))|first // empty")
rg_status "$_EC_INSTANCE" "ElastiCache instance found ($NAME)"
if [ -z "$_EC_INSTANCE" ]; then
_EC_INSTANCE=$(aws elasticache create-cache-cluster --cache-cluster-id $NAME \
        --az-mode $EC_AZ_MODE \
        --num-cache-nodes $EC_CACHE_NODES \
        --cache-node-type $EC_CACHE_NODE_TYPE \
        --engine $EC_ENGINE \
        --engine-version $EC_ENGINE_VERSION \
        --security-group-ids $EC2_SG_ID \
        --cache-subnet-group-name $EC_SUBNET_GROUP_NAME \
        --tags Key=Name,Value=$TAG \
        --preferred-maintenance-window $EC_PREFERRED_MAINTENANCE_PERIOD \
        --port $EC_PORT)
fi

