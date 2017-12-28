#!/usr/bin/env bash
source init.sh

AWS_USER_ARN=$(aws iam get-user --user-name=$IAM_USER|jq -r '.User.Arn')
if [ -z "$AWS_USER_ARN" ]; then
    yellow " creating user $IAM_USER"
    AWS_USER_ARN=$(aws iam create-user --user-name=$IAM_USER|jq -r '.User.Arn')
fi

R=$(aws iam list-access-keys --user-name=$IAM_USER|jq '.AccessKeyMetadata[]|select(.Status=="Active")')
if [ -z "$R" ]; then
    yellow " creating IAM access keys for $IAM_USER"
    CREDENTIALS="$(aws iam create-access-key --user-name=$IAM_USER)"
    red " store these AWS access keys for $IAM_USER"
    echo "$CREDENTIALS">.credentials.${IAM_USER}
    echo "$CREDENTIALS"
fi

KMS_KEY_ID=$(kms_key_for_alias "$KMS_ALIAS" "$AWS_REGION")
if [ -z "$KMS_KEY_ID" ]; then
    yellow " creating KMS Key"
    KMS_KEY_ID="$(aws kms create-key --description="$SERVICE_LISTING_KEY" --region="$AWS_REGION"|jq -r '.KeyMetadata|.KeyId')"
    yellow " creating alias $KMS_ALIAS for KMS Key $KMS_KEY_ID in $AWS_REGION"
    aws kms create-alias --alias-name "$KMS_ALIAS" --target-key-id "$KMS_KEY_ID" --region="$AWS_REGION"
fi

KMS_KEY_ARN=$(aws kms describe-key --key-id=$KMS_KEY_ID --region=$AWS_REGION|jq -r '.KeyMetadata.Arn')

BUCKET_EXISTS=$(aws s3api list-buckets|jq -r ".Buckets[]|select(.Name==\"$SECRETS_S3_BUCKET\")")
rg_status "$BUCKET_EXISTS" "S3 bucket '$SECRETS_S3_BUCKET' exists"
if [ -z "$BUCKET_EXISTS" ]; then
    aws s3api create-bucket --bucket $SECRETS_S3_BUCKET --region $AWS_REGION --create-bucket-configuration LocationConstraint=$AWS_REGION
fi
aws s3api put-bucket-versioning --bucket $SECRETS_S3_BUCKET --versioning-configuration Status=Enabled --region $AWS_REGION 1>/dev/null

# ACL for IAM_USER
cp $POLICY_FILE /tmp/
replaceinfile /tmp/$POLICY_FILE 'AWS_USER_ARN' "$AWS_USER_ARN"
replaceinfile /tmp/$POLICY_FILE 'SECRETS_S3_BUCKET' "$SECRETS_S3_BUCKET"
replaceinfile /tmp/$POLICY_FILE 'SWARM_S3_BUCKET' "$SWARM_S3_BUCKET"
aws iam put-user-policy --user-name $IAM_USER --policy-name SwarmPolicy --policy-document file:///tmp/$POLICY_FILE

