#!/usr/bin/env bash
source init.sh

AWS_USER_ARN=$(aws iam get-user --user-name="$IAM_USER"|jq -r '.User.Arn')
if [ -z "$AWS_USER_ARN" ]; then
    yellow " creating user $IAM_USER"
    AWS_USER_ARN=$(aws iam create-user --user-name="$IAM_USER"|jq -r '.User.Arn')
fi

R=$(aws iam list-access-keys --user-name="$IAM_USER"|jq '.AccessKeyMetadata[]|select(.Status=="Active")')
if [ -z "$R" ]; then
    yellow " creating IAM access keys for $IAM_USER"
    CREDENTIALS="$(aws iam create-access-key --user-name="$IAM_USER")"
    echo "$CREDENTIALS">$(credentials_file)
    red "✘ STORE SAFELY: $(credentials_file) contains AWS credentials for $IAM_USER. Use these as --aws-key and --aws-secret in further install.sh runs."
fi

# policy: kms, s3
cp $POLICY_FILE /tmp/
replaceinfile /tmp/$POLICY_FILE 'AWS_USER_ARN' "$AWS_USER_ARN"
replaceinfile /tmp/$POLICY_FILE 'SECRETS_S3_BUCKET' "$SECRETS_S3_BUCKET"
replaceinfile /tmp/$POLICY_FILE 'SWARM_S3_BUCKET' "$SWARM_S3_BUCKET"
aws iam put-user-policy --user-name "$IAM_USER" --policy-name SwarmPolicy --policy-document file:///tmp/$POLICY_FILE

# policy: cloudtwatch
cp cloudwatch_policy.json /tmp/
aws iam put-user-policy --user-name "$IAM_USER" --policy-name CloudWatch --policy-document file:///tmp/cloudwatch_policy.json

# policy: rexray
cp rexray_policy.json /tmp/
aws iam put-user-policy --user-name "$IAM_USER" --policy-name RexRay --policy-document file:///tmp/rexray_policy.json

echo -e
