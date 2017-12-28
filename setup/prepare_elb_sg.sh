#!/usr/bin/env bash
source init.sh

SG_ELB_NAME="${_SG_ELB_NAME:-$SG_ELB_NAME}"
VPC=$(vpc|vpc_id)

ELB_SG=$(sg_elb|sg_id)
rg_status "$ELB_SG" "ELB Security Group '$SG_ELB_NAME' configured ($ELB_SG) "
if [ -z "$ELB_SG" ]; then
    ELB_SG=$(aws ec2 create-security-group --group-name "$SG_ELB_NAME" --description "ELB $SG_ELB_NAME" --vpc-id $VPC|jq -r '.GroupId')
    aws ec2 create-tags --resources $ELB_SG --tags Key=Name,Value="$SG_ELB_NAME" Key=$TAG_KEY,Value=$TAG Key=$PURPOSE_TAG_KEY,Value=$SG_ELB_NAME
    tag_with_futuswarm $ELB_SG
fi

# allow HTTP to ELB
capture_stderr "aws ec2 authorize-security-group-ingress --group-id $ELB_SG --protocol tcp --port 80 --cidr 0.0.0.0/0"|suppress_valid_awscli_errors
# allow HTTPS to ELB
capture_stderr "aws ec2 authorize-security-group-ingress --group-id $ELB_SG --protocol tcp --port 443 --cidr 0.0.0.0/0"|suppress_valid_awscli_errors
