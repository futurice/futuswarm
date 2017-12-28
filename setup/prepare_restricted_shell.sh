#!/usr/bin/env bash
source init.sh

cp ../server/server.sh /tmp/server

NODE_LIST="${NODE_LIST:-$(node_list|tr '\n' ' '|sed '$s/ $//')}"
NODE_LIST_PUBLIC="${NODE_LIST_PUBLIC:-$(node_list|tr '\n' ' '|sed '$s/ $//')}"
WORKER_NODES="${WORKER_NODES:-$(swarm_node_instances|jq -r '.Reservations[].Instances[]|.PrivateIpAddress'|tr '\n' ' '|sed '$s/ $//')}"
RESTART_SSH="${RESTART_SSH:-true}"

SWARM_MAP="${SWARM_MAP:-$(mk_swarm_map)}"

replaceinfile '/tmp/server' '^NODE_LIST=.*' "NODE_LIST=\"$WORKER_NODES\""
replaceinfile '/tmp/server' '^NODE_LIST_PUBLIC=.*' "NODE_LIST_PUBLIC=\"$NODE_LIST_PUBLIC\""
replaceinfile '/tmp/server' '^ADMIN_LIST=.*' "ADMIN_LIST=\"$ADMIN_LIST\""
replaceinfile '/tmp/server' '^DOMAIN=.*' "DOMAIN=\"$DOMAIN\""
replaceinfile '/tmp/server' '^OPEN_DOMAIN=.*' "OPEN_DOMAIN=\"$OPEN_DOMAIN\""
replaceinfile '/tmp/server' '^SWARM_MAP=.*' "SWARM_MAP=\"$SWARM_MAP\""
replaceinfile '/tmp/server' '^CLOUD=.*' "CLOUD=$CLOUD"
replaceinfile '/tmp/server' '^CORE_CONTAINERS=.*' "CORE_CONTAINERS=\"$CORE_CONTAINERS\""
# RDS:postgres
replaceinfile '/tmp/server' '^RDS_USER=.*' "RDS_USER=${RDS_USER:-}"
replaceinfile '/tmp/server' '^RDS_PASS=.*' "RDS_PASS='${RDS_PASS:-}'"
replaceinfile '/tmp/server' '^RDS_HOST=.*' "RDS_HOST=${RDS_HOST:-$(rds_db_host $RDS_NAME)}"
replaceinfile '/tmp/server' '^RDS_PORT=.*' "RDS_PORT=${RDS_PORT:-}"
replaceinfile '/tmp/server' '^RDS_DB_NAME=.*' "RDS_DB_NAME=${RDS_DB_NAME:-}"
# ACL
replaceinfile '/tmp/server' '^ACL_DB_NAME=.*' "ACL_DB_NAME=${ACL_DB_NAME:-}"
# aws instances
AWS_FILTER="$(get_aws_filter)"
replaceinfile '/tmp/server' 'AWS_FILTER' "$AWS_FILTER"
replaceinfile '/tmp/server' 'SWARM_NODE_LABEL_KEY' "$SWARM_NODE_LABEL_KEY"

python - <<PEOF
CS=open('commands.sh').read().replace('#!/usr/bin/env bash','')
import commands;commands.replace_block('/tmp/server','commands',CS);
PEOF

prepare_server_file() {
synchronize /tmp/server /srv/server.sh $1

RSHELL=$(cat <<EOF
"""
Match User *,!$SSH_USER
    ForceCommand /srv/server.sh
"""
EOF
)

R=$(run_sudo $1 <<EOF
chmod +x /srv/server.sh
python - <<PEOF
import os;os.chdir('/opt');import commands;commands.replace_block('/etc/ssh/sshd_config','rshell',$RSHELL)
PEOF
if [[ "$RESTART_SSH" == true ]]; then
/etc/init.d/ssh restart
fi
EOF
)
}

# prepare all nodes
for ip in ${NODE_LIST[@]}; do
    prepare_server_file $ip &
    synchronize commands.sh /opt/ $ip
    synchronize commands.py /opt/ $ip
done
wait $(jobs -p)
