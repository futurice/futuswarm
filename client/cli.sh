#!/usr/bin/env bash

# NOTES:
# - SSH_ARGS="-t" is (also) needed for testing output of commands

# GLOBAL VARIABLES
HOST="${HOST:-}"
CONTAINER_PORT=8000
COMPANY=company
OPEN_DOMAIN=not-configured
SSH_USER="${SSH_USER:=$USER}"
SSH_KEY="${SSH_KEY:-}"
SSH_PORT="${SSH_PORT:-}"
WITH_SSH_KEY=""
CLI_VERSION=
DOCKER_REGISTRY_PORT="${DOCKER_REGISTRY_PORT:-5005}"
DOCKER_REGISTRY_HOST_BIND="${DOCKER_REGISTRY_HOST_BIND:-127.0.0.1}"
if [ ! -z "$SSH_KEY" ]; then
WITH_SSH_KEY="-i $SSH_KEY"
fi
SSH_ARGS="${SSH_ARGS:-}"
SU="${SU:-}"

#BLOCKSTARTcommands
# development
_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $_DIR/../setup/commands.sh 2>/dev/null||source setup/commands.sh 2>/dev/null
#BLOCKENDcommands

if [ -z "$HOST" ]; then
    red "HOST= not configured (unfinished futuswarm installation?)"
    safe_exit 1
fi

mk_ssh_cmd() {
local _host="$(determine_host "$1")"
local _port="$(determine_port "$1" $SSH_PORT)"
echo "TERM=xterm-256color ssh -A ${SSH_FLAGS:-} -o Compression=no -o ServerAliveInterval=10 -o ConnectTimeout=3 -o LogLevel=ERROR -q -o StrictHostKeyChecking=no $WITH_SSH_KEY -p $_port $SSH_USER@$_host $SSH_ARGS"
}

# MUTABLE VARIABLES
DEFAULT_TAG=latest
DEFAULT_ENV=default

key_val_conversion() {
ARGS_ARR=("$@")
ARGS_ARR_LEN=${#ARGS_ARR[@]}
O=""
for (( i=0;i<$ARGS_ARR_LEN;i++)); do
    _line=${ARGS_ARR[${i}]}
    # argument startswith --
    if [[ $(echo $_line|grep ^--) ]]; then
        continue
    fi
    # argument contains =
    [[ "$_line" == *'='* ]] || continue

    _k=$(echo $_line|cut -f1 -d=)
    _v="$(echo $_line|cut -f2-100 -d=)"
    O+='{"key":"'$_k'","value":"'$_v'"},'
done
echo "$O"|sed 's/.$//'
}
CONV=$(key_val_conversion "$@")

arg_value() {
    if [[ $(echo "$1"|grep ^-) ]]; then
        echo ""
    else
        echo "$1"
    fi
}

ARGS=$*
ACTION=$1
ARG_2="$(arg_value "${2:-}")"
ARGS_=$@


# default values
_arg_name=
_arg_debug=
_arg_tag="$DEFAULT_TAG"
_arg_port="$CONTAINER_PORT"
_arg_show_examples=
_arg_env="$DEFAULT_ENV"
_arg_action=
_arg_open=
_arg_version=
_arg_node=
_arg_user=
_arg_key=
_arg_cpu=
_arg_placement=
_arg_async=
_arg_replicas=
_arg_password=

DOCKER_CMD="$(docker_cmd)"

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

print_help() {
printf 'Usage: %s COMMAND [-n APP_NAME] [ARGUMENTS]\n' "$0"
printf "\t%s\n" " "
printf "\t%s\n" "Commands:"
printf "\t%s\n" " image:push"
print_example "? push a local Docker image to Docker Swarm"
print_example "image:push -i $COMPANY/IMAGE_NAME -t TAG"
printf "\t%s\n" " app:deploy"
print_example "? deploy a Docker image as a service (image from Docker Hub, or uploaded previously using image:push)"
print_example "app:deploy -n NAME -i $COMPANY/IMAGE_NAME -t TAG"
printf "\t%s\n" " app:list"
print_example "? list all running services, or the status of a specific one"
print_example "app:list -n NAME"
printf "\t%s\n" " app:inspect"
printf "\t%s\n" " app:logs"
printf "\t%s\n" " app:shell"
print_example "? access a container"
print_example "app:shell -n NAME"
printf "\t%s\n" " app:run"
print_example "? execute a command in the container and exit"
print_example "app:run --action \"ls -laF\" -n NAME"
printf "\t%s\n" " app:restart"
printf "\t%s\n" " app:remove"
printf "\t%s\n" ""
printf "\t%s\n" " config"
print_example "? show configuration (environment variables) for the container"
print_example "config -n NAME"
printf "\t%s\n" " config:get"
print_example "config:get KEY -n NAME"
printf "\t%s\n" " config:set"
print_example "config:set KEY=val KEY2=val2 -n NAME"
printf "\t%s\n" " config:unset"
print_example "config:unset KEY -n NAME"
printf "\t%s\n" ""
printf "\t%s\n" " acl:user:list"
print_example "? show users with access to specified service"
print_example "acl:user:list -n NAME"
printf "\t%s\n" " acl:user:add"
print_example "acl:user:add username -n NAME"
printf "\t%s\n" " acl:user:rm"
printf "\t%s\n" " acl:user:services"
printf "\t%s\n" ""
printf "\t%s\n" " secret"
print_example "? show secrets for the container"
print_example "secret -n NAME"
printf "\t%s\n" " secret:get"
print_example "secret:get KEY -n NAME"
printf "\t%s\n" " secret:set"
print_example "secret:set KEY=file -n NAME"
print_example "secret:set KEY=file -n NAME --version 2"
printf "\t%s\n" " secret:unset"
print_example "secret:unset KEY -n NAME"
printf "\t%s\n" ""
printf "\t%s\n" " volume:create:ebs"
print_example "volume:create VOLUME_NAME --size 10 -n NAME"
printf "\t%s\n" " volume:rm:ebs"
print_example "volume:rm VOLUME_NAME -n NAME"
printf "\t%s\n" " volume:list"
print_example "volume:list -n NAME"
printf "\t%s\n" ""
printf "\t%s\n" " db:create:postgres"
print_example "db:create:postgres -n NAME"
printf "\t%s\n" ""
printf "\t%s\n" " admin:list"
printf "\t%s\n" " admin:swarm:usage"
printf "\t%s\n" " admin:swarm:restart"
printf "\t%s\n" " admin:user:add"
printf "\t%s\n" ""
printf "\t%s\n" " swarm:nodes"
printf "\t%s\n" " swarm:stats"
printf "\t%s\n" " swarm:node:label:add"
printf "\t%s\n" " swarm:node:label:rm"
printf "\t%s\n" " swarm:network:health"
print_example "? check swarm networking health between two containers. By default futuswarm-health (manager) and a container of choice (default: --name futuswarm --port 8000)"
print_example "swarm:network:health (optional arguments: --name, --port)"
printf "\t%s\n" " "
printf "\t%s\n" "Arguments:"
printf "\t%s\n" "-n,--name: name of application"
printf "\t%s\n" "-i,--image: Docker image to use"
printf "\t%s\n" "-t,--tag: tag of Docker image (default: $DEFAULT_TAG)"
printf "\t%s\n" "--extra: extra arguments to 'docker service create'"
printf "\t%s\n" "--port: container listens on this exposed port (default: $CONTAINER_PORT)"
printf "\t%s\n" "--open=true|false: Allow access to same service from *.$OPEN_DOMAIN"
printf "\t%s\n" "-e,--env: configuration environment (default: $DEFAULT_ENV)"
printf "\t%s\n" "-h,--help: Prints help (-hh for example usage)"
}

create_service() {
run_client $HOST '{"command":"app:create","name":"'$_arg_name'","image":"'$_arg_image'","tag":"'$_arg_tag'","port":"'$_arg_port'","extra":"'$_arg_extra'"}'
}

restart_service() {
SSH_ARGS="-t" run_client $HOST '{"command":"app:restart","name":"'$_arg_name'","async":"'$_arg_async'"}'
}

show_app_status() {
if [[ -n "$_arg_name" ]]; then
run_client $HOST '{"command":"app:status","name":"'$_arg_name'","trunc":"'${TRUNC:-}'"}'
else
run_client $HOST '{"command":"app:status"}'
fi
}

registry_container_name="futuswarm-registry"
REGISTRY_UP=0
cleanup_registry() {
  if [[ -n "$($DOCKER_CMD ps -q -f name="$registry_container_name")" ]]; then
    REGISTRY_UP=1
  else
    yellow "Removing old Docker Registry containers..."
    $DOCKER_CMD rm -f -v "$registry_container_name"||true
  fi
}

# tunnel directly to nodes
# 1: image
push_image_to_all_nodes_v2() {
image_name="$1"
image_tag="${2:-}"
image_tag_ext=""

if [ -n "$image_tag" ]; then
    if [ "$image_tag" != "latest" ]; then
        image_tag_ext=":$image_tag"
    fi
fi

container_registry_port=5000
registry_port=$DOCKER_REGISTRY_PORT
registry_host="localhost"
registry_host_ip=127.0.0.1
remote_registry_port=${REMOTE_REGISTRY_PORT:-$(($container_registry_port + $(( ( RANDOM % 500 ) + 1 ))))}

cleanup_registry
start_local_registry
registry_port=$($DOCKER_CMD inspect $registry_container_name --format '{{json .}}'|jq -r '.NetworkSettings.Ports."5000/tcp"[].HostPort')
push_image_to_local_private_registry
yellow "\nSending image '$1:$_arg_tag' to all nodes... (Note: first push of a new image takes some time)"
# get node_list
CMD='{"command":"swarm:node:ips"}'
NODES="$(run_client $HOST "$CMD")"
NODE_LIST="$(echo $NODES|jq -r '.nodes')"
echo " nodes: $NODE_LIST"
# push to each swarm node
for ip in ${NODE_LIST[@]}; do
    push_image_to_swarm $ip false &
done
wait $(jobs -p)
verify_image_exists_on_swarm_nodes
}

# tunnel via manager
# 1: image
push_image_to_all_nodes() {
image_name="$1"
image_tag="${2:-}"
image_tag_ext=""

if [ -n "$image_tag" ]; then
    if [ "$image_tag" != "latest" ]; then
        image_tag_ext=":$image_tag"
    fi
fi

container_registry_port=5000
registry_port=$DOCKER_REGISTRY_PORT
registry_host="localhost"
registry_host_ip=127.0.0.1
remote_registry_port=${REMOTE_REGISTRY_PORT:-$(($container_registry_port + $(( ( RANDOM % 500 ) + 1 ))))}

cleanup_registry
start_local_registry
registry_port=$($DOCKER_CMD inspect $registry_container_name --format '{{json .}}'|jq -r '.NetworkSettings.Ports."5000/tcp"[].HostPort')
push_image_to_local_private_registry
yellow "\nSending image '$1:$_arg_tag' to all nodes... (Note: first push of a new image takes some time)"
# push to manager; manager pushes fwd to nodes
push_image_to_swarm $HOST
verify_image_exists_on_swarm_nodes
}

start_local_registry() {
if [ "$REGISTRY_UP" -ne 1 ]; then
    yellow "Running a Docker Registry at $registry_host:$registry_port..."
    $DOCKER_CMD run -d --mount type=tmpfs,destination=/var/lib/registry -e REGISTRY_STORAGE_FILESYSTEM_MAXTHREADS=150 --publish="$DOCKER_REGISTRY_HOST_BIND:$registry_port:$container_registry_port" --name $registry_container_name registry:2 || true
    sleep 2 # need sleep when starting
fi
}

push_image_to_local_private_registry() {
yellow "\nPushing '$image_name$image_tag_ext' to local Docker Registry '$registry_host:$registry_port'..."
$DOCKER_CMD tag "$image_name$image_tag_ext" "$registry_host:$registry_port/$image_name$image_tag_ext"
$DOCKER_CMD push "$registry_host:$registry_port/$image_name$image_tag_ext"
}

# 1:image 2:host 3:tag
push_image_to_swarm() {
local spread="${2:-true}"
local WITH_USER_HOST="$SSH_USER@$(determine_host "$1")"
yellow "\nPulling '$image_name$image_tag_ext' to '$WITH_USER_HOST:$remote_registry_port' from '$registry_host:$registry_port'..."
CMD='{"command":"image:push","host":"'$registry_host_ip':'$remote_registry_port'","image_tag":"'$image_name$image_tag_ext'","spread":"'$spread'","su":"'$SU'"}'
SSH_ARGS="-R $remote_registry_port:$registry_host_ip:$registry_port" run_client $1 "$CMD"
}

verify_image_exists_on_swarm_nodes() {
yellow "\nVerifying image '$image_name$image_tag_ext' sent to all nodes..."
CMD='{"command":"docker:images:name","image_tag":"'$image_name$image_tag_ext'","spread":true,"su":"'$SU'"}'
SSH_ARGS="" run_client $HOST "$CMD"
}

while test $# -gt 0; do
    case "$1" in
           -o|--option|--option=*)
            _arg_option=$(arg_required option "$1" "$2") || die
        ;; -n|--name|--name=*)
            _arg_name=$(arg_required name "$1" "$2") || die
            validate_servicename "$_arg_name"
        ;; -i|--image|--image=*)
            _arg_image=$(arg_required image "$1" "$2") || die
        ;; -t|--tag|--tag=*)
            _arg_tag=$(arg_required tag "$1" "$2") || die
        ;; --action|--action=*)
            _arg_action=$(arg_required action "$1" "$2") || die
        ;; --port|--port=*)
            _arg_port=$(arg_required port "$1" "$2") || die
        ;; --extra|--extra=*)
            _arg_extra=$(arg_required extra "$1" "$2") || die
        ;; --size|--size=*)
            _arg_size=$(arg_required size "$1" "$2") || die
        ;; -e|--env|--env=*)
            _arg_env=$(arg_required env "$1" "$2") || die
        ;; --open|--open=*)
            _arg_open=$(arg_required open "$1" "$2") || die
        ;; --version|--version=*)
            _arg_version=$(arg_required version "$1" "$2") || die
        ;; --node|--node=*)
            _arg_node=$(arg_required node "$1" "$2") || die
        ;; --user|--user=*)
            _arg_user=$(arg_required user "$1" "$2") || die
        ;; --key|--key=*)
            _arg_key=$(arg_required key "$1" "$2") || die
        ;; --cpu|--cpu=*)
            _arg_cpu=$(arg_required cpu "$1" "$2") || die
        ;; --placement|--placement=*)
            _arg_placement=$(arg_required placement "$1" "$2") || die
        ;; --replicas|--replicas=*)
            _arg_replicas=$(arg_required replicas "$1" "$2") || die
        ;; --password|--password=*)
            _arg_password=$(arg_required password "$1" "$2") || die
        ;; --debug)
            _arg_debug=on
        ;; --async)
            _arg_async=on
        ;; -h|--help)
            print_help
            safe_exit 0
        ;; -hh)
            _arg_show_examples=on
            print_help
            safe_exit 0
        ;; *)
            _positionals+=("$1")
        ;;
    esac
    shift
done

_positional_names=('_arg_positional_arg')
_arg_positional_arg=$ACTION

# ensure SSH_KEY is available
DEFAULT_SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_rsa}"
add_ssh_key_to_agent "$DEFAULT_SSH_KEY"

# CLI version check
_cli_version_check() {
_CV="${CLI_VERSION:-$(cli_version)}"
run_client $HOST '{"command":"cli:version-check","version":"'$_CV'"}'
}
if [ -n "$(cli_version_check_needed)" ]; then
    green "Performing weekly CLI version check..."
    _cli_version_check
fi

# Action.
case "$ACTION" in
swarm:node:ips)
run_client $HOST '{"command":"swarm:node:ips"}'

;; image:push)
exit_on_undefined "$_arg_image" "--image"

# check image exists locally
R=$($DOCKER_CMD images -q "$_arg_image:$_arg_tag")
if [[ -z "$R" ]]; then
    red "Could not find image '$_arg_image:$_arg_tag' from local Docker (run 'docker pull $_arg_image:$_arg_tag'?)"
    safe_exit 1
fi

_PUSH_IMAGE_FN="${PUSH_IMAGE_FN:-push_image_to_all_nodes_v2}"
$_PUSH_IMAGE_FN "$_arg_image" "$_arg_tag"

;; app:deploy)
exit_on_undefined "$_arg_image" "--image"
exit_on_undefined "$_arg_name" "--name"
if [[ "$_arg_tag" == "latest" ]]; then
    red "NOTICE: Using 'latest' for a tag is bad practice, please pin the image to a specific tag in future"
fi
DO='{"command":"app:deploy","name":"'$_arg_name'","env":"'$_arg_env'","image":"'$_arg_image'","tag":"'$_arg_tag'","port":"'$_arg_port'","extra":"'$_arg_extra'","open":"'$_arg_open'","cpu":"'$_arg_cpu'","placement":"'$_arg_placement'","action":"'$_arg_action'","async":"'$_arg_async'","replicas":"'$_arg_replicas'"}'
SSH_ARGS="-t" run_client $HOST "$DO"
TRUNC="" show_app_status

;; app:restart)
exit_on_undefined "$_arg_name" "--name"
restart_service
TRUNC="" show_app_status

;; app:remove)
exit_on_undefined "$_arg_name" "--name"
run_client $HOST '{"command":"app:remove","name":"'$_arg_name'"}'

;; app:list)
TRUNC="--no-trunc" show_app_status

;; app:inspect)
exit_on_undefined "$_arg_name" "--name"
run_client $HOST '{"command":"app:inspect","name":"'$_arg_name'"}'

;; app:logs)
exit_on_undefined "$_arg_name" "--name"
run_client $HOST '{"command":"app:logs","name":"'$_arg_name'"}'

;; app:run)
exit_on_undefined "$_arg_name" "--name"
exit_on_undefined "$_arg_action" "--action"
DO='{"command":"app:run","name":"'$_arg_name'","action":"'$_arg_action'"}'
SSH_ARGS="-tt" run_client "$HOST" "$DO"

;; app:shell)
exit_on_undefined "$_arg_name" "--name"
DO='{"command":"app:shell","name":"'$_arg_name'"}'
SSH_ARGS="-tt" run_client $HOST "$DO"

;; swarm:nodes)
run_client $HOST '{"command":"swarm:node:list"}'

;; swarm:stats)
run_client $HOST '{"command":"swarm:node:stats"}'

;; swarm:node:label:add)
exit_on_undefined "$ARG_2" "label"
exit_on_undefined "$_arg_node" "--node"
run_client $HOST '{"command":"swarm:node:label:add","key":"'$ARG_2'","node":"'$_arg_node'"}'

;; swarm:node:label:rm)
exit_on_undefined "$ARG_2" "label"
exit_on_undefined "$_arg_node" "--node"
run_client $HOST '{"command":"swarm:node:label:rm","key":"'$ARG_2'","node":"'$_arg_node'"}'

;; swarm:node:location)
exit_on_undefined "$_arg_name" "--name"
run_client $HOST '{"command":"swarm:node:location","name":"'$_arg_name'"}'

;; config:set)
exit_on_undefined "$CONV" "KEY=value"
exit_on_undefined "$_arg_name" "--name"
SSH_ARGS="-t" run_client $HOST '{"command":"config:set","name":"'$_arg_name'","env":"'$_arg_env'","keys":['"$CONV"'],"async":"'$_arg_async'"}'

;; config:get)
exit_on_undefined "$_arg_name" "--name"
run_client $HOST '{"command":"config:get","key":"'$ARG_2'","env":"'$_arg_env'","name":"'$_arg_name'"}'

;; config)
exit_on_undefined "$_arg_name" "--name"
run_client $HOST '{"command":"config","env":"'$_arg_env'","name":"'$_arg_name'"}'

;; config:unset)
exit_on_undefined "$_arg_name" "--name"
SSH_ARGS="-t" run_client $HOST '{"command":"config:unset","key":"'$ARG_2'","env":"'$_arg_env'","name":"'$_arg_name'","async":"'$_arg_async'"}'

# NOTE: for secrets the env is predefined by the server
;; secret:set)
exit_on_undefined "$CONV" "KEY=file"
exit_on_undefined "$_arg_name" "--name"
while IFS= read -r key &&
      IFS= read -r value; do
if [[ ! -f "$value" ]]; then
    red "File '$value' not found"
    safe_exit 1
fi
NAME="${_arg_name}_$key"
local _port="$(determine_port "$HOST" $SSH_PORT)"
scp ${SSH_FLAGS:-} -o StrictHostKeyChecking=no -i $SSH_KEY -P $_port $value $SSH_USER@$HOST:/tmp/$NAME
done < <(echo "[$CONV]"|jq -r '.[]|(.key,.value)')
SSH_ARGS="-t" run_client $HOST '{"command":"secret:set","name":"'$_arg_name'","env":"'$_arg_env'","version":"'$_arg_version'","keys":['"$CONV"']}'

;; secret:get)
exit_on_undefined "$_arg_name" "--name"
run_client $HOST '{"command":"secret:get","key":"'$ARG_2'","env":"'$_arg_env'","name":"'$_arg_name'","version":"'$_arg_version'"}'

;; secret)
exit_on_undefined "$_arg_name" "--name"
run_client $HOST '{"command":"secret","env":"'$_arg_env'","name":"'$_arg_name'"}'

;; secret:unset)
exit_on_undefined "$_arg_name" "--name"
SSH_ARGS="-t" run_client $HOST '{"command":"secret:unset","key":"'$ARG_2'","env":"'$_arg_env'","name":"'$_arg_name'"}'

;; volume:create:ebs)
exit_on_undefined "$ARG_2" "volume name"
exit_on_undefined "$_arg_name" "--name"
exit_on_undefined "$_arg_size" "--size"
SSH_ARGS="-t" run_client $HOST '{"command":"volume:create:ebs","volume_name":"'$ARG_2'","size":"'$_arg_size'","name":"'$_arg_name'"}'

;; volume:rm:ebs)
exit_on_undefined "$ARG_2" "volume name"
exit_on_undefined "$_arg_name" "--name"
SSH_ARGS="-t" run_client $HOST '{"command":"volume:rm:ebs","volume_name":"'$ARG_2'","name":"'$_arg_name'"}'

;; volume:list)
exit_on_undefined "$_arg_name" "--name"
SSH_ARGS="-t" run_client $HOST '{"command":"volume:list","name":"'$_arg_name'"}'

;; db:create:postgres)
exit_on_undefined "$_arg_name" "--name"
SSH_ARGS="-t" run_client $HOST '{"command":"db:create:postgres","name":"'$_arg_name'"}'

;; db:drop:postgres)
exit_on_undefined "$_arg_name" "--name"
exit_on_undefined "$_arg_password" "--password"
SSH_ARGS="-t" run_client $HOST '{"command":"db:drop:postgres","name":"'$_arg_name'","password":"'$_arg_password'"}'

;; acl:user:add)
exit_on_undefined "$ARG_2" "username"
exit_on_undefined "$_arg_name" "--name"
SSH_ARGS="-t" run_client $HOST '{"command":"acl:user:add","name":"'$_arg_name'","key":"'$ARG_2'"}'

;; acl:user:rm)
exit_on_undefined "$ARG_2" "username"
exit_on_undefined "$_arg_name" "--name"
SSH_ARGS="-t" run_client $HOST '{"command":"acl:user:rm","name":"'$_arg_name'","key":"'$ARG_2'"}'

;; acl:user:list)
exit_on_undefined "$_arg_name" "--name"
run_client $HOST '{"command":"acl:user:list","name":"'$_arg_name'"}'

;; acl:user:services)
exit_on_undefined "$ARG_2" "username"
SSH_ARGS="-t" run_client $HOST '{"command":"acl:user:services","key":"'$ARG_2'"}'

;; cli:version-check)
_cli_version_check

;; admin:list)
run_client $HOST '{"command":"admin:list"}'

;; admin:swarm:usage)
SSH_ARGS="-t" run_client $HOST '{"command":"admin:swarm:usage"}'

;; admin:swarm:restart)
run_client $HOST '{"command":"admin:swarm:restart"}'

;; admin:user:add)
PUBKEY="$(cat $_arg_key)"
DO='{"command":"admin:user:add","user":"'$_arg_user'","key":"'$PUBKEY'"}'
SSH_ARGS="-t" run_client $HOST "$DO"

;; admin:user:rm)
DO='{"command":"admin:user:rm","user":"'$_arg_user'"}'
SSH_ARGS="-t" run_client $HOST "$DO"

;; admin:user:key:set)
PUBKEY="$(cat $_arg_key)"
DO='{"command":"admin:user:key:set","user":"'$_arg_user'","key":"'$PUBKEY'"}'
run_client $HOST "$DO"

;; admin:node:default_tags)
run_client $HOST '{"command":"admin:node:default_tags"}'

;; swarm:network:health)
DO='{"command":"swarm:network:health","name":"'$_arg_name'","port":"'$_arg_port'"}'
SSH_ARGS="-t" run_client $HOST "$DO"

;; node:json)
DO='{"command":"node:json"}'
run_client $HOST "$DO"

;; *)
echo "Unrecognized command '$ACTION'"
;;
esac

# User guidance
if [[ -z "$ACTION" ]]; then
echo "See CLI commands with -h, and full usage examples with -hh"
fi
