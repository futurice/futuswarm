#!/usr/bin/env bash

###
### Global configuration
### - unique naming of resources
###

TAG=test

#
# AWS
#

AWS_PROFILE="${AWS_PROFILE:=}"
AWS_REGION=eu-west-1
AWS_DNS=169.254.169.253
IAM_USER=$TAG

#
# Secrets
# - https://github.com/futurice/secret
#

KMS_ALIAS="alias/$TAG"
SECRETS_S3_BUCKET="com.futuswarm.$TAG.secrets"
SECRETS_REGION="$AWS_REGION"
POLICY_FILE=user_policy.json
SERVICE_LISTING_KEY=$TAG-swarm-services

#
# ACL
#

ACL_DB_NAME=futuswarm

#
# ELB
# ACM SSL certificate
#

DOMAIN=$TAG.futurice.com
ELB_DOMAIN="*.$TAG.futurice.com"
OPEN_DOMAIN=

#
# DOCKER
# - COMPANY -- Docker image namespace (eg. company/container-name)
#

COMPANY=futurice
DOCKER_CONTAINER_PORT=8000
DOCKER_VERSION="${DOCKER_VERSION:-18.01.0~ce-0~ubuntu}"

#
# AMI
# - Ubuntu AMI lookup https://cloud-images.ubuntu.com/locator/ec2/
#

AMI=ami-37940d58
BLOCKDEVICE=/dev/sda1
BLOCKDEVICE_SIZE=20
BLOCKDEVICE_VOLUME_TYPE=gp2
EC2_KEY_PAIR=$TAG
EC2_SUBNET_STRATEGY=static
EC2_SUBNET_AS=eu-central-1a

#
# SSH
#

SSH_USER=root
SSH_KEYS_HOME="../server"
SSH_KEY="$SSH_KEYS_HOME/server-key-for-tests"
SSH_KEY_PUB="$SSH_KEYS_HOME/server-key-for-tests.pub"
ADMIN_LIST="$SSH_USER"
CLI_NAME=${CLOUD}swarm

#
# VPC
# - Subnet CIDRs need to be within VPC_CIDR
#

VPC_CIDR=""
SUBNETS_DATA="172.16.12.0/24,eu-west-1a 172.16.13.0/24,eu-west-1b 172.16.14.0/24,eu-west-1c"
SUBNETS_TOTAL=3

#
# Docker Swarm
#

SWARM_NODES=$(cat <<EOF
{
"managers": [
{"type":"m4.large", "count": 1, "blockdevice": {"size": 100}}
],
"workers": [
{"type":"m4.large", "count": 2, "blockdevice": {"size": 100}}
]
}
EOF
)
SWARM_NODE_LABEL_KEY=swarm-label
SWARM_S3_BUCKET="com.futurice.futuswarm.$TAG.files"
CORE_CONTAINERS="proxy swarm-listener futuswarm futuswarm-health sso-proxy"
DOCKER_REGISTRY_PORT=5000

#
# TAGS
# - key/value identifiers for AWS resource lookups
#

TAG_KEY=cloud
PURPOSE_TAG_KEY=purpose-$TAG

ELB_NAME=$TAG-elb

SG_NAME=$TAG-sg
SG_ELB_NAME=$TAG-sg-elb
SG_RDS_NAME=$TAG-sg-rds

SUBNET_TAG_VALUE=$TAG-subnet

SWARM_ROLE_KEY=$TAG-swarm-role
SWARM_TAG_VALUE=$TAG-swarm
SWARM_MANAGER_VALUE=manager
SWARM_NODE_VALUE=node

#
# RDS
#

RDS_NAME=$TAG-db
RDS_INSTANCE=db.t2.medium
RDS_STORAGE=10
RDS_STORAGE_TYPE=gp2
RDS_ENGINE=postgres
RDS_ENGINE_VERSION=9.6.1
RDS_PREFERRED_MAINTENANCE_PERIOD="mon:01:00-mon:01:30"
RDS_PREFERRED_BACKUP_WINDOW="00:00-00:30"
RDS_SUBNET_GROUP_NAME=$TAG
RDS_DB_NAME=db
RDS_PORT=5433

#
# ElastiCache
#

EC_ENGINE=redis
EC_NAME=$TAG-$EC_ENGINE
EC_AZ_MODE=single
EC_CACHE_NODES=1
EC_CACHE_NODE_TYPE=cache.t2.micro
EC_ENGINE_VERSION=3.2.4
EC_PREFERRED_MAINTENANCE_PERIOD="mon:03:00-mon:06:30"
EC_PORT=6379
EC_SUBNET_GROUP_NAME=$TAG
EC_SUBNET_GROUP_DESCRIPTION="$EC_NAME"
EC_HOST=""
