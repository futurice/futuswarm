#!/usr/bin/env bash
source init.sh

ELB_DOMAIN="${_ELB_DOMAIN:-$ELB_DOMAIN}"

# Use AWS ACM. Terminate SSL at ELB.
# http://docs.aws.amazon.com/elasticloadbalancing/latest/classic/elb-update-ssl-cert.html
ELB_DOMAIN_MILD="$(domain_mild "$ELB_DOMAIN")"
ACM_CERT_EXISTS="$(acm_cert_exists "$ELB_DOMAIN")"
ACM_ARN="$(acm_arn "$ELB_DOMAIN")"
rg_status "$ACM_CERT_EXISTS" "Amazon Certificate Manager: SSL certificate for ($ELB_DOMAIN_MILD, $ELB_DOMAIN) has been requested"
if [ -z "$ACM_CERT_EXISTS" ]; then
    red " requesting certificate (check email to confirm request)"
    ACM_ARN=$(aws acm request-certificate --domain-name "$ELB_DOMAIN_MILD" --subject-alternative-names "$ELB_DOMAIN"|jq -r '.CertificateArn')
fi

ACM_ARN="$(acm_arn "$ELB_DOMAIN")"
ACM_CERT="$(acm_cert "$ACM_ARN")"
CERT_STATUS="$(acm_cert_status "$ACM_CERT")"
IS_CERT_ISSUED="$(acm_cert_issued "$ACM_CERT")"
rg_status "$IS_CERT_ISSUED" "Certificate issued for '$ELB_DOMAIN' (status: $CERT_STATUS)"
