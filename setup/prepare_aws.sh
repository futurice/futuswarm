#!/usr/bin/env bash
# Prepare AWS Resources For Swarm Cluster
# VPC: Internet Gateway + Route Table + Subnets, EC2: Key Pair + Security Group + FireWall
source init.sh

# ACM
CERTS=$(aws acm list-certificates --region=$AWS_REGION)
CERT_EXISTS=$(echo "$CERTS"|jq -r ".CertificateSummaryList|map(select(.DomainName==\"$ELB_DOMAIN\"))|first // empty")
rg_status "$CERT_EXISTS" "ACM SSL certificate exists ($ELB_DOMAIN)"
if [ -z "$CERT_EXISTS" ]; then
read -p "Make ACM SSL Certificate request? [y/n]" -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]
then
    aws acm request-certificate --domain-name "$ELB_DOMAIN" --idempotency-token "$(echo DOMAIN|tr -d .)" --region="$AWS_REGION"
fi
fi

# VPC
VPC=$(vpc|vpc_id)
rg_status "$VPC" "VPC exists ($VPC)"
if [ -z "$VPC" ]; then
    VPC=$(aws ec2 create-vpc --cidr-block $VPC_CIDR --region=$AWS_REGION|jq -r '.Vpc.VpcId')
    aws ec2 create-tags --resources $VPC --tags Key=Name,Value=$TAG Key=$TAG_KEY,Value=$TAG
    tag_with_futuswarm $VPC
    aws ec2 modify-vpc-attribute --vpc-id $VPC --enable-dns-hostnames
fi

# Internet Gateway
IG=$(ig|ig_id)
rg_status "$IG" "VPC Internet Gateway configured ($IG)"
if [ -z "$IG" ]; then
    IG=$(aws ec2 create-internet-gateway|jq -r '.InternetGateway.InternetGatewayId')
    aws ec2 create-tags --resources $IG --tags Key=Name,Value=$TAG Key=$TAG_KEY,Value=$TAG
    tag_with_futuswarm $IG
fi

# Attach IG to VPC
capture_stderr "aws ec2 attach-internet-gateway --internet-gateway-id $IG --vpc-id $VPC"|suppress_valid_awscli_errors

# Route Table (automatically created for VPC)
RT=$(routetable $VPC|routetable_id)
rg_status "$RT" "VPC Route Table configured ($RT)"
capture_as_stderr "aws ec2 create-route --route-table-id $RT --destination-cidr-block 0.0.0.0/0 --gateway-id $IG"|suppress_valid_awscli_errors
# TODO: only modify Name on RT when no Name exists yet, to allow using an existing VPC setup without disruption
# capture_stderr "aws ec2 create-tags --resources $RT --tags Key=Name,Value=$TAG"|suppress_valid_awscli_errors
capture_stderr "aws ec2 create-tags --resources $RT --tags Key=$TAG_KEY,Value=$TAG"|suppress_valid_awscli_errors
tag_with_futuswarm $RT

# Subnets for VPC
# - unique AZ
# - unique CIDR
SUBNETS_AVAILABLE=$(subnets)
function Pcidr {
    echo $SUBNETS_DATA|cut -f$(($1+1)) -d' '|cut -f1 -d,
}
function Paz {
    echo $SUBNETS_DATA|cut -f$(($1+1)) -d' '|cut -f2 -d,
}
for k in $(seq 0 $(($SUBNETS_TOTAL-1))); do
    # TODO: Match CidrBlock rather than AvailabilityZone
    SUBNET_EXISTS=$(echo $SUBNETS_AVAILABLE|jq ".Subnets[]|select(.AvailabilityZone==\"$(Paz $k)\")")
    rg_status "$SUBNET_EXISTS" "VPC subnet $k: $(Pcidr $k) $(Paz $k) configured"
    if [ -z "$SUBNET_EXISTS" ]; then
        yellow " preparing subnet $k: $(Pcidr $k) $(Paz $k)"
        SUBNET=$(aws ec2 create-subnet --vpc-id $VPC --cidr-block $(Pcidr $k) --availability-zone $(Paz $k)|jq -r '.Subnet.SubnetId')
        aws ec2 modify-subnet-attribute --subnet-id $SUBNET --map-public-ip-on-launch
        aws ec2 create-tags --resources $SUBNET --tags Key=Name,Value="$TAG-$(Paz $k)" Key=$TAG_KEY,Value=$TAG
        tag_with_futuswarm $SUBNET
    fi
done

# EC2 Key Pair
# - SSH keys
KEYPAIR=$(keypair|keypair_name)
rg_status "$KEYPAIR" "EC2 Key Pair found ($KEYPAIR)"
if [ -z "$KEYPAIR" ]; then
    red "An existing EC2 Key Pair (name: $EC2_KEY_PAIR) was not found, generating one for you..."
    openssl genrsa -out $TAG.pem 2048
    openssl rsa -in $TAG.pem -pubout > $TAG.pub
    aws ec2 import-key-pair --key-name $TAG --public-key-material "`cat $TAG.pub|sed '$ d'|sed 1d|tr -d '\n'`"
    chmod 0600 $TAG.pem

    # move created keys to default location
    mkdir -p "${SSH_KEYS_HOME}"
    mv "$TAG.pem" "${SSH_KEYS_HOME}/"
    mv "$TAG.pub" "${SSH_KEYS_HOME}/"
    red "Move $TAG.pem and $TAG.pub (from $SSH_KEYS_HOME) to your storage of choice for safekeeping"
fi

# Security Groups

## Private network, only inbound SSH access
SG=$(sg|sg_id)
rg_status "$SG" "EC2 Security Group configured ($SG)"
if [ -z "$SG" ]; then
    SG=$(aws ec2 create-security-group --group-name $TAG --description "EC2 $TAG" --vpc-id $VPC|jq -r '.GroupId')
    aws ec2 create-tags --resources $SG --tags Key=Name,Value=$TAG Key=$TAG_KEY,Value=$TAG Key=$PURPOSE_TAG_KEY,Value=$SG_NAME Key=ssh-automation,Value=on
    tag_with_futuswarm $SG
fi

# Allow all connections within SG
capture_stderr "aws ec2 authorize-security-group-ingress --group-id $SG --protocol all --port all --source-group $SG"|suppress_valid_awscli_errors

if [ "$(sg|get_sg_tag ssh-automation)" == "on" ]; then
    # Allow SSH from everywhere
    capture_stderr "aws ec2 authorize-security-group-ingress --group-id $SG --protocol tcp --port 22 --cidr 0.0.0.0/0"|suppress_valid_awscli_errors
else
    red "SG '$SG' rules for SSH remain untouched as tag 'ssh-automation=on' is not set"
fi

## Public network, access via ELB
( _SG_ELB_NAME="$SG_ELB_NAME" . ./prepare_elb_sg.sh )
