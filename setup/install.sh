#!/usr/bin/env bash
RUN_ID="$RANDOM"
source init.sh

die() {
    local _ret=$2
    test -n "$_ret" || _ret=1
    test "$_PRINT_HELP" = yes && print_help >&2
    echo "$1" >&2
    exit ${_ret}
}

print_help() {
printf 'Usage: %s COMMAND [--name APP] [ARGUMENTS]\n' "$0"
printf "\t%s\n" " "
printf "\t%s\n" "Arguments:"
printf "\t%s\n" "--aws-key: (optional, created on install) access_key_id of deployment user"
printf "\t%s\n" "--aws-secret: (optional, created on install) secret_access_key of deployment user"
printf "\t%s\n" "--vault-pass: (optional) Vault password for acquiring Ansible secrets"
printf "\t%s\n" "--registry-user: Docker Hub username"
printf "\t%s\n" "--registry-pass: Docker Hub password"
printf "\t%s\n" "--force-new-cluster: (optional) Destroy existing Swarm and create a new one"
printf "\t%s\n" "--use-sssd: (optional) use SSSD (default: false)"
printf "\t%s\n" "--cloudwatch-logs [true/false]: (optional) use CloudWatch logs (default: true)"
printf "\t%s\n" "-h,--help: Prints help"
}

arg_required() {
    if test "$1" = "$2"; then
        test $# -lt 3 && die "Missing value for '$2'." 1
        echo "$3"
        shift
    else
        echo "$1"
    fi
}

_arg_aws_key=
_arg_aws_secret=
_arg_vault_pass=
_arg_registry_user=
_arg_registry_pass=
_arg_force_new_cluster=
_arg_use_sssd=
_arg_cloudwatch_logs=true

while test $# -gt 0; do
    _key="$1"
    case "$_key" in
           --aws-key|--aws-key=*)
            _arg_aws_key=$(arg_required "${_key##--aws-key=}" $1 "${2:-}") || die
        ;; --aws-secret|--aws-secret=*)
            _arg_aws_secret=$(arg_required "${_key##--aws-secret=}" $1 "${2:-}") || die
        ;; --vault-pass|--vault-pass=*)
            _arg_vault_pass=$(arg_required "${_key##--vault-pass=}" $1 "${2:-}") || die
        ;; --registry-user|--registry-user=*)
            _arg_registry_user=$(arg_required "${_key##--registry-user=}" $1 "${2:-}") || die
        ;; --registry-pass|--registry-pass=*)
            _arg_registry_pass=$(arg_required "${_key##--registry-pass=}" $1 "${2:-}") || die
        ;; --force-new-cluster|--force-new-cluster=*)
            _arg_force_new_cluster="1"
        ;; --use-sssd)
            _arg_use_sssd=true
        ;; --cloudwatch-logs|--cloudwatch-logs=*)
            _arg_cloudwatch_logs=$(arg_required "${_key##--cloudwatch-logs=}" $1 "${2:-}") || die
            # TODO: assert true|false given as input
        ;; -h|--help)
            print_help
            exit 0
        ;; *)
            _positionals+=("$1")
        ;;
    esac
    shift
done

exit_on_undefined "$_arg_vault_pass" "--vault-pass"
exit_on_undefined "$_arg_vault_pass" "--registry-user"
exit_on_undefined "$_arg_vault_pass" "--registry-pass"

check_env() {

R=$(command -v docker||true)
rg_status "$R" "Docker installed" "https://docs.docker.com/engine/installation/"

R=$(command -v python||true)
rg_status "$R" "Python installed" "brew install python / apt-get install python"

if [[ -n "$_arg_use_sssd" ]]; then
R=$(ssh -T git@github.com > /dev/null 2>&1)
rg_status "$(exit_code_ok $? 1)" "GitHub user configured"
fi

R=$(command -v aws||true)
rg_status "$R" "AWS CLI installed" "-> pip install awscli (requires Python)"

R=$(command -v jq||true)
rg_status "$R" "jq installed" "-> brew install jq / apt-get install jq"

R=$(cat ~/.aws/credentials|cat ~/.aws/credentials|grep -a2 $AWS_PROFILE|grep aws_access_key_id)
rg_status "$R" "AWS credentials configured" "-> See installation.md"
}

WELCOME=$(cat <<EOF

~
~ futuswarm installer
~ All AWS resources are created once, tagged for ID and then modified according to your "CLOUD=$CLOUD" settings.
~ All created AWS resources remain safely intact between installer re-runs.
~
EOF
)
green "$WELCOME"
echo ""
yellow "Using Settings: $CDIR"
yellow "Check local configuration..."
check_env

# Cleanup slate from possible previous installations
# - virtualenv: dependencies might be old, or an aborted installation left virtualenv in zombie state
rm -rf venv/

yellow "Checking IAM user '$IAM_USER' existence"
AWS_USER_ARN=$(aws iam get-user --user-name="$IAM_USER"|jq -r '.User.Arn')
if [ -n "$AWS_USER_ARN" ]; then
    AWS_USER_KEYS=$(aws iam list-access-keys --user-name="$IAM_USER"|jq '.AccessKeyMetadata[]|select(.Status=="Active")')
    if [ -n "$AWS_USER_KEYS" ]; then
        echo "IAM user '$IAM_USER' exists, checking that --aws-key and --aws-secret are provided"
        exit_on_undefined "$_arg_aws_key" "--aws-key"
        exit_on_undefined "$_arg_aws_secret" "--aws-secret"
    fi
fi

yellow "Checking EC2 KeyPair existence"
KEYPAIR="$(keypair)"
KEYPAIR_NAME="$(echo "$KEYPAIR"|keypair_name)"
if [ -n "$KEYPAIR_NAME" ]; then
    echo "Checking RSA keys for EC2 KeyPair exist locally..."
    if [ ! -f "$SSH_KEY" ]; then
        red "EC2 instances have already been created, but root SSH key is missing locally"
        red "Place the private RSA key matching the EC2 KeyPair '$EC2_KEY_PAIR' to '$SSH_KEY' before proceeding"
        exit 1
    else
        yellow "Checking RSA key fingerprint matches EC2 KeyPair..."
        KEYPAIR_FINGERPRINT="$(echo "$KEYPAIR"|jq -r '.KeyPairs[]|select(.KeyName="app")|.KeyFingerprint')"
        if [ "$(aws_keypair_fingerprint)" == "$KEYPAIR_FINGERPRINT" ]; then
            :
        else
            red "EC2 KeyPair fingerprint '$KEYPAIR_FINGERPRINT' does not match '$SSH_KEY' fingerprint '$(aws_keypair_fingerprint)'"
            exit 1
        fi
    fi
fi

yellow "Checking AWS_PROFILE region matches $CLOUD/settings AWS_REGION '$AWS_REGION'"
VPC_PROFILE=$(vpc|vpc_id)
VPC_FUTUSWARM=$(aws ec2 describe-vpcs --filter Name=tag:$TAG_KEY,Values=$TAG --region=$AWS_REGION|vpc_id)
if [ "$VPC_FUTUSWARM" == "$VPC_PROFILE" ]; then
    :
else
    red "AWS region for AWS_PROFILE does not match settings '$AWS_REGION'"
    exit 1
fi

yellow "Prepare AWS resources..."
( . ./prepare_aws.sh )

# ensure SSH_KEY is available
add_ssh_key_to_agent "$SSH_KEY"

# AWS_KEY/SECRET used to allow tests to work without install.sh
NODE_LIST="$(node_list)"
AWS_KEY="$_arg_aws_key"
AWS_SECRET="$_arg_aws_secret"
SECURITY_GROUPS="$TAG"
VAULT_PASS="$_arg_vault_pass"
REGISTRY_USER="$_arg_registry_user"
REGISTRY_PASS="$_arg_registry_pass"

yellow "Create EC2 instances for Swarm..."
create_swarm_instances manager &
create_swarm_instances worker &
wait $(jobs -p)

NODE_LIST="$(node_list)"

if [[ -n "$NODE_LIST" ]]; then
    yellow "Checking instance connectivity health"
    for ip in ${NODE_LIST[@]}; do
        node_access_health "$ip" &
    done
    wait $(jobs -p)
fi

yellow "Update host basics..."
for ip in ${NODE_LIST[@]}; do
    ( HOST="$ip" . ./prepare_host.sh ) &
done
wait $(jobs -p)

yellow "Prepare Elastic Load Balancer (ELB)..."
( . ./prepare_elbv2.sh )

yellow "Create AWS user..."
( . ./prepare_aws_user.sh )

yellow "Configure AWS credentials..."
for ip in ${NODE_LIST[@]}; do
    ( HOST="$ip" . ./prepare_aws_credentials.sh ) &
done
wait $(jobs -p)

yellow "Install Docker '$DOCKER_VERSION' on all Swarm instances..."
for ip in ${NODE_LIST[@]}; do
    ( HOST="$ip" . ./prepare_docker.sh ) &
done
wait $(jobs -p)

yellow "Install REX-Ray '$REXRAY_VERSION' on all Swarm instances..."
# early config preparation to avoid mutating same config files in parallel
prepare_rexray_config
for ip in ${NODE_LIST[@]}; do
    ( HOST="$ip" SKIP_REXCONF=y . ./prepare_rexray.sh ) &
done
wait $(jobs -p)

yellow "Install SSSD on all Swarm instances..."
if [[ -n "$_arg_use_sssd" ]]; then
    ( HOSTS="$NODE_LIST" . ./prepare_sssd.sh )
else
    yellow "...skipped"
fi

ec2_ssh_access_ok() {
    R=$(ssh $1 $(echo '{"command":"docker:ps"}'|b64enc) >/dev/null)
    rg_status "$(exit_code_ok $? 0)" "SSH access for $USER@$1"
}

if [[ -n "$_arg_use_sssd" ]]; then
for ip in ${NODE_LIST[@]}; do
    ec2_ssh_access_ok "$ip" &
done
wait $(jobs -p)
fi

yellow "Prepare RDS:Postgres"
( HOST="$(echo "$NODE_LIST"|head -n1)" . ./prepare_rds.sh )

yellow "Preparing restricted shell for users..."
( . ./prepare_restricted_shell.sh )

yellow "Configure Swarm Manager..."
SWARM_MANAGER_LIST="$(swarm_manager_instances|jq -r '.Reservations[].Instances[]|.PublicIpAddress')"
for ip in ${SWARM_MANAGER_LIST[@]}; do
    ( HOST="$ip" . ./prepare_manager.sh ) &
done
wait $(jobs -p)

yellow "Prepare Docker Swarm..."
( FORCE_NEW_CLUSTER="$_arg_force_new_cluster" . ./prepare_swarm.sh )

MANAGER_IP=$(manager_ip)

yellow "Configure Swarm node labels"
cd ../client
HOST="$MANAGER_IP" configure_swarm_nodes
cd - 1>/dev/null

yellow "Prepare core services..."
( HOST="$MANAGER_IP" . ./prepare_core_services.sh )

## undefined RDS_HOST available only after prepare_rds
( . ./prepare_restricted_shell.sh )

yellow "Prepare ACL"
( HOST="$MANAGER_IP" . ./prepare_acl.sh )

yellow "EC2 instance availability..."
check_reachable "$DOMAIN"
check_reachable "$DOMAIN" 443
check_reachable "$(v2elb $ELB_NAME|jq_v2elb_dnsname)"
check_reachable "$(v2elb $ELB_NAME|jq_v2elb_dnsname)" 443

_IPS="$(swarm_manager_instances|jq -r '.Reservations[].Instances[]|.PublicIpAddress')"
for ip in ${_IPS[@]}; do
    R=$(is_reachable_via_curl "$ip")
    rg_status "$(exit_code_not_ok $? 0)" "$ip:80 is blocked"
done

_IPS="$(swarm_node_instances|jq -r '.Reservations[].Instances[]|.PublicIpAddress')"
for ip in ${_IPS[@]}; do
    R=$(is_reachable_via_curl "$ip")
    rg_status "$(exit_code_not_ok $? 0)" "$ip:80 is blocked"
done

yellow "Checking ELB instance health..."
_TG_ARN="$(v2elb_target_groups "$ELB_NAME"|v2elb_target_group_arn)"
HEALTH="$(aws elbv2 describe-target-health --target-group-arn "$_TG_ARN")"
for k in $(echo $HEALTH|jq -r '.TargetHealthDescriptions[]|[.Target.Id,.TargetHealth.State]|@csv'|tr '\n' ' '|sed 's/"//g'); do
    INSTANCE_ID="$(echo $k|cut -f1 -d,)"
    INSTANCE_ST="$(echo $k|cut -f2 -d,)"
    R=$(test "$INSTANCE_ST" = "healthy")
    rg_status "$(exit_code_ok $? 0)" "ELB '$ELB_NAME' listener '$INSTANCE_ID' is healthy"
done

yellow "Checking Swarm health..."
health_leader() {
    echo "$1"|grep Ready|grep Active|grep Leader
}
health_node() {
    echo "$1"|grep Ready|grep Active
}
NODE_HEALTH=$(run_user $MANAGER_IP <<EOF
docker node ls
EOF
)
R="$(health_leader "$NODE_HEALTH")"
N="$(echo $R|awk '{print $1}')"
rg_status "$(exit_code_ok $? 0)" "Swarm Manager '$N' is healthy"
while IFS= read -r line; do
    N="$(echo $line|awk '{print $1}')"
    R="$(health_node "$line")"
    rg_status "$(exit_code_ok $? 0)" "Swarm Node '$N' is healthy"
done <<< "$(echo "$NODE_HEALTH"|sed '1d'|grep -v Leader)";

yellow "Preparing CLI for users..."
( HOST="$MANAGER_IP" . ./prepare_cli.sh )
yellow "Cronjobs..."
( HOST="$MANAGER_IP" KEY=$SERVICE_LISTING_KEY . ./prepare_swarm_cronjobs.sh )

yellow "Preparing Secrets..."
( . ./prepare_secrets.sh )

if [[ "$_arg_cloudwatch_logs" == "true" ]]; then
    yellow "Preparing CloudWatch logging..."
    for ip in ${NODE_LIST[@]}; do
        ( HOST="$ip" . ./prepare_cloudwatch.sh ) &
    done
    wait $(jobs -p)
else
    yellow "Skipping CloudWatch logging setup..."
fi

yellow "Prepare futuswarm container..."
( . ./prepare_futuswarm_container.sh )

yellow "Prepare futuswarm-health container..."
( . ./prepare_futuswarm_health_container.sh )

do_post_install "install.sh"

FULL_LOG="$(install_log)"
green "Installation complete!"
echo "Logs available at $FULL_LOG"
echo "Usage instructions at https://$DOMAIN"
RED_ISSUES="$(cat $FULL_LOG|grep ✘)"
if [[ -n "$RED_ISSUES" ]]; then
    echo ""
    yellow "The following issues might require your attention (you can re-run the installer to verify/fix issues):"
    echo "$RED_ISSUES"
fi
