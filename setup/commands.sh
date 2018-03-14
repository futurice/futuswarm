#!/usr/bin/env bash
SSH_PORT="${SSH_PORT:-22}"
TERM="${TERM:-xterm-256color}"

# 30.1.2018: security.ubuntu.com doesnt resolve ipv6
APT_FORCE_IPV4=true

HOST_OS=$(uname)
is_osx() {
    [[ "$HOST_OS" == "Darwin"* ]]
}

# lineinfile 1:string 2:file
lineinfile() {
    grep -q -F "$1" $2 || echo $1 >> $2
}

# replaceinfile 1:file 2:string/regex 3:replacement string
RIN_OPTS="-i"
if is_osx; then
    RIN_OPTS="-i ''"
fi
replaceinfile() {
    find $1 -type f -exec sed $RIN_OPTS "s~$2~$3~g" {} \;
}

# replaceOrAppendInFile 1:file 2:string/regex 3:replacement string
replaceOrAppendInFile() {
    if file_contains_str "$1" "$2"; then
        find $1 -type f -exec sed $RIN_OPTS "s~$2~$3~g" {} \;
    else
        echo $3 >> $1
    fi
}

# 1: file 2: string/regex
file_contains_str() {
    grep -q "$2" "$1"
}

log() {
    if [ "$LOGGING" -eq 1 ]; then
        printf "$(tput setaf 2)$(date +"%d.%m %H:%M:%S") | $@ [$0]$(tput sgr0)\n"
    fi
}

yellow() {
    printf "$(tput setaf 3)$@ $(tput sgr0)\n"
}

green() {
    printf "$(tput setaf 2)$@ $(tput sgr0)\n"
}

red() {
    printf "$(tput setaf 1)$@ $(tput sgr0)\n"
}

stdin() {
    # capturing piped output to a function as first parameter
    echo "${1:-$(</dev/stdin)}"
}

# run HOST COMMAND
run_user() {
local _port="$(determine_port "$1" $SSH_PORT)"
SSH_ARGS="${SSH_ARGS:-sudo bash -s}"
TERM=xterm-256color ssh ${SSH_FLAGS:-} -o StrictHostKeyChecking=no $SSH_USER@$1 -p $_port -i $SSH_KEY $SSH_ARGS <<EOF
TERM=xterm-256color
source /opt/commands.sh 2>/dev/null||true
${2:-$(stdin)}
EOF
}

run_sudo() {
local _port="$(determine_port "$1" $SSH_PORT)"
TERM=xterm-256color ssh ${SSH_FLAGS:-} -o StrictHostKeyChecking=no $SSH_USER@$1 -p $_port -i $SSH_KEY "sudo su && bash -s" <<EOF
TERM=xterm-256color
source /opt/commands.sh 2>/dev/null||true
${2:-$(stdin)}
EOF
}

loginto() {
TERM=xterm-256color ssh -A $SSH_USER@$1 -i $SSH_KEY
}

# synchronize FROM_PATH TO_PATH SERVER
synchronize() {
local _port="$(determine_port "$3" $SSH_PORT)"
    rsync -q -a -v -t -r  -e "ssh -i $SSH_KEY ${SSH_FLAGS:-} -o StrictHostKeyChecking=no -p $_port" --rsync-path="sudo rsync" $1 $SSH_USER@$3:$2
}

transfer() {
    scp -ri $SSH_KEY $1 $SSH_USER@$3:$2
}

countCharsIn() {
    echo $1|grep -o "$2"|grep -c "$2"||true
}

json_escape() {
    echo -n "$1" | python -c 'import json,sys,ast; print json.dumps(ast.literal_eval(sys.stdin.read()))'
}

ssh_up() {
    nc -w1 $1 22
}

ssh_up_wait() {
    until $(ssh_up); do sleep 2; done
}

RG_RED=0
RG_GREEN=0
is_red_green() {
if [ -z "$1" ]; then
    (( RG_RED++ ))
    red "✘"
else
    (( RG_GREEN++ ))
    green "✓"
fi
}

# 1: [green: "ok", red: ""] 2:requirement 3:message
rg_status() {
    local R="$(is_red_green "$1") ${2:-}"
    echo "$R"
    echo "$R">>/tmp/swarm-install-rg-$RUN_ID
    if [ -z "$1" ]; then
        if [ -n "${3:-}" ]; then
            echo "$3"
        fi
    fi
}

# 1: exit-code 2: wanted-code
exit_code_ok() {
    local _CODE="${2:-0}"
    if [[ $1 -eq $_CODE ]]; then
        echo "ok"
    else
        echo ""
    fi
}

exit_code_not_ok() {
    local _CODE="${2:-0}"
    if [[ $1 != $_CODE ]]; then
        echo "ok"
    else
        echo ""
    fi
}

exit_on_undefined() {
    if [[ -z "$1" ]]; then
        echo "Required argument '$2' not defined."
        safe_exit 1
    fi
}

add_ssh_key_to_agent() {
R=$(ssh-add -l)
if [[ "$R" != *"$1"* ]]; then
    if [ -f $1 ]; then
        yellow "Adding SSH_KEY=$1 for ssh-agent..."
        ssh-add $1
    fi
fi
}

B64_DECODE_OPTS="-d"
B64_ENCODE_OPTS="-w0"
if is_osx; then
    B64_DECODE_OPTS="-D"
    B64_ENCODE_OPTS=""
fi

b64enc() {
base64 $B64_ENCODE_OPTS
}

b64dec() {
base64 $B64_DECODE_OPTS
}

su_remote_cmd() {
cat <<EOF
export TERM=xterm-256color
export SSH_ORIGINAL_COMMAND=$(echo $1|b64enc)
export SSH_CONNECTION=localhost
bash /srv/server.sh
EOF
}

determine_host() {
echo "$1"|cut -d: -f1
}

# 1: port
# 2: default port
determine_port() {
local P="$(echo "$1"|cut -d: -f2 -s)"
if [ -z "$P" ]; then
    local P="$2"
fi
echo "$P"
}

mk_ssh_cmd() {
local _host="$(determine_host "$1")"
local _port="$(determine_port "$1" $SSH_PORT)"
echo "TERM=xterm-256color ssh -tt -A -o ServerAliveInterval=30 -o ConnectTimeout=3 -o LogLevel=ERROR -o StrictHostKeyChecking=no -i $SSH_KEY -p $_port $SSH_USER@$_host ${SSH_ARGS:-}"
}

sudo_client() {
_input="${2:-$(stdin)}"
SU=true SU_DIRECT=1 run_client "$1" "$_input"
}

run_client() {
    # 1: IP
    # 2/stdin: command
    _input="${2:-$(stdin)}"
    _cmd="$(echo "$_input")"
    SSH_CMD="$(mk_ssh_cmd $1)"
    if [[ "${SU:-}" != "true" ]]; then
        _cmd=$(echo "$_cmd"|b64enc)
        eval $SSH_CMD $_cmd
    else
        # root SSH_USER does bypasses ForceCommand
        if [[ ! -n "${SU_DIRECT:-}" ]]; then
            eval $SSH_CMD "bash -s" <<EOF
$(su_remote_cmd "$_cmd")
EOF
        else
            eval $SSH_CMD $_cmd
        fi
    fi
    return_code="$?"
    if [[ $return_code -eq 0 || $return_code -eq 1 ]]; then
        :
    else
        red "Connection Error ($return_code). Check your connection or contact support?"
        exit $return_code
    fi
}

cli_location() {
echo "https://s3.$AWS_REGION.amazonaws.com/$SWARM_S3_BUCKET/cli"
}

# 1: from
# 2: to
# (3: force)
cp_proxy_config() {
local FROM="$1"
local TO="$2"
if [ "${3:-}" == "y" ]; then
    mkdir -p "$TO"
    cp $FROM/apache.conf "$TO"
    cp $FROM/index.html "$TO"
    cp $FROM/status.html "$TO"
fi
}

# 1: name-of-cloud
# 2: company
mk_cloud() {
if [ -z "$1" ]; then
    red "Usage: mk_cloud name-of-cloud company"
    exit 1
fi
local _CLOUD="$1"
local _COMPANY="$2"
CDIR="$DIR/../config/$_CLOUD"
yellow "Creating '$CLOUD' with default configuration files in '$CDIR'"
cp_proxy_config "$DIR/../proxy/" "$CDIR/proxy/"
cp "$DIR/settings.sh" "$CDIR"
replaceinfile "$CDIR/settings.sh" '{COMPANY}' "$_COMPANY"
}

rm_cloud() {
# delete all AWS resources with our TAG
# rm EC2, rm ELB, rm RDS, rm VPC
echo "y"
}

# 1: lookup
# 2: space-separated list
is_in_list() {
S="$(echo $2|tr ' ' '\n')"
F="/tmp/tmp.$(date +%s%N).$RANDOM"
echo "$S">$F
_R=
while IFS= read -r x; do
    if [[ "$x" == "$1" ]]; then
        _R="y"
    fi
done <"$F"
rm $F
echo "$_R"
}


allow_user_or_abort() {
    if [[ -z "$(is_admin)" ]]; then
        red "Unauthorized"
        exit 1
    fi
}

is_sudo_docker_required() {
_SUDO=
R=$(docker info &>/dev/null)
if [[ "$?" -ne 0 ]]; then
    _SUDO=y
fi
echo $_SUDO
}

docker_cmd() {
if [[ $(is_sudo_docker_required) == "y" ]]; then
    echo "sudo docker"
else
    echo "docker"
fi
}

suppress_valid_awscli_errors() {
INPUT=${1:-$(</dev/stdin)}
OUTPUT="$INPUT"
while IFS= read -r msg; do
    R=$(echo "$INPUT"|tr '\n' ' '|grep "$msg")
    if [[ "$?" -eq 0 ]]; then
        OUTPUT=""
        break
    fi
done < <(echo "$OK_AWS")
if [ -n "$OUTPUT" ]; then
echo "$OUTPUT"
fi
}

OK_AWS=$(cat <<EOF
Resource.AlreadyAssociated
InvalidPermission.Duplicate
RouteAlreadyExists
"Return": true
EOF
)

# Capture stderr as stdin, output stdin
# 1: cmd
capture_stderr() {
echo $($1 2>&1 >/dev/tty)
}

# Capture stderr as stdin
# 1: cmd
capture_as_stderr() {
echo $($1 2>&1)
}

# Show spinner until function completes execution
# 1: pid
# (2: message)
spinner() {
_pid=$1
_msg="${2:-Processing}"
spin='-\|/'
i=0
sleep .1
local start="$SECONDS"
while kill -0 $_pid 2>/dev/null; do
  i=$(( (i+1) %4 ))
  local took=$(( SECONDS - start ))
  printf "\r (${took}s) $_msg ${spin:$i:1}"
  sleep .1
done
echo ""
}

# Execute function until return code equals 0
# 1: fn-condition
# (2: fn-payload)
# (3: message)
# (4: sleep-period)
wait_for() {
_fn_cond_rc() {
R=$("$_fn" "$_fn_payload" &>/dev/null)
echo $?
}
local _fn=$1
local _fn_payload="${2:-}"
local _msg="${3:-Waiting}"
local _sleep="${4:-1}"
local spin='-\|/'
i=0
sleep .1
local start="$SECONDS"
local took=0
local WAIT_FOR_FILE="/tmp/wait_for.$RANDOM"
while [ $(_fn_cond_rc) -ne 0 ]; do
  i=$(( (i+1) %4 ))
  local took=$(( SECONDS - start ))
  if [ -e "$WAIT_FOR_FILE" ]; then
      _msg="$(cat "$WAIT_FOR_FILE")"
  fi
  printf "\r (${took}s) $_msg ${spin:$i:1}"
  sleep $_sleep
done
rm -f "$WAIT_FOR_FILE"
green "\n OK. ${took}s $_msg"
}

# source into a subshell to pass parent environment, but avoid modifications to parent
# 1: file
do_post_install() {
if [ -f "$CDIR/_$1" ]; then
    yellow "Executing Post Install instructions for '$1'"
    ( . "$CDIR/_$1" )
fi
}

arg_required() {
    # 1: key name
    # 2: field (--key=val)
    # 3: field+1 (-key val | --key val)
    _case_one="${2##--$1=}" # --key=val
    if [[ -n $_case_one ]] && [[ "$_case_one" != "$2" ]]; then
        # --key=value
        echo "$_case_one"
        shift
    else
        # -key val | --key value
        if test "$_case_one" = "$2"; then
            test $# -lt 3 && die "Missing value for '$2'." 1
            echo "$3"
            shift
        fi
    fi
}

docker_version_num() {
echo "${1:-$DOCKER_VERSION}"|cut -d. -f1,2|sed 's~\.~~g'
}

# 1: (rcode=1)
safe_exit() {
    local rcode="${1:-1}"
    if [[ "$0" =~ bash ]]; then
        return $rcode # sourced
    else
        exit $rcode # bashed
    fi
}

# 1: string
is_valid_servicename() {
re_valid_characters='^[][0-9a-zA-Z_-]*$'
re_begins_with_ascii='^[][a-zA-Z]*$'
if [[ "$1" =~ $re_valid_characters ]] && [[ "${1:0:1}" =~ $re_begins_with_ascii ]]; then
    echo "$1"
else
    echo ""
fi
}

validate_servicename() {
    if [ -z "$(is_valid_servicename "$1")" ]; then
        red "Naming error for '$1'. Name must begin with an ascii-character and contain only a-zA-Z0-9_-"
        safe_exit 1
    fi
}

cli_version() {
# version of local CLI; prepare_cli keeps copy in /tmp/cli
local _CLI_NAME="${1:-production}"
if [ -f "/tmp/.$_CLI_NAME.cli.version" ]; then
    :
else
    cat /tmp/cli|base64|shasum -a 256|cut -d' ' -f1 > /tmp/.$_CLI_NAME.cli.version
fi
cat /tmp/.$_CLI_NAME.cli.version
}

cli_version_server() {
# version of CLI available on server
cat /opt/cli|grep ^CLI_VERSION|cut -d= -f2
}

cli_version_check_needed() {
# daily: +"%d.%m.%Y" weekly: +%V
local _CLI_NAME="$1"
local CHECKED="/tmp/.$_CLI_NAME.cli.check.$(date +%V)"
# TODO: remove old files
if [ -f "$CHECKED" ]; then
    echo ""
else
    touch "$CHECKED"
    echo "y"
fi
}

mk_virtualenv() {
if [ ! -d venv ]; then
    yellow "Creating virtualenv..."
    pip install virtualenv
    virtualenv venv 1>/dev/null
    source venv/bin/activate
    pip install ansible==2.4.2.0 awscli==1.14.1 cryptography==2.1.4 secret==0.8 markdown==2.6.11
    # awscli installs a boto3 that is too old to be compatible
    pip install boto3==1.4.8
    deactivate
fi
}

rc0_yes() {
if [[ $1 == 0 ]]; then
    echo "yes"
else
    echo ""
fi
}

is_installed() {
SYSTEMD_PAGER='' service "$1" status|grep "Loaded:"|grep ": loaded" 1>/dev/null
rc0_yes "$?"
}

is_running() {
SYSTEMD_PAGER='' service "$1" status|grep "Active:"|grep "running" 1>/dev/null
rc0_yes "$?"
}

docker_daemon_version() {
docker info 2>/dev/null|grep "Server Version"|awk '{print $3}'
}

# 1: IP
node_access_health() {
local LIMIT=4
local start=$SECONDS
SSH_FLAGS="-o ConnectTimeout=5 -o ConnectionAttempts=1" run_sudo "$1" "hostname" 1>/dev/null
local took=$(( SECONDS - start ))
R=$(if [ $took -lt $LIMIT ]; then echo "ok"; else echo ""; fi)
rg_status "$R" "$ip: Connection established in less than $LIMIT ($took) seconds."
}

condition_rds_up() {
local _R=$(aws rds describe-db-instances --db-instance-identifier="${1:-$RDS_NAME}")
local IS_AVAILABLE=$(echo $_R|jq -r '.DBInstances|first|.DBInstanceStatus')
[[ "$IS_AVAILABLE" == "available" ]]
}

is_reachable_via_curl() {
    $(curl -m 3 "$1" > /dev/null 2>&1)
}

# 1: host
# 2: IP
is_reachable_via_nc() {
nc -w 2 -G 2 "$1" "$2" &>/dev/null
}

# 1: awscli output of instance information
# 2: (port) default=80
check_reachable() {
    local _IPS="$1"
    local _PORT="${2:-80}"
    for ip in ${_IPS[@]}; do
        R=$(is_reachable_via_nc "$ip" "$_PORT")
        rg_status "$(exit_code_ok $? 0)" "$ip:$_PORT is reachable"
    done
}

install_log() {
echo "/tmp/swarm-install-rg-$RUN_ID"
}

# 1: str
# 2: n
replicate_str() {
echo $(python -c "print(\"$1\"*$2)")
}

# 1:file
create_file_if_not_exists() {
    [[ ! -f "$1" ]] && echo "" > "$1"
}

docker_version() {
sudo docker info --format '{{json .}}'|jq -r '.ServerVersion'
}

# 1: image
# 2: tag
push_image() {
( SU=true \
    . $CLI_DIR/cli.sh image:push -i $1 -t $2 )
}

# 1: image
# 2: tag
# 3: name
deploy_service() {
( SU=true \
    . $CLI_DIR/cli.sh app:deploy -i $1 -t $2 -n $3 )
}

# 1: command
run_cli() {
( SU="${SU:-true}" HOST="${HOST:-$(manager_ip)}" . $CLI_DIR/cli.sh "$@" )
}

# 1: service-name
does_service_exist() {
echo $(run_user $HOST <<EOF
docker service ls -q --filter name="$1"
EOF
)
}

get_aws_filter() {
echo "Name=tag:$PURPOSE_TAG_KEY,Values=$SWARM_TAG_VALUE Name=\"instance-state-name\",Values=\"running\""
}

get_ec2_instances() {
aws ec2 describe-instances --filter "$(get_aws_filter)"
}

condition_node_drained() {
R="$(sudo docker ps --format '{{json .}}')"
REMAINING="$(echo $R|jq -r '.Names')"
echo "( Remaining: $REMAINING )" > $WAIT_FOR_FILE
[[ "$R" == "" ]]
}

list_docker_versions() {
    echo "..."
}

docker_version_upgrade() {
NODES="$(run_cli node:json)"
MANAGERS=$(echo "$NODES"|jq -r -c -M '.|select(.manager!="")')
WORKERS=$(echo "$NODES"|jq -r -c -M '.|select(.manager=="")')
while IFS= read -r row; do
_id="$(echo $row|jq -r '.id')"
_pubip="$(echo $row|jq -r '.public_ip')"
_privip="$(echo $row|jq -r '.private_ip')"
_docker_version="$(echo $row|jq -r '.docker_version')"
if [ $(docker_version_num "$_docker_version") -eq $(docker_version_num "$DOCKER_VERSION") ]; then
    yellow "$_pubip: Already running '$DOCKER_VERSION'..."
    continue
fi
# manager
run_sudo $HOST "docker node update --availability drain $_id"
# worker
run_sudo $_pubip "wait_for condition_node_drained $_id \"$_id: Waiting to drain node...\" 5"
( HOST=$_pubip UPGRADE_DOCKER=yes . ./prepare_docker.sh )
# manager
run_sudo $HOST "docker node update --availability active $_id"
# let swarm chew on changes
sleep 5
done <<< "$WORKERS"

while IFS= read -r row; do
_id="$(echo $row|jq -r '.id')"
_pubip="$(echo $row|jq -r '.public_ip')"
_docker_version="$(echo $row|jq -r '.docker_version')"
if [ $(docker_version_num "$_docker_version") -eq $(docker_version_num "$DOCKER_VERSION") ]; then
    yellow "$_pubip: Already running '$DOCKER_VERSION'..."
    continue
fi
# manager
( HOST=$_pubip UPGRADE_DOCKER=yes . ./prepare_docker.sh )
# let swarm chew on changes
sleep 5
done <<< "$MANAGERS"
}

# HARD reboot of Docker Swarm by killing managers, then workers.
# - Used for fixing swarm ingress-networking issues (split-brain routing to alive and dead IPs)
reboot_swarm() {
NODES="$(run_cli node:json)"
MANAGERS=$(echo "$NODES"|jq -r -c -M '.|select(.manager!="")')
WORKERS=$(echo "$NODES"|jq -r -c -M '.|select(.manager=="")')
while IFS= read -r row; do
_pubip="$(echo $row|jq -r '.public_ip')"
( HOST=$_pubip FORCE_RESTART=yes . ./prepare_docker.sh )
# let swarm chew on changes
sleep 5
done <<< "$MANAGERS"

while IFS= read -r row; do
_pubip="$(echo $row|jq -r '.public_ip')"
( HOST=$_pubip FORCE_RESTART=yes . ./prepare_docker.sh )
# let swarm chew on changes
sleep 5
done <<< "$WORKERS"

# TODO: restore-services?
# TODO: rebalance
}

