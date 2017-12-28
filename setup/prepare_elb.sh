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

# Use AWS ACM. Terminate SSL at ELB.
# http://docs.aws.amazon.com/elasticloadbalancing/latest/classic/elb-update-ssl-cert.html
ELB_DOMAIN_MILD="${ELB_DOMAIN/\*./}"
ACM_CERTS="$(aws acm list-certificates)"
ACM_CERT_EXISTS="$(echo $ACM_CERTS|jq -r ".CertificateSummaryList[]|select(.DomainName==\"$ELB_DOMAIN_MILD\")")"
ACM_ARN="$(echo $ACM_CERT_EXISTS|jq -r '.CertificateArn')"
rg_status "$ACM_CERT_EXISTS" "Amazon Certificate Manager: SSL certificate for ($ELB_DOMAIN_MILD, $ELB_DOMAIN) has been requested"
if [ -z "$ACM_CERT_EXISTS" ]; then
    yellow " requesting certificate (check email to confirm request)"
ACM_ARN=$(aws acm request-certificate --domain-name "$ELB_DOMAIN_MILD" --subject-alternative-names "$ELB_DOMAIN"|jq -r '.CertificateArn')
fi

ACM_CERT="$(aws acm describe-certificate --certificate-arn "$ACM_ARN")"
CERT_STATUS="$(echo $ACM_CERT|jq -r '.Certificate.Status')"
IS_CERT_ISSUED="$(if [[ "$CERT_STATUS" == "ISSUED" ]]; then echo "ok"; else echo ""; fi)"
rg_status "$IS_CERT_ISSUED" "Certificate issued for '$ELB_DOMAIN' (status: $CERT_STATUS)"

if [[ -n "$IS_CERT_ISSUED" ]]; then
aws elb create-load-balancer-listeners --load-balancer-name $ELB_NAME \
    --listeners "Protocol=HTTP,LoadBalancerPort=80,InstanceProtocol=HTTP,InstancePort=80" "Protocol=HTTPS,LoadBalancerPort=443,InstanceProtocol=HTTP,InstancePort=80,SSLCertificateId=$ACM_ARN" 1>/dev/null
aws elb set-load-balancer-listener-ssl-certificate --load-balancer-name $ELB_NAME --load-balancer-port 443 --ssl-certificate-id "$ACM_ARN"
else
    red 'Could not fully setup load balancer due non-issued certificate! Check https://console.aws.amazon.com/acm/'
fi

check_reachable "$PROXY_IP" 80
check_reachable "$PROXY_IP" 443
