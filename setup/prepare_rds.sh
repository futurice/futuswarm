#!/usr/bin/env bash
source init.sh

# RDS DB Subnet Group + EC2 VPC + RDS Instance

RDS_USER="${RDS_USER:-}"
RDS_PASS="${RDS_PASS:-}"

if [ -z "$RDS_USER" ] || [ -z "$RDS_PASS" ] || [ -z "$HOST" ]; then
    red "RDS_USER/RDS_PASS/HOST unset"
    exit 1
fi

SUBNET_IDS=$(echo $(subnets|jq -r '.Subnets[].SubnetId'))
_RDS_SUBNET_GROUPS=$(aws rds describe-db-subnet-groups)
_RDS_SUBNET_GROUP=$(echo "$_RDS_SUBNET_GROUPS"|jq -r ".DBSubnetGroups|map(select(.DBSubnetGroupName==\"$RDS_SUBNET_GROUP_NAME\"))|first // empty")
rg_status "$_RDS_SUBNET_GROUP" "RDS subnet group found ($RDS_SUBNET_GROUP_NAME)"
if [ -z "$_RDS_SUBNET_GROUP" ]; then
_RDS_SUBNET_GROUP=$(aws rds create-db-subnet-group --db-subnet-group-name $RDS_SUBNET_GROUP_NAME \
          --db-subnet-group-description $TAG \
          --subnet-ids $SUBNET_IDS \
          --tags Key=Name,Value=$TAG)
fi

VPC_ID=$(vpc|vpc_id)
EC2_SG_ID=$(sg|sg_id)
RDS_SG_ID=$(sg_rds|sg_id)
rg_status "$RDS_SG_ID" "RDS Security Group configured ($RDS_SG_ID)"
if [ -z "$RDS_SG_ID" ]; then
    RDS_SG_ID=$(aws ec2 create-security-group --group-name $SG_RDS_NAME --description "RDS $TAG" --vpc-id $VPC_ID|jq -r '.GroupId')
    aws ec2 create-tags --resources $RDS_SG_ID --tags Key=Name,Value=$SG_RDS_NAME Key=$TAG_KEY,Value=$TAG Key=$PURPOSE_TAG_KEY,Value=$SG_RDS_NAME
    tag_with_futuswarm $RDS_SG_ID
fi
# Allow EC2_SG to use RDS
capture_stderr "aws ec2 authorize-security-group-ingress --group-id $RDS_SG_ID --protocol tcp --port 5432 --source-group $EC2_SG_ID"|suppress_valid_awscli_errors

_RDS_INSTANCES=$(aws rds describe-db-instances)
_RDS_INSTANCE=$(echo "$_RDS_INSTANCES"|jq -r ".DBInstances|map(select(.DBInstanceIdentifier==\"$RDS_NAME\"))|first // empty")
rg_status "$_RDS_INSTANCE" "RDS instance found ($RDS_NAME)"
if [ -z "$_RDS_INSTANCE" ]; then
_RDS_INSTANCE=$(aws rds create-db-instance --db-instance-identifier $RDS_NAME \
    --allocated-storage $RDS_STORAGE \
    --db-instance-class $RDS_INSTANCE \
    --engine $RDS_ENGINE \
    --engine-version $RDS_ENGINE_VERSION \
    --storage-type $RDS_STORAGE_TYPE \
    --db-subnet-group-name $RDS_SUBNET_GROUP_NAME \
    --vpc-security-group-ids $RDS_SG_ID \
    --tags Key=Name,Value=$TAG \
    --preferred-maintenance-window $RDS_PREFERRED_MAINTENANCE_PERIOD \
    --preferred-backup-window $RDS_PREFERRED_BACKUP_WINDOW \
    --master-username "$RDS_USER" \
    --master-user-password "$RDS_PASS")

wait_for condition_rds_up "$RDS_NAME" "Waiting for RDS '$RDS_NAME' to come online (takes several minutes)" 20
fi

RDS_HOSTNAME="$(rds_db_host $RDS_NAME)"
R=$(run_sudo "$HOST" "pg_isready -h $RDS_HOSTNAME -p $RDS_PORT")
rg_status "$(exit_code_ok $? 0)" "$RDS_HOSTNAME:$RDS_PORT - RDS accepting connections"

prepare_db "$HOST"
