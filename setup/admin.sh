#!/usr/bin/env bash
STRICT="${STRICT:-y}"
CWD="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $CWD/init.sh

ARGS=$*
ACTION="${1:-}"

_arg_from=
_arg_to=
_arg_force=
_arg_noop=
_arg_show_examples=
_arg_env=default

mk_virtualenv
source venv/bin/activate

die() {
    local _ret=$2
    test -n "$_ret" || _ret=1
    test "$_PRINT_HELP" = yes && print_help >&2
    echo "$1" >&2
    safe_exit ${_ret}
}

print_example() {
    if [[ -n "$_arg_show_examples" ]]; then
        printf "\t%s\n" "   $1"
    fi
}

noop_notice() {
if [ -n "$_arg_noop" ]; then
    red "--noop in effect; no changes will be done."
fi
}

print_help() {
printf 'Usage: %s COMMAND [ARGUMENTS]\n' "$0"
printf "\t%s\n" " "
printf "\t%s\n" "Commands:"
printf "\t%s\n" " running-services"
printf "\t%s\n" " stored-services"
printf "\t%s\n" " migrate-secrets --from A_CLI --to B_CLI"
print_example "? Move secrets from swarm A to swarm B using their respective CLIs"
print_example "? ... --from futuswarm --to futuswarmv2"
printf "\t%s\n" " restore-services --to CLI [--force]"
print_example "? Restore all known services. Optionally remove existing service before deployment."
}

while test $# -gt 0; do
    _two="${2:-}"
    case "$1" in
           --from|--from=*)
            _arg_from=$(arg_required from "$1" "$_two") || die
        ;; --to|--to=*)
            _arg_to=$(arg_required to "$1" "$_two") || die
        ;; --env|--env=*)
            _arg_env=$(arg_required env "$1" "$_two") || die
        ;; --force)
            _arg_force=true
        ;; --noop)
            _arg_noop=true
        ;; -h|--help)
            print_help
            safe_exit 0
        ;; -hh)
            _arg_show_examples=on
            print_help
            safe_exit 0
        ;; *)
            :
        ;;
    esac
    shift
done

DOMAIN="${_DOMAIN:-$DOMAIN}"
KEY="${_KEY:-$SERVICE_LISTING_KEY}"
COMPANY="${_COMPANY:-$COMPANY}"
SSH_KEY="${_SSH_KEY:-$SSH_KEY}"
# FROM (migration)
FROM_AWS_PROFILE="${FROM_AWS_PROFILE:-}"
# TO (migration)
# TO unset? TO==FROM (recovery)
TO_AWS_PROFILE="${TO_AWS_PROFILE:-$FROM_AWS_PROFILE}"
# FROM unset? FROM==TO (recovery)
FROM_AWS_PROFILE="${FROM_AWS_PROFILE:-$TO_AWS_PROFILE}"

stored_services_list() {
    AWS_PROFILE="$1" secret get $KEY --vaultkey="$KMS_ALIAS" --vault="$SECRETS_S3_BUCKET" --env "$_arg_env"
}

running_services_list() {
    echo "$($_arg_from app:list|sed '1d'|awk '{print $2}')"
}

service_secrets() {
    AWS_PROFILE="$1" secret config -P "$2" --vaultkey="$KMS_ALIAS" --vault="$SECRETS_S3_BUCKET" --env "$_arg_env" -F json
}

restore_services() {
yellow "Restoring all known services using AWS-profile '$FROM_AWS_PROFILE' to futuswarm '$CLOUD' using CLI '$_arg_to' [env: $_arg_env]"
SERVICES="${MOCK_SERVICES:-$(stored_services_list "$FROM_AWS_PROFILE")}"
while IFS= read -r line; do
    _name="$(echo $line|jq -r '.Name')"
    _image_tag="$(echo $line|jq -r '.Image')"
    _image=$(echo $_image_tag|cut -f1 -d:)
    _tag=$(echo $_image_tag|cut -f2 -d:)
    if [[ -z "$_name" ]]; then
        red " unnamed service: $_image_tag"
        continue
    fi
    if [[ $(is_in_list "$_name" "$CORE_CONTAINERS") == "y" ]]; then
        green " skipping core container: $_name"
        continue
    fi
    cd $CWD/../client
    echo " restoring: $_name ($_image:$_tag)"
    if [ -n "$_arg_noop" ]; then
        continue
    fi
    if [ -n "$_arg_force" ]; then
        echo ""|bash -c "$_arg_to app:rm --name $_name"
    fi
    echo ""|bash -c "$_arg_to app:deploy --name $_name --image $_image --tag $_tag"
    cd - 1>/dev/null
done <<< "$SERVICES"
}

migrate_secrets() {
exit_on_undefined "$FROM_AWS_PROFILE" "FROM_AWS_PROFILE="
yellow "Migrating secrets using AWS-profile '$FROM_AWS_PROFILE' to futuswarm '$CLOUD' using CLI '$_arg_to' [env: $_arg_env]"
# NOTE: echo ""| prevents stdin hijack
SERVICES="${MOCK_SERVICES:-$(stored_services_list "$FROM_AWS_PROFILE")}"
while IFS= read -r line; do
    _name="$(echo $line|jq -r '.Name')"
    yellow "service: $_name"
    SECRETS="${MOCK_SECRETS:-$(service_secrets "$FROM_AWS_PROFILE" "$_name")}"
SECRETS_FMT=$(python commands.py stdin_to_json_newlined_objects <<EOF
$SECRETS
EOF
)
    while IFS= read -r sd; do
        KEY="$(echo $sd|jq -r '.Key')"
        VAL="$(echo $sd|jq -r '.Value')"
        if [ -z "$KEY" ]; then
            continue
        fi
        echo " migrating $KEY"
        if [ -n "$_arg_noop" ]; then
            continue
        fi
        echo ""|bash -c "$_arg_to config:set $KEY='$VAL' -n $_name" 1>/dev/null &
    done <<< "$SECRETS_FMT"
    wait $(jobs -p)
done <<< "$SERVICES"
}

# ACTION
case "$ACTION" in
migrate-secrets)
exit_on_undefined "$_arg_to" "--to"
exit_on_undefined "$FROM_AWS_PROFILE" "FROM_AWS_PROFILE="
noop_notice
migrate_secrets

;; restore-services)
exit_on_undefined "$_arg_to" "--to"
exit_on_undefined "$FROM_AWS_PROFILE" "FROM_AWS_PROFILE="
noop_notice
restore_services

;; stored-services)
exit_on_undefined "$FROM_AWS_PROFILE" "FROM_AWS_PROFILE="
stored_services_list "$FROM_AWS_PROFILE"

;; running-services)
exit_on_undefined "$_arg_from" "--from"
running_services_list

;; *)
echo "Unrecognized command '$ACTION'"
;;
esac

# exit virtualenv
deactivate
