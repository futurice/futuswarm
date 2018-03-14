#!/usr/bin/env bash
source init.sh

# ELB -> Proxy
# By default proxy is co-located on Swarm Managers instances
ELB_NAME="${_ELB_NAME:-$ELB_NAME}"
SG_ELB_NAME="${_SG_ELB_NAME:-$SG_ELB_NAME}"
ELB_DOMAIN="${_ELB_DOMAIN:-$ELB_DOMAIN}"

INSTANCES=$(proxy_instances)
PROXY_IP="$(proxy_elb "$ELB_NAME"|proxy_ip)"
rg_status "$PROXY_IP" "Elastic Load Balancer (ELB) '$ELB_NAME' is up"

# Security Group
( _SG_ELB_NAME="$SG_ELB_NAME" . ./prepare_elb_sg.sh )

# ELB (public) for proxy instances
# - health check /status
# - ports 80, 443
if [ -z "$PROXY_IP" ]; then
    yellow " creating"
    SUBNETS=$(echo $INSTANCES|jq -r '.Reservations[].Instances[].SubnetId')
    ELB_DATA=$(aws elb create-load-balancer --load-balancer-name $ELB_NAME --listeners "Protocol=HTTP,LoadBalancerPort=80,InstanceProtocol=HTTP,InstancePort=80" --security-groups $(sg|sg_id) --subnets $SUBNETS)
    ELB=$(echo $ELB_DATA|jq -r '.DNSName')
    tag_elb_with_futuswarm "$ELB_NAME"
fi
aws elb apply-security-groups-to-load-balancer --security-groups "$(sg|sg_id)" "$(sg_elb|sg_id)" --load-balancer-name $ELB_NAME 1>/dev/null
aws elb configure-health-check --load-balancer-name $ELB_NAME --health-check Target=HTTP:80/status,Interval=30,UnhealthyThreshold=2,HealthyThreshold=2,Timeout=3 1>/dev/null

IDS=$(echo $INSTANCES|jq -r '.Reservations[].Instances[].InstanceId'|tr '\n' ' ')
aws elb register-instances-with-load-balancer --load-balancer-name $ELB_NAME --instances $IDS 1>/dev/null

ACM_ARN="$(acm_arn "$ELB_DOMAIN")"
ACM_CERT="$(acm_cert "$ACM_ARN")"
IS_CERT_ISSUED="$(acm_cert_issued "$ACM_CERT")"

if [[ -n "$IS_CERT_ISSUED" ]]; then
    aws elb create-load-balancer-listeners --load-balancer-name $ELB_NAME \
        --listeners "Protocol=HTTP,LoadBalancerPort=80,InstanceProtocol=HTTP,InstancePort=80" "Protocol=HTTPS,LoadBalancerPort=443,InstanceProtocol=HTTP,InstancePort=80,SSLCertificateId=$ACM_ARN" 1>/dev/null
    aws elb set-load-balancer-listener-ssl-certificate --load-balancer-name $ELB_NAME --load-balancer-port 443 --ssl-certificate-id "$ACM_ARN"
else
    red 'Could not fully setup load balancer due non-issued certificate! Check https://console.aws.amazon.com/acm/'
fi

check_reachable "$PROXY_IP" 80
check_reachable "$PROXY_IP" 443
