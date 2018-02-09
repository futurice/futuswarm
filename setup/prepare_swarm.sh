#!/usr/bin/env bash
source init.sh

# publicIp,privateIp publicIp2,privateIp2 ...
SWARM_MANAGER_LIST=$(swarm_manager_instances|jq -r '.Reservations[].Instances[]|[.PublicIpAddress,.PrivateIpAddress]|@csv'|tr '\n' ' '|sed 's/"//g')
SWARM_NODE_LIST=$(swarm_node_instances|jq -r '.Reservations[].Instances[]|[.PublicIpAddress,.PrivateIpAddress]|@csv'|tr '\n' ' '|sed 's/"//g')
FORCE_NEW_CLUSTER="${FORCE_NEW_CLUSTER:-}"

FST_MAN_SERVER="$(echo $SWARM_MANAGER_LIST|cut -f1 -d' ')"
FST_MAN_PUBLIC="$(echo $FST_MAN_SERVER|cut -f1 -d,)"
FST_MAN_PRIVATE="$(echo $FST_MAN_SERVER|cut -f2 -d,)"

MANAGER_TOKEN=
NODE_TOKEN=
NODE_STATUS=
MANAGER_TOKEN_EXISTS=$(run_user $FST_MAN_PUBLIC <<EOF
docker swarm join-token manager 2>/dev/null
EOF
)
rg_status "$MANAGER_TOKEN_EXISTS" "$FST_MAN_PRIVATE is a Swarm Manager"

FORCE_NC=""
if [[ -n "$FORCE_NEW_CLUSTER" ]]; then
    red " force creating a new cluster"
    MANAGER_TOKEN_EXISTS=""
    FORCE_NC="--force-new-cluster"
fi

if [[ -n "$MANAGER_TOKEN_EXISTS" ]]; then
    :
else
    yellow " creating manager"
MANAGER_UP=$(run_user $FST_MAN_PUBLIC <<EOF
docker swarm init $FORCE_NC --listen-addr $FST_MAN_PRIVATE --advertise-addr $FST_MAN_PRIVATE
EOF
)
fi

MANAGER_TOKEN=$(run_user $FST_MAN_PUBLIC <<EOF
docker swarm join-token -q manager
EOF
)
NODE_TOKEN=$(run_user $FST_MAN_PUBLIC <<EOF
docker swarm join-token -q worker
EOF
)
NODE_STATUS=$(run_user $FST_MAN_PUBLIC <<EOF
docker node ls
EOF
)

is_part_of_swarm() {
    echo "$1"|grep "$2"|grep Ready|grep Active
}

# Join additional Managers
REMAINING_SWARM_MANAGERS="${SWARM_MANAGER_LIST/$FST_MAN_SERVER/}"
# TODO: test multi-manager setup
for ip in ${REMAINING_SWARM_MANAGERS[@]}; do
    yellow " joining as manager"
$(run_user $ip <<EOF
    docker node ls && echo "already joined" || docker swarm join --token $MANAGER_TOKEN $FST_MAN_PRIVATE:2377
EOF
)
done

# Join Nodes to Manager
for ip in ${SWARM_NODE_LIST[@]}; do
PUB_IP="$(echo $ip|cut -f1 -d,)"
PRIV_IP="$(echo $ip|cut -f2 -d,)"
R=$(is_part_of_swarm "$NODE_STATUS" "$(echo "$PRIV_IP"|tr . -)")
IS_IN="$(exit_code_ok $? 0)"
rg_status "$IS_IN" "$PRIV_IP is a Swarm Node"
if [[ -n "$FORCE_NEW_CLUSTER" ]]; then
    yellow " leaving swarm"
R=$(run_user $PUB_IP <<EOF
    docker swarm leave --force
EOF
)
    echo "   $R"
    sleep 1
    IS_IN=""
fi

if [[ -z "$IS_IN" ]]; then
    yellow " joining swarm"
R=$(run_user $PUB_IP <<EOF
    docker swarm join --token $NODE_TOKEN $FST_MAN_PRIVATE:2377
EOF
)
    echo "   $R"
fi
done

# cleanup
NODE_STATUS=$(run_user $FST_MAN_PUBLIC <<EOF
docker node ls
EOF
)
DOWNED_NODES="$(echo "$NODE_STATUS"|grep Down|awk '{print $1'})"
for n in ${DOWNED_NODES[@]}; do
    yellow " removing Downed node $n"
R=$(run_user $FST_MAN_PUBLIC <<EOF
    docker node rm --force "$n"
EOF
)
done
