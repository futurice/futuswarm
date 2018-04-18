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
_arg_value=
_arg_new_value=
_arg_legacy_docker=
_arg_name=

mk_virtualenv
source_virtualenv

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
printf "\t%s\n" " migrate-secrets --to B_CLI"
print_example "? Move secrets from swarm A to swarm B using B's CLIs"
print_example "? ... --from futuswarm --to futuswarmv2"
printf "\t%s\n" " restore-services --to CLI [--force]"
print_example "? Restore all known services. Optionally remove existing service before deployment."
printf "\t%s\n" " check-for-value --value (--new-value)"
print_example "? Check for deprecated configuration values and update as necessary"
printf "\t%s\n" " check-for-key --value (--new-value)"
print_example "? Check for deprecated configuration values by key names and update as necessary"
printf "\t%s\n" " service-inspect -n NAME"
print_example "? Check stored app:inspect data for service"
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
        ;; --value|--value=*)
            _arg_value=$(arg_required value "$1" "$_two") || die
        ;; --new-value|--new-value=*)
            _arg_new_value=$(arg_required new-value "$1" "$_two") || die
        ;; -n|--name=*)
            _arg_name=$(arg_required name "$1" "$_two") || die
        ;; --legacy-docker)
            _arg_legacy_docker=true
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
    R=$(AWS_PROFILE="$1" secret get $KEY --vaultkey="$KMS_ALIAS" --vault="$SECRETS_S3_BUCKET" --env "$_arg_env" --region "$SECRETS_REGION")
    if [[ "$?" == "0" ]]; then
        echo "$R"
    fi
}

running_services_list() {
    echo "$($_arg_from app:list|sed '1d'|awk '{print $2}')"
}

service_secrets() {
    AWS_PROFILE="$1" secret config -P "$2" --vaultkey="$KMS_ALIAS" --vault="$SECRETS_S3_BUCKET" --env "$_arg_env" --region "$SECRETS_REGION" -F json
}

service_inspect() {
    local _KEY="service-inspect-$2"
    R=$(AWS_PROFILE="$1" secret get $_KEY --vaultkey="$KMS_ALIAS" --vault="$SECRETS_S3_BUCKET" --env "$_arg_env" --region "$SECRETS_REGION" -P futuswarm)
    if [[ "$?" == "0" ]]; then
        echo "$R"
    fi
}

restore_services() {
yellow "Restoring all known services using AWS-profile '$FROM_AWS_PROFILE' from futuswarm '$CLOUD' to futuswarm using CLI '$_arg_to' [env: $_arg_env]"
SERVICES="${MOCK_SERVICES:-$(stored_services_list "$FROM_AWS_PROFILE")}"
while IFS= read -r line; do
    _name="$(read_value "$line" ".Name")"
    _image_tag="$(read_value "$line" ".Image" "5")"
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

    _INSPECT="${MOCK_INSPECT:-$(service_inspect "$FROM_AWS_PROFILE" "$_name")}"
    _arg_port=$(echo $_INSPECT|jq -r '.Spec.Labels."com.df.port"//empty')
    _arg_open=false
    if [[ -n "$OPEN_DOMAIN" ]]; then
        _arg_open=$(echo $_INSPECT|jq -r '.Spec.Labels."com.df.serviceDomain"//empty'|grep "$OPEN_DOMAIN" >/dev/null&&echo true||echo false)
    fi
    if [[ -z "$_arg_port" ]]; then
        _arg_port=$DOCKER_CONTAINER_PORT
    fi

    cd $CWD/../client
    echo " restoring: $_name ($_image:$_tag) port:$_arg_port open:$_arg_open"
    if [ -n "$_arg_noop" ]; then
        continue
    fi
    if [ -n "$_arg_force" ]; then
        echo ""|bash -c "$_arg_to app:remove --name $_name"
    fi
    echo ""|bash -c "$_arg_to app:deploy --name $_name --image $_image --tag $_tag --port=$_arg_port --open=$_arg_open"
    cd - 1>/dev/null
done <<< "$SERVICES"
}

read_value() {
    if [[ "$_arg_legacy_docker" == "true" ]]; then
        _LOOKUP="${3:-2}"
        echo "$(echo $1|awk "{print \$$_LOOKUP}")"
    else
        echo "$(echo $1|jq -r "$2")"
    fi
}

migrate_secrets() {
exit_on_undefined "$FROM_AWS_PROFILE" "FROM_AWS_PROFILE="
yellow "Migrating secrets using AWS-profile '$FROM_AWS_PROFILE' from futuswarm '$CLOUD' to futuswarm using CLI '$_arg_to' [env: $_arg_env]"
# NOTE: echo ""| prevents stdin hijack
SERVICES="${MOCK_SERVICES:-$(stored_services_list "$FROM_AWS_PROFILE")}"
while IFS= read -r line; do
    _name="$(read_value "$line" ".Name")"
    yellow "service: $_name"
    SECRETS="${MOCK_SECRETS:-$(service_secrets "$FROM_AWS_PROFILE" "$_name")}"
SECRETS_FMT=$(python commands.py stdin_to_json_newlined_objects <<EOF
$SECRETS
EOF
)
TOTAL_SECRETS="$(echo "$SECRETS_FMT"|wc -l)"
_bg=""
if [[ "$TOTAL_SECRETS" -lt 10 ]]; then
    _bg="&"
fi
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
        echo ""|bash -c "$_arg_to config:set $KEY='$VAL' -n $_name" 1>/dev/null $_bg
    done <<< "$SECRETS_FMT"
    wait $(jobs -p)
done <<< "$SERVICES"
}

check_for_value() {
yellow "Checking secrets using AWS-profile '$FROM_AWS_PROFILE' for '$_arg_value' [env: $_arg_env]"
# NOTE: echo ""| prevents stdin hijack
SERVICES="${MOCK_SERVICES:-$(stored_services_list "$FROM_AWS_PROFILE")}"
while IFS= read -r line; do
    _name="$(read_value "$line" ".Name")"
    yellow "service: $_name"
    SECRETS="${MOCK_SECRETS:-$(service_secrets "$FROM_AWS_PROFILE" "$_name")}"
SECRETS_FMT=$(python commands.py stdin_to_json_newlined_objects <<EOF
$SECRETS
EOF
)
TOTAL_SECRETS="$(echo "$SECRETS_FMT"|wc -l)"
_bg=""
if [[ "$TOTAL_SECRETS" -lt 10 ]]; then
    _bg="&"
fi
    while IFS= read -r sd; do
        KEY="$(echo $sd|jq -r '.Key')"
        VAL="$(echo $sd|jq -r '.Value')"
        if [ -z "$KEY" ]; then
            continue
        fi
        _direct_match=
        if [[ "$VAL" == "$_arg_value" ]]; then
            _direct_match=true
        fi
        if [[ "$VAL" =~ "$_arg_value" ]]; then
            echo "Match: $KEY=$VAL"
        fi
        if [ -n "$_arg_new_value" ] && [ "$_direct_match" == "true" ]; then
            echo " updating: $_arg_to config:set $KEY='$_arg_new_value' -n $_name"
            if [ -n "$_arg_noop" ]; then
                continue
            fi
            echo ""|bash -c "$_arg_to config:set $KEY='$_arg_new_value' -n $_name" --async 1>/dev/null $_bg
        fi
    done <<< "$SECRETS_FMT"
    wait $(jobs -p)
done <<< "$SERVICES"
}

check_for_key() {
yellow "Checking secrets using AWS-profile '$FROM_AWS_PROFILE' for '$_arg_value' [env: $_arg_env]"
# NOTE: echo ""| prevents stdin hijack
SERVICES="${MOCK_SERVICES:-$(stored_services_list "$FROM_AWS_PROFILE")}"
while IFS= read -r line; do
    _name="$(read_value "$line" ".Name")"
    yellow "service: $_name"
    SECRETS="${MOCK_SECRETS:-$(service_secrets "$FROM_AWS_PROFILE" "$_name")}"
SECRETS_FMT=$(python commands.py stdin_to_json_newlined_objects <<EOF
$SECRETS
EOF
)
TOTAL_SECRETS="$(echo "$SECRETS_FMT"|wc -l)"
_bg=""
if [[ "$TOTAL_SECRETS" -lt 10 ]]; then
    _bg="&"
fi
    while IFS= read -r sd; do
        KEY="$(echo $sd|jq -r '.Key')"
        VAL="$(echo $sd|jq -r '.Value')"
        if [ -z "$KEY" ]; then
            continue
        fi
        _direct_match=
        if [[ "$KEY" == "$_arg_value" ]]; then
            _direct_match=true
        fi
        if [[ "$KEY" =~ "$_arg_value" ]]; then
            echo "Match: $KEY=$VAL"
        fi
        if [ -n "$_arg_new_value" ] && [ "$_direct_match" == "true" ]; then
            echo " updating: $_arg_to config:set $KEY='$_arg_new_value' -n $_name"
            if [ -n "$_arg_noop" ]; then
                continue
            fi
            echo ""|bash -c "$_arg_to config:set $KEY='$_arg_new_value' -n $_name" --async 1>/dev/null $_bg
        fi
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

;; service-inspect)
exit_on_undefined "$FROM_AWS_PROFILE" "FROM_AWS_PROFILE="
service_inspect "$FROM_AWS_PROFILE" "$_arg_name"

;; check-for-value)
exit_on_undefined "$_arg_value" "--value"
exit_on_undefined "$FROM_AWS_PROFILE" "FROM_AWS_PROFILE="
exit_on_undefined "$_arg_to" "--to"
noop_notice
check_for_value

;; check-for-key)
exit_on_undefined "$_arg_value" "--value"
exit_on_undefined "$FROM_AWS_PROFILE" "FROM_AWS_PROFILE="
exit_on_undefined "$_arg_to" "--to"
noop_notice
check_for_key

;; *)
echo "Unrecognized command '$ACTION'"
print_help
;;
esac

deactivate_virtualenv
