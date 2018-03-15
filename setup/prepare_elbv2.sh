#!/usr/bin/env bash
source init.sh

# ELB -> Proxy
# By default proxy is co-located on Swarm Managers instances
ELB_NAME="${_ELB_NAME:-$ELB_NAME}"
SG_ELB_NAME="${_SG_ELB_NAME:-$SG_ELB_NAME}"
ELB_DOMAIN="${_ELB_DOMAIN:-$ELB_DOMAIN}"

# Certificate
( _ELB_DOMAIN="$ELB_DOMAIN" . ./prepare_acm.sh )

ELB_IP="$(proxy_elbv2 "$ELB_NAME"|proxy_ip)"
rg_status "$ELB_IP" "Elastic Load Balancer (ELB) '$ELB_NAME' is up"

# Security Group
( _SG_ELB_NAME="$SG_ELB_NAME" . ./prepare_elb_sg.sh )

# ELB (public) for proxy instances
if [ -z "$ELB_IP" ]; then
    yellow "Creating ELB '$ELB_NAME'"
    _SUBNETS=$(subnets|jq -r '.Subnets[]|.SubnetId')
    _ELB_DATA="$(aws elbv2 create-load-balancer \
        --name "$ELB_NAME"  \
        --type application \
        --scheme internet-facing \
        --subnets $_SUBNETS \
        --security-groups "$(sg|sg_id)" "$(sg_elb|sg_id)")"
    tag_elbv2_with_futuswarm "$(echo "$_ELB_DATA"|v2elb_arn)"
fi

_ELB_ARN="$(v2elb "$ELB_NAME"|v2elb_arn)"

# target group has listeners
VPC_ID=$(vpc|vpc_id)
yellow "Creating target group '$ELB_NAME'"
aws elbv2 create-target-group --name "$ELB_NAME" \
    --protocol HTTP \
    --port 80 \
    --health-check-path "/status" \
    --health-check-port 80 \
    --vpc-id "$VPC_ID"
_TG_ARN="$(v2elb_target_groups "$ELB_NAME"|v2elb_target_group_arn)"

INSTANCES=$(proxy_instances)
IDS=$(echo $INSTANCES|jq -r '.Reservations[].Instances[].InstanceId')
IDS_FMT=$(python commands.py stdin_to_id_keyed_values <<EOF
$IDS
EOF
)

# add EC2 instances for traffic destination
yellow "Registering targets '$IDS'"
aws elbv2 register-targets --target-group-arn "$_TG_ARN" \
    --targets $IDS_FMT

# listener: HTTP 80
yellow "Creating HTTP listener"
aws elbv2 create-listener --load-balancer-arn "$_ELB_ARN" \
    --protocol HTTP \
    --port 80 \
    --default-actions Type=forward,TargetGroupArn="$_TG_ARN"
# listener: HTTP 443
ACM_ARN="$(acm_arn "$ELB_DOMAIN")"
ACM_CERT="$(acm_cert "$ACM_ARN")"
IS_CERT_ISSUED="$(acm_cert_issued "$ACM_CERT")"
yellow "Creating HTTPS listener (ACM: $ACM_ARN)"
aws elbv2 create-listener --load-balancer-arn "$_ELB_ARN" \
    --protocol HTTPS \
    --port 443 \
    --certificates CertificateArn="$ACM_ARN" \
    --default-actions Type=forward,TargetGroupArn="$_TG_ARN"
