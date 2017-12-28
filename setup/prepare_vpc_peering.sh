#!/usr/bin/env bash
source init.sh

FROM_VPC="${FROM_VPC:=$(vpc|vpc_id)}"
TO_VPC="$TO_VPC"

# VPC peering
PEERING_ID=$(vpc_peering_from_to $FROM_VPC $TO_VPC)
rg_status "$PEERING_ID" "VPC peering between $FROM_VPC <> $TO_VPC configured"
if [ -z "$PEERING_ID" ]; then
    R=$(aws ec2 create-vpc-peering-connection --vpc-id $FROM_VPC --peer-vpc-id $TO_VPC)
    PEERING_ID=$(echo $R|jq -r '.VpcPeeringConnection.VpcPeeringConnectionId')
    aws ec2 create-tags --resources $PEERING_ID --tags Key=Name,Value=$TAG Key=$TAG_KEY,Value=$TAG
    tag_with_futuswarm $PEERING_ID
    # TODO: VPC needs to be in same AWS account; prefix AWS_PROFILE=$AWS_PROFILE_TO_VPC
    aws ec2 accept-vpc-peering-connection --vpc-peering-connection-id "$PEERING_ID"
fi

# VPC Peering route tables
FROM_RT="${FROM_RT:=$(routetable_for_vpc $FROM_VPC|jq -r .'RouteTableId')}"
TO_RT="${TO_RT:=$(routetable_for_vpc $TO_VPC|jq -r .'RouteTableId')}"

FROM_VPC_CIDR=$(get_vpc $FROM_VPC|jq -r '.CidrBlock')
TO_VPC_CIDR=$(get_vpc $TO_VPC|jq -r '.CidrBlock')
capture_stderr "aws ec2 create-route --route-table-id $FROM_RT --destination-cidr-block $TO_VPC_CIDR --vpc-peering-connection-id $PEERING_ID"|suppress_valid_awscli_errors
capture_stderr "aws ec2 create-route --route-table-id $TO_RT --destination-cidr-block $FROM_VPC_CIDR --vpc-peering-connection-id $PEERING_ID"|suppress_valid_awscli_errors

# SG: SG in TO_VPC allowing connections from FROM_VPC's SG
# TODO: TO_VPC needs to be in same AWS account; prefix AWS_PROFILE=$AWS_PROFILE_TO_VPC
SG=$(sg_by_name $SG_FOR_VPC_PEERING_NAME|sg_id)
rg_status "$SG" "EC2 Security Group for VPC peered resources configured ($SG_FOR_VPC_PEERING_NAME)"
if [ -z "$SG" ]; then
    SG=$(aws ec2 create-security-group --group-name $SG_FOR_VPC_PEERING_NAME --description "EC2 VPC Peering resources" --vpc-id $TO_VPC|jq -r '.GroupId')
    aws ec2 create-tags --resources $SG --tags Key=Name,Value=$SG_FOR_VPC_PEERING_NAME Key=$TAG_KEY,Value=$TAG
    tag_with_futuswarm $SG
fi
# SG: Allow LDAP: 389, 636
SOURCE_SG="${SOURCE_SG:=$(sg|sg_id)}"
capture_stderr "aws ec2 authorize-security-group-ingress --group-id $SG --protocol tcp --port 389 --source-group $SOURCE_SG"|suppress_valid_awscli_errors
capture_stderr "aws ec2 authorize-security-group-ingress --group-id $SG --protocol tcp --port 636 --source-group $SOURCE_SG"|suppress_valid_awscli_errors
