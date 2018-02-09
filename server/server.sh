#!/usr/bin/env bash

# LOG USAGE
log="logger -t swarm"
IP=`echo $SSH_CONNECTION|cut -d " " -f 1`
export TERM=xterm-256color

#BLOCKSTARTcommands
# development
source ../setup/commands.sh 2>/dev/null||source /opt/commands.sh 2>/dev/null
#BLOCKENDcommands

if [[ "$SSH_ORIGINAL_COMMAND" == scp* ]]; then
COMMAND='{"command":"scp"}'
else
COMMAND="$(echo "$SSH_ORIGINAL_COMMAND"|b64dec)"
fi
printf -v CLIENT_COMMAND "%s" "$COMMAND"
$log $IP $USER "$CLIENT_COMMAND"||true

# GLOBALS
NODE_LIST=docker.for.mac.localhost:2223
NODE_LIST_PUBLIC="docker.for.mac.localhost:2223 docker.for.mac.localhost:2222"
ADMIN_LIST="ubuntu"
DOMAIN=localhost
OPEN_DOMAIN=
SWARM_MAP="docker.for.mac.localhost:2223,worker-1"
DEFAULT_SSH_PORT=22
DEFAULT_ENV=default
CLOUD=futuswarm
RDS_HOST=
RDS_PORT=
RDS_USER=
RDS_PASS=
RDS_DB_NAME=
ACL_DB_NAME=
CORE_CONTAINERS=
# /GLOBALS


DOCKER_DETACH=""
if [ $(docker_version_num "$(docker_version)") -lt 1710 ]; then
DOCKER_DETACH="--detach=false"
fi

mk_ssh_cmd() {
local _host="$(determine_host "$1")"
local _port="$(determine_port "$1" $SSH_PORT)"
echo "ssh -A -o Compression=no -o ServerAliveInterval=10 -o ConnectTimeout=3 -o LogLevel=ERROR -o StrictHostKeyChecking=no -p $_port $USER@$_host $SSH_ARGS"
}

node_name_to_instance() {
R=$(echo "$SWARM_MAP"|tr ' ' '\n'|grep "$1"|cut -d, -f1)
local _host=$(echo "$R"|cut -d: -f1)
local _port=$(echo "$R"|cut -d: -f2 -s)
echo "$_host,$_port"
}
node_name_to_instance_ip() {
echo $(node_name_to_instance $1|cut -d, -f1)
}
node_name_to_instance_ssh_port() {
_port=$(node_name_to_instance $1|cut -d, -f2 -s)
if [[ ! -n "$_port" ]]; then
    _port=$DEFAULT_SSH_PORT
fi
echo $_port
}


get_secrets() {
echo "$(sudo bash -c "HOME=/root/ secret config -P $_arg_name --env $_arg_env -F docker --skip-files")"
}

update_service() {
ENVIRON_VARS="$(get_secrets|sed 's/-e /--env-add /g')"
_CPU=""
_PLACEMENT=""
if [[ -n "$(is_admin)" ]]; then
    if [[ -n "$_arg_cpu" ]]; then
        _CPU="--limit-cpu=$_arg_cpu"
    fi
    if [[ -n "$_arg_placement" ]]; then
        _PLACEMENT="--placement-pref 'spread=node.labels.$_arg_placement'"
    fi
fi
sudo bash -c "HOME=/root/ docker service update $ENVIRON_VARS $_PLACEMENT --label-add com.df.serviceDomain="$(get_domains)" --with-registry-auth --image $_arg_image:$_arg_tag $_arg_name $DOCKER_DETACH" 2>/dev/null
}

get_domains() {
DOMAINS="$_arg_name.$DOMAIN"
if [[ "$_arg_open" == "true" ]]; then
    DOMAINS+=",$_arg_name.$OPEN_DOMAIN"
fi
echo "$DOMAINS"
}

image_exists() {
sudo docker images $_arg_image:$_arg_tag|sed 1d
}

verify_image_exists() {
    if [ -z "$(image_exists)" ]; then
        yellow "Image '$_arg_image:$_arg_tag' not found in swarm, trying to pull from registry..."
        sudo bash -c "HOME=/root/ docker pull $_arg_image:$_arg_tag"||true
    fi
    if [ -z "$(image_exists)" ]; then
        red "Image '$_arg_image:$_arg_tag' not found, forgot to image:push?"
        exit 1
    fi
}

restart_service() {
R=$(sudo docker service ps $_arg_name -q >&/dev/null)
if [[ "$?" == 0 ]]; then
    ENVIRON_VARS="$(get_secrets|sed 's/-e /--env-add /g')"
    sudo bash -c "HOME=/root/ docker service update $ENVIRON_VARS --force $_arg_name $DOCKER_DETACH" 2>/dev/null
fi
}

create_service() {
_CPU=1
_REPLICAS=1
_PLACEMENT="--placement-pref 'spread=node.labels.default'"
_CONSTRAINT="--constraint 'node.role == worker'"
if [[ -n "$(is_admin)" ]]; then
    if [[ -n "$_arg_cpu" ]]; then
        _LIMIT_CPU="--limit-cpu=$_arg_cpu"
    fi
    if [[ -n "$_arg_placement" ]]; then
        _PLACEMENT="--placement-pref 'spread=node.labels.$_arg_placement'"
    fi
    if [[ -n "$_arg_constraint" ]]; then
        _CONSTRAINT="--constraint 'node.role == $_arg_constraint'"
    fi
fi
if [[ -n "$_arg_replicas" ]]; then
    _REPLICAS="$_arg_replicas"
fi
ENVIRON_VARS="$(get_secrets)"
CMD=$(echo docker service create \
  --name=$_arg_name \
  --network=proxy \
  --with-registry-auth \
  "$ENVIRON_VARS" \
  -l com.df.notify=true \
  -l com.df.distribute=false \
  -l com.df.servicePath=/ \
  -l com.df.serviceDomain="$(get_domains)" \
  -l com.df.port=$_arg_port \
  $DOCKER_DETACH \
  $_LIMIT_CPU \
  --replicas=$_REPLICAS \
  "$_CONSTRAINT" \
  "$_PLACEMENT" \
  "$_arg_extra" \
  $_arg_image:$_arg_tag "$_arg_action")
sudo docker service rm $_arg_name >&/dev/null||true
sudo bash -c "HOME=/root/ $CMD" 2>/dev/null
}

push_image_to_swarm_node() {
# 1: _arg_host
# SSH tunnel for Docker Registry: CLIENT:5000 -> manager:5xxx is CLIENT:5000 [1..n] -> worker[n]:5xxx is manager:5xxx
local _host=$(echo "$1"|cut -d: -f1)
local _port=$(echo "$1"|cut -d: -f2 -s)

local remote_registry_host=$(echo "$_arg_host"|cut -d: -f1)
local remote_registry_port=$(echo "$_arg_host"|cut -d: -f2)

yellow "\nPulling '$_arg_image_tag' to '$1' from '$remote_registry_host:$remote_registry_port'..."
CMD='{"command":"image:push","host":"'$remote_registry_host':'$remote_registry_port'","image_tag":"'$_arg_image_tag'","spread":false}'
SSH_ARGS="-R $remote_registry_port:$remote_registry_host:$remote_registry_port"
if [[ $(echo $COMMAND|jq -r '.su') == true ]]; then
SU=true
fi
run_client $_host "$CMD"
}

check_image_on_swarm_node() {
local _host=$(echo "$1"|cut -d: -f1)
local _port=$(echo "$1"|cut -d: -f2 -s)

CMD='{"command":"docker:images:name","image_tag":"'$_arg_image_tag'","spread":false}'
if [[ $(echo $COMMAND|jq -r '.su') == true ]]; then
SU=true
fi
run_client $_host "$CMD"
}

parse() {
    # NOTE: remove stderr redirection for debugging
    echo $COMMAND|jq -r "$1" 2>/dev/null
}

determine_node() {
replicated_service_name="$_arg_name.1"
CONTAINER_DATA=$(sudo docker service ps --format '{{json .}}' $_arg_name 2>/dev/null|jq -s ".|map(select(.Name == \"$replicated_service_name\" and .DesiredState == \"Running\"))|first // empty")
if [[ ! -n "$CONTAINER_DATA" ]]; then
    yellow "Service '$_arg_name' not found (or down). Did you mistype the service name?"
    exit 1
fi
CONTAINER_NAME=$(echo $CONTAINER_DATA|jq -r '.Name')
NODE_NAME=$(echo $CONTAINER_DATA|jq -r '.Node')
CONTAINER_NODE_IP=$(node_name_to_instance_ip $NODE_NAME)
CONTAINER_NODE_SSH_PORT=$(node_name_to_instance_ssh_port $NODE_NAME)
}

# RESTRICTED COMMANDSET FOR CLIENTS
_arg_env=$(parse '.env // empty')
_arg_name=$(parse '.name // empty')
_arg_cmd=$(parse '.command')
_arg_action=$(parse '.action // empty')
_arg_key=$(parse '.key')
_arg_extra=$(parse '.extra // empty')
_arg_image=$(parse '.image')
_arg_tag=$(parse '.tag')
_arg_image_tag=$(parse '.image_tag')
_arg_host=$(parse '.host')
_arg_port=$(parse '.port')
_arg_size=$(parse '.size // empty')
_arg_volume_name=$(parse '.volume_name')
_arg_open=$(parse '.open // empty')
_arg_version=$(parse '.version // empty')
_arg_node=$(parse '.node // empty')
_arg_user=$(parse '.user // empty')
_arg_cpu=$(parse '.cpu // empty')
_arg_placement=$(parse '.placement // empty')
_arg_async=$(parse '.async // empty')
_arg_replicas=$(parse '.replicas // empty')
_arg_password=$(parse '.password // empty')

# default values when unspecified
if [[ "$_arg_size" == "" ]]; then
_arg_size=1
fi
if [[ "$_arg_env" == "" ]]; then
_arg_env=$DEFAULT_ENV
fi

admin_required() {
if [[ -z $(is_admin) ]]; then
    red "Admin access required."
    exit 1
fi
}

if [[ -n "$_arg_async" ]]; then
    DOCKER_DETACH="--detach"
fi

is_admin() {
is_in_list "$USER" "$ADMIN_LIST"
}

cando() {
SERVICE_USERS_LIST="$(acl_rds_exec "$(acl_list_service_users "$_arg_name")"|paste -s -d ' ' -)"
if [[ -z "$SERVICE_USERS_LIST" || $(is_in_list "$USER" "$SERVICE_USERS_LIST") == "y" || -n $(is_admin) ]]; then
    :
else
    red "Unauthorized. Ask owner/admins (see acl:user:list and admin:list) to give you '$USER' rights to work '$_arg_name' service."
    exit 1
fi
}

# -A --no-align
# -F --field-separator
# 1: sql
acl_rds_exec() {
PGPASSWORD="$RDS_PASS" psql -t -h "$RDS_HOST" -p "$RDS_PORT" -U "$RDS_USER" "$ACL_DB_NAME" -F ',' -A <<EOF
$1
EOF
}

# 1: service
acl_list_service_users() {
echo "SELECT username FROM acl WHERE service='$1';"
}
# 1: username
acl_list_user_services() {
echo "SELECT service FROM acl WHERE username='$1';"
}
# 1: username 2: service
acl_add_user() {
echo "INSERT INTO acl (username, service) VALUES ('$1','$2') ON CONFLICT DO NOTHING;"
}
# 1: username
_acl_add_user() {
acl_rds_exec "$(acl_add_user "$1" "$_arg_name")"
}
# 1: username 2: service
acl_rm_user() {
echo "DELETE FROM acl WHERE username='$1' AND service='$2';"
}

docker_stats() {
R="$(sudo docker stats --no-stream --format '{{.Name}} {{.Container}} {{.CPUPerc}} {{.MemUsage}} {{.MemPerc}} {{.NetIO}}')"
# prettyprint
R="$(echo "$R"|sed 's~ / ~/~g')"
O=""
while IFS= read -r row; do
_long="$(echo "$row"|cut -d' '  -f1)"
_short="$(echo "$_long"|cut -d. -f1)"
if [ -z "$_short" ]; then
    continue
fi
O+="\n$(echo "$row"|sed s~$_long~$_short~g)"
done < <(echo "$R")
echo "$O"
}

get_instances() {
sudo bash -c "HOME=/root/ aws ec2 describe-instances --filter AWS_FILTER"
}

node_json() {
DOCKER_NODES="$(sudo docker node ls --format '{{json .}}')"
INSTANCES="$(get_instances)"
local T=""
while IFS= read -r row; do
NODE_ID="$(echo $row|jq -r '.ID')"
IS_MANAGER="$(echo $row|jq -r '.ManagerStatus // empty')"
NODE_DATA="$(sudo docker node inspect $NODE_ID --format '{{json .}}')"
NODE_PRIVATE_IP="$(echo "$NODE_DATA"|jq -r '.Status.Addr')"
AWS_DATA="$(echo "$INSTANCES"|jq ".Reservations[].Instances[]|select(.PrivateIpAddress==\"$NODE_PRIVATE_IP\")")"
NODE_PUBLIC_IP="$(echo "$AWS_DATA"|jq -r -c '. as $r | {v: [$r.Tags[]|select(.Key=="SWARM_NODE_LABEL_KEY")|.Value]|first} as $nl | $r.PublicIpAddress'|paste -s -d ' ' -|sed 's~null~~g')"
_DOCKER_VERSION="$(docker_version_num $(echo "$NODE_DATA"|jq -r '.Description.Engine.EngineVersion'))"
_NUM_CONTAINERS="$(num_containers "$NODE_ID")"
T+='{"id":"'$NODE_ID'","private_ip":"'$NODE_PRIVATE_IP'","public_ip":"'$NODE_PUBLIC_IP'","manager":"'$IS_MANAGER'","docker_version":"'$_DOCKER_VERSION'","services_total":"'$_NUM_CONTAINERS'"}'
done < <(echo "$DOCKER_NODES")
echo "$T"
}

# manager checks worker for # of running containers
num_containers() {
R="$(sudo docker node ps $1 --filter desired-state=running --format '{{json .}}')"
if [[ "$R" == "" ]]; then
echo 0
else
echo $(echo "$R"|wc -l)
fi
}

ec2_information() {
DOCKER_NODES="$(sudo docker node ls --format '{{json .}}')"
INSTANCES="$(get_instances)"
local T="Id Status Avail. MgrStatus NodeLabel EC2Id Name EC2Type PublicIp PrivateIp EC2Tag #Services Version"

while IFS= read -r row; do
NODE_ID="$(echo $row|jq -r '.ID')"
IS_MANAGER="$(echo $row|jq -r '.ManagerStatus')"
NODE_STATUS="$(echo $row|jq -r '.Status')"
NODE_AVAILABILITY="$(echo $row|jq -r '.Availability')"
NODE_DATA="$(sudo docker node inspect $NODE_ID --format '{{json .}}')"
NODE_PRIVATE_IP="$(echo "$NODE_DATA"|jq -r '.Status.Addr')"
NODE_LABEL="$(echo "$NODE_DATA"|jq -r -c '.Spec.Labels')"
AWS_DATA="$(echo "$INSTANCES"|jq ".Reservations[].Instances[]|select(.PrivateIpAddress==\"$NODE_PRIVATE_IP\")")"
_DOCKER_VERSION="$(docker_version_num $(echo "$NODE_DATA"|jq -r '.Description.Engine.EngineVersion'))"
_NUM_CONTAINERS="$(num_containers "$NODE_ID")"
_ROW="$(echo "$AWS_DATA"|jq -r -c '. as $r | {v: [$r.Tags[]|select(.Key=="SWARM_NODE_LABEL_KEY")|.Value]|first} as $nl | $r.InstanceId,$r.KeyName,$r.InstanceType,$r.PublicIpAddress,$r.PrivateIpAddress,$nl.v'|paste -s -d ' ' -|sed 's~null~~g')"
T+="\n$(echo $NODE_ID|cut -c1-8) $NODE_STATUS $NODE_AVAILABILITY $IS_MANAGER $NODE_LABEL $_ROW $_NUM_CONTAINERS $_DOCKER_VERSION"
done < <(echo "$DOCKER_NODES")

echo -e "$T"|column -n -t -s ' '
}

default_node_tagging() {
# add node.label=default to every worker node without a configured label
DOCKER_NODES="$(sudo docker node ls --format '{{json .}}')"
INSTANCES="$(get_instances)"
while IFS= read -r row; do
NODE_ID="$(echo $row|jq -r '.ID')"
IS_MANAGER="$(echo $row|jq -r '.ManagerStatus // empty')"
NODE_DATA="$(sudo docker node inspect $NODE_ID --format '{{json .}}')"
NODE_PRIVATE_IP="$(echo "$NODE_DATA"|jq -r '.Status.Addr')"
AWS_DATA="$(echo "$INSTANCES"|jq ".Reservations[].Instances[]|select(.PrivateIpAddress==\"$NODE_PRIVATE_IP\")")"
TAG="$(echo "$AWS_DATA"|jq -r -c '. as $r | {v: [$r.Tags[]|select(.Key=="SWARM_NODE_LABEL_KEY")|.Value]|first} as $nl|$nl.v'|sed 's~null~~g')"
_LABEL="${TAG:-default}"
if [ -z "$IS_MANAGER" ]; then
    sudo docker node update --label-add "$_LABEL" "$NODE_ID"
    sleep .1
fi
done < <(echo "$DOCKER_NODES")
}

schema_exists() {
R=$(PGPASSWORD="$RDS_PASS" psql -t -h "$RDS_HOST" -p "$RDS_PORT" -U "$RDS_USER" "$RDS_DB_NAME" <<EOF
select exists(select nspname from pg_catalog.pg_namespace where nspname = '$1');
EOF
)
_EXISTS=
if [[ "$R" == *t* ]]; then
    _EXISTS="t"
fi
echo "$_EXISTS"
}

docker_secret_env() {
echo "docker-secret"
}

docker_secret_version() {
if [[ "$_arg_version" == "" ]]; then
echo ""
else
echo "--version $_arg_version"
fi
}

add_user() {
EXISTS=$(id -u "$_arg_user" 2>/dev/null)
if [[ "$?" == 0 ]]; then
    red "User '$_arg_user' already exists on $(hostname)"
    exit 1
fi
sudo bash -c "adduser --disabled-password --gecos \"\" --shell /bin/bash \"$_arg_user\" 1>/dev/null"
sudo bash -c "mkdir -p /home/$_arg_user/.ssh/ && touch /home/$_arg_user/.ssh/authorized_keys && chmod 0600 /home/$_arg_user/.ssh/authorized_keys && chown -R $_arg_user /home/$_arg_user"
sudo bash -c "echo \"$_arg_key\" > /home/$_arg_user/.ssh/authorized_keys"
sudo bash -c "echo \"$_arg_user ALL=(ALL) NOPASSWD: /usr/bin/docker, /usr/bin/timeout, /usr/local/bin/secret, /bin/bash\" >> /etc/sudoers"
}

rm_user() {
sudo bash -c "userdel -r"
}

change_user_pubkey() {
sudo bash -c "echo \"$_arg_key\" > /home/$_arg_user/.ssh/authorized_keys"
}

mk_rdsurl() {
_SCHEMA="$1"
_PASS="$2"
_DB="${3:-$RDS_DB_NAME}"
_RDS_PORT=
if [ "$RDS_PORT" -ne 5432 ]; then
    _RDS_PORT=":$RDS_PORT"
fi
echo "postgresql://$_SCHEMA:$_PASS@${RDS_HOST}${_RDS_PORT}/$_DB"
}

case "$_arg_cmd" in
    "docker:ps")
        sudo docker ps
        ;;
    "docker:images")
        sudo docker images
        ;;
    "docker:images:name")
        sudo docker images $_arg_image_tag &
        if [[ $(echo $COMMAND|jq -r '.spread') == true ]]; then
            for ip in ${NODE_LIST[@]}; do
                R=$(check_image_on_swarm_node $ip &)
                echo -e "$ip:\n$(echo -e "$R"|sed 1d)"
            done
        fi
        wait $(jobs -p)
        ;;
    "docker:service")
        sudo docker service $_arg_cmd
        ;;
    "swarm:node:ips")
        M='{"nodes":"'$NODE_LIST_PUBLIC'"}'
        echo "$M"
        ;;
    "image:push")
        pull_local() {
            sudo bash -c "HOME=/root/ docker pull \"$_arg_host/$_arg_image_tag\""
            sudo bash -c "HOME=/root/ docker tag \"$_arg_host/$_arg_image_tag\" \"$_arg_image_tag\""
        }
        pull_local &
        if [[ $(echo $COMMAND|jq -r '.spread') == true ]]; then
            for ip in ${NODE_LIST[@]}; do
                push_image_to_swarm_node $ip &
            done
        fi
        wait $(jobs -p)
        ;;
    "config:set")
        cando
        while IFS= read -r key &&
              IFS= read -r value; do
          sudo bash -c "HOME=/root/ secret put $key '$value' --env $_arg_env -P $_arg_name"
        done < <(echo $COMMAND|jq -r '.keys[]|(.key,.value)')
        restart_service
        ;;
    "config:get")
        cando
        sudo bash -c "HOME=/root/ secret get $_arg_key --env $_arg_env -P $_arg_name"
        ;;
    "config")
        cando
        sudo bash -c "HOME=/root/ secret config --env $_arg_env -P $_arg_name"
        ;;
    "config:unset")
        cando
        sudo bash -c "HOME=/root/ secret rm $_arg_key --env $_arg_env -P $_arg_name"
        restart_service
        ;;

    "secret:set")
        cando
        while IFS= read -r key &&
              IFS= read -r value; do
            NAME="$key"
            NAMESPACED_NAME="${_arg_name}_$key"
            NAME_VERSION="${_arg_name}_${key}_v${_arg_version}" # [\w_. that ends in alphanumeric char]
            SECRET_FILE="/tmp/$NAMESPACED_NAME"

            # TODO: if secret exists in Swarm, skip create commands
            sudo bash -c "HOME=/root/ secret put $key $SECRET_FILE --env $(docker_secret_env) -P $_arg_name $(docker_secret_version)"
            sudo docker secret create $NAME_VERSION $SECRET_FILE

            SECRET_OLD=$(sudo docker service inspect $_arg_name|jq -r ".[] // first|.Spec.TaskTemplate.ContainerSpec.Secrets[]|select(.File.Name==\"$NAME\")|.SecretName // empty")

            ROTATE_SECRET=""
            if [[ ! -z "$SECRET_OLD" ]]; then
                ROTATE_SECRET="--secret-rm $SECRET_OLD"
            fi

            # removes old secret pointed to target and adds the new version
            yellow "Adding secret source=$NAME_VERSION,target=$NAME"
            sudo docker service update \
                 $ROTATE_SECRET --secret-add source=$NAME_VERSION,target=$NAME \
                 $DOCKER_DETACH \
                 $_arg_name

            sudo bash -c "rm $SECRET_FILE"
        done < <(echo $COMMAND|jq -r '.keys[]|(.key,.value)')
        ;;
    "secret:get")
        cando
        sudo bash -c "HOME=/root/ secret get $_arg_key --env $(docker_secret_env) -P $_arg_name $(docker_secret_version)"
        ;;
    "secret")
        cando
        yellow "Stored secrets"
        sudo bash -c "HOME=/root/ secret ls --env $(docker_secret_env) -P $_arg_name"

        yellow "All versions of secrets in Swarm"
        sudo docker secret ls|grep " ${_arg_name}_"

        yellow "Active secrets [Name, Version]"
        sudo docker service inspect $_arg_name|jq -r '.[] // first|.Spec.TaskTemplate.ContainerSpec.Secrets[]?|[.File.Name,.SecretName]|@text'
        ;;
    "secret:unset")
        cando
        sudo bash -c "HOME=/root/ secret rm $_arg_key --env $(docker_secret_env) -P $_arg_name"
        sudo docker service update \
             --secret-rm $_arg_key  \
             $DOCKER_DETACH \
             $_arg_name
        ALL_VERSIONS="$(sudo docker secret ls|grep " ${_arg_name}_${_arg_key}_"|awk '{print $2}')"
        yellow "Removing known versions of secret '$_arg_key'"
        while IFS= read -r key; do
            sudo docker secret rm $key
        done < <(echo $ALL_VERSIONS)
        ;;

    "swarm:node:list")
        yellow "Swarm Node information"
        ec2_information
        ;;
    "swarm:node:stats")
        yellow "Container statistics"
        tmp_dir="$(mktemp -d -p /dev/shm)"
        $(docker_stats > "$tmp_dir/m.$RANDOM") &
        for ip in ${NODE_LIST[@]}; do
            $(run_client $ip '{"command":"swarm:node:stats_single"}' > "$tmp_dir/$RANDOM.$RANDOM") &
        done
        wait $(jobs -p)

        T="Name ContainerId Cpu% MemUsage/Limit Mem% NetI/O"
        T+="$(cat "$tmp_dir"/*)"
        echo -e "$T"|sort -k3 -r|column -n -t -s ' '
        rm -rf "$tmp_dir"
        ;;
    "swarm:node:stats_single")
        docker_stats
        ;;
    "swarm:node:location")
        determine_node
        echo "'$_arg_name': ContainerName: $CONTAINER_NAME ContainerIP: $CONTAINER_NODE_IP"
        ;;
    "swarm:node:label:add")
        admin_required
        sudo docker node update --label-add "$_arg_key" "$_arg_node"
        ;;
    "swarm:node:label:rm")
        admin_required
        sudo docker node update --label-rm "$_arg_key" "$_arg_node"
        ;;
    "app:logs")
        cando
        sudo timeout 5 docker service logs -t --tail 500 $_arg_name
        ;;
    "app:inspect")
        cando
        sudo docker service inspect $_arg_name --pretty
        ;;
    "app:status")
        if [[ -n "$_arg_name" ]]; then
            _trunc=$([[ "$(parse '.trunc // empty')" == "--no-trunc" ]] && echo '--no-trunc' || echo '')
            sudo docker service ps $_arg_name $_trunc
        else
            sudo docker service ls
        fi
        ;;
    "app:deploy")
        SERVICES=$(sudo docker service ls)
        SERVICE_EXISTS="$(echo "$SERVICES"|awk '{print $2}'|grep -w ^$_arg_name\$)"

        verify_image_exists

        if [[ -n "$SERVICE_EXISTS" ]]; then
            cando
            yellow "Service '$_arg_name' found, updating..."
            update_service
        else
            yellow "Service '$_arg_name' not found, creating..."
            _acl_add_user "$USER" 1> /dev/null
            create_service
        fi
        if [[ "$?" -eq 0 ]]; then
            yellow "=> Done! See https://$_arg_name.$DOMAIN"
        else
            red "deployment failed"
        fi
        ;;
    "app:restart")
        cando
        restart_service
        ;;
    "app:remove")
        cando
        if [[ -z $(is_admin) ]]; then
            if [[ $(is_in_list "$_arg_name" "$CORE_CONTAINERS") == "y" ]]; then
                red "Unauthorized to remove a core service"
                exit 1
            fi
        fi
        sudo docker service rm $_arg_name
        ;;
    "app:run")
        cando
        determine_node
        CMD='{"command":"app:run:exec","name":"'$CONTAINER_NAME'","action":"'$_arg_action'"}'
        SSH_ARGS="-p $CONTAINER_NODE_SSH_PORT" run_client $CONTAINER_NODE_IP "$CMD"
        ;;
    "app:run:exec")
        sudo docker exec \
            $(sudo docker ps --format '{{json .}}'|jq -r 'select(.Names|startswith("'$_arg_name'"))|.ID') \
            sh -c "$_arg_action"
        ;;
    "app:shell")
        # TODO: configurable shell (sh/bash)?
        # TODO: replication support, choose a node?
        cando
        determine_node
        CMD='{"command":"app:shell:exec","name":"'$CONTAINER_NAME'"}'
        SSH_ARGS="-p $CONTAINER_NODE_SSH_PORT -tt" run_client $CONTAINER_NODE_IP $CMD
        ;;
    "app:shell:exec")
        sudo docker exec -it \
            $(sudo docker ps --format '{{json .}}'|jq -r 'select(.Names|startswith("'$_arg_name'"))|.ID') \
            sh
        ;;
    "volume:create:ebs")
        cando
        sudo docker volume create --driver=rexray --name="${CLOUD}_${_arg_name}_${_arg_volume_name}" -o size=$_arg_size
        ;;
    "volume:rm:ebs")
        cando
        sudo docker volume rm -f --name="${CLOUD}_${_arg_name}_${_arg_volume_name}"
        ;;
    "volume:list")
        VS=$(sudo docker volume ls)
        echo "$VS"|head -n1
        echo "$VS"|grep "${CLOUD}_${_arg_name}"
        ;;
    "db:create:postgres")
        cando
SCHEMA="$_arg_name"
if [[ "$SCHEMA" == "$RDS_DB_NAME" ]]; then
    red "Schema can not be named '$RDS_DB_NAME'"
    exit 1
fi
if [[ $(schema_exists "$SCHEMA") == "t" ]]; then
    red "Schema '$SCHEMA' already exists"
    exit 1
fi
PASS="$(openssl rand -base64 24|base64|cut -c1-22)"
RDS_URL="$(mk_rdsurl "$SCHEMA" "$PASS")"
yellow "Creating '$RDS_URL'"
PGPASSWORD="$RDS_PASS" psql -h "$RDS_HOST" -p "$RDS_PORT" -U "$RDS_USER" "$RDS_DB_NAME" 1>/dev/null <<EOF
create schema "$SCHEMA";
create role "$SCHEMA" with password '$PASS' login;
grant usage on schema "$SCHEMA" to "$SCHEMA";
grant create on schema "$SCHEMA" to "$SCHEMA";
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA "$SCHEMA" TO "$SCHEMA";
ALTER SCHEMA "$SCHEMA" OWNER TO "$SCHEMA";
EOF
yellow "Adding usage information to service configuration..."
sudo bash -c "HOME=/root/ secret put DB_HOST '$RDS_HOST' --env $_arg_env -P $_arg_name" 1>/dev/null &
sudo bash -c "HOME=/root/ secret put DB_PORT '$RDS_PORT' --env $_arg_env -P $_arg_name" 1>/dev/null &
sudo bash -c "HOME=/root/ secret put DB_USER '$SCHEMA' --env $_arg_env -P $_arg_name" 1>/dev/null &
sudo bash -c "HOME=/root/ secret put DB_PASS '$PASS' --env $_arg_env -P $_arg_name" 1>/dev/null &
sudo bash -c "HOME=/root/ secret put DB_NAME '$RDS_DB_NAME' --env $_arg_env -P $_arg_name" 1>/dev/null &
sudo bash -c "HOME=/root/ secret put DB_URL '$RDS_URL' --env $_arg_env -P $_arg_name" 1>/dev/null &
wait $(jobs -p)
        ;;
    "db:drop:postgres")
yellow "Removing db:postgres '$_arg_name'"
cando
RDS_URL="$(mk_rdsurl "$_arg_name" "$_arg_password")"
PGPASSWORD="$_arg_password" psql $RDS_URL 1>/dev/null <<EOF
drop schema "$_arg_name" cascade;
EOF
PGPASSWORD="$RDS_PASS" psql -h "$RDS_HOST" -p "$RDS_PORT" -U "$RDS_USER" "$RDS_DB_NAME" 1>/dev/null <<EOF
drop role "$_arg_name";
EOF
        ;;
    "acl:user:add")
        cando
        _acl_add_user "$_arg_key" 1> /dev/null
        yellow "User '$_arg_key' added to service '$_arg_name'"
        ;;
    "acl:user:rm")
        cando
        acl_rds_exec "$(acl_rm_user "$_arg_key" "$_arg_name")" 1> /dev/null
        yellow "User '$_arg_key' removed from service '$_arg_name'"
        ;;
    "acl:user:list")
        acl_rds_exec "$(acl_list_service_users "$_arg_name")"
        ;;
    "acl:user:services")
        acl_rds_exec "$(acl_list_user_services "$_arg_key")"
        ;;
    "admin:list")
        echo "$ADMIN_LIST"
        ;;
    "admin:swarm:usage")
        yellow "Recent usage"
        allow_user_or_abort
        sudo tail -n10000 /var/log/syslog|grep command
        ;;
    "admin:swarm:restart")
        yellow "Restarting the Docker Swarm. First workers then managers."
        allow_user_or_abort
        for ip in ${NODE_LIST[@]}; do
            run_client $ip '{"command":"admin:swarm:restart:self"}'
            sleep 5
        done
        yellow "Restarting Docker Manager."
        sudo service docker restart
        ;;
    "admin:swarm:restart:self")
        DI=$(sudo docker info --format '{{json .}}')
        yellow "Restarting Docker Node. Hostname: $(hostname) NodeID: $(echo $DI|jq -r '.Swarm.NodeID')"
        allow_user_or_abort
        sudo service docker restart
        ;;
    "admin:user:add")
        admin_required
        yellow "Adding '$_arg_user' to users"
        add_user
        DO='{"command":"admin:user:add:self","user":"'$_arg_user'","key":"'$_arg_key'"}'
        for ip in ${NODE_LIST[@]}; do
            SU=1 run_client $ip "$DO"
        done
        ;;
    "admin:user:add:self")
        admin_required
        add_user
        ;;
    "admin:user:rm")
        admin_required
        yellow "Removing '$_arg_user' from users"
        rm_user
        DO='{"command":"admin:user:rm:self","user":"'$_arg_user'"}'
        for ip in ${NODE_LIST[@]}; do
            SU=1 run_client $ip "$DO"
        done
        ;;
    "admin:user:rm:self")
        admin_required
        rm_user
        ;;
    "admin:user:key:set")
        admin_required
        yellow "Modifying public key for '$_arg_user'"
        change_user_pubkey
        DO='{"command":"admin:user:key:set:self","user":"'$_arg_user'","key":"'$_arg_key'"}'
        for ip in ${NODE_LIST[@]}; do
            SU=1 run_client $ip "$DO"
        done
        ;;
    "admin:user:key:set:self")
        admin_required
        change_user_pubkey
        ;;
    "admin:node:default_tags")
        admin_required
        default_node_tagging
        ;;
    "cli:version-check")
        CV="$(cli_version_server)"
        if [[ "$CV" == "$_arg_version" ]]; then
            green "You have the most recent CLI installed"
        else
            yellow "Newer CLI available at https://$DOMAIN (version mismatch: $(echo "$_arg_version"|cut -c -8) != $(echo "$CV"|cut -c -8)) "
        fi
        ;;
    "swarm:network:health")
        _SERVICE="${_arg_name:-futuswarm}"
        _PORT="${_arg_port:-8000}"
        yellow "Checking Docker Swarm networking health"
        yellow "HTTP GET from futuswarm-health (manager) => $_SERVICE:$_PORT"
        FS_HEALTH_ID="$(sudo docker ps|grep futuswarm-health:|awk '{print $1}')"
        R="$(sudo docker exec "$FS_HEALTH_ID" curl -s "localhost:8000/check?service=$_SERVICE&port=$_PORT")"
        if [[ "$R" == "200" ]]; then
            green "Healthy: $R"
        else
            red "Connection issues: $R"
        fi
        ;;
    "node:json")
        node_json
        ;;
    "scp")
        sudo bash -c "$SSH_ORIGINAL_COMMAND"
        ;;
    *)
        if [[ -n "$(is_admin)" ]]; then
            exec $COMMAND
        else
            echo "Unrecognized command: $_arg_cmd"
            exit 1
        fi
        ;;
esac

