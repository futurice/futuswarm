#!/usr/bin/env bash
source init.sh

# KMS
KMS_KEY_ID=$(kms_key_for_alias "$KMS_ALIAS" "$AWS_REGION")
if [ -z "$KMS_KEY_ID" ]; then
    yellow " creating KMS Key"
    KMS_KEY_ID="$(aws kms create-key --description="$SERVICE_LISTING_KEY" --region="$AWS_REGION"|jq -r '.KeyMetadata|.KeyId')"
    yellow " creating alias $KMS_ALIAS for KMS Key $KMS_KEY_ID in $AWS_REGION"
    aws kms create-alias --alias-name "$KMS_ALIAS" --target-key-id "$KMS_KEY_ID" --region="$AWS_REGION"
fi
KMS_KEY_ARN=$(aws kms describe-key --key-id=$KMS_KEY_ID --region=$AWS_REGION|jq -r '.KeyMetadata.Arn')

# S3 Bucket for Secrets
BUCKET_EXISTS=$(aws s3api list-buckets|jq -r ".Buckets[]|select(.Name==\"$SECRETS_S3_BUCKET\")")
rg_status "$BUCKET_EXISTS" "S3 bucket '$SECRETS_S3_BUCKET' exists"
if [ -z "$BUCKET_EXISTS" ]; then
    aws s3api create-bucket --bucket $SECRETS_S3_BUCKET --region $AWS_REGION --create-bucket-configuration LocationConstraint=$AWS_REGION
fi
aws s3api put-bucket-versioning --bucket $SECRETS_S3_BUCKET --versioning-configuration Status=Enabled --region $AWS_REGION 1>/dev/null

