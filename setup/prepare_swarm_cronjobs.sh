#!/usr/bin/env bash
source init.sh

HOST="$HOST"
KEY="$KEY"
COMPANY="$COMPANY"

synchronize scripts/swarm_service_ls.sh /opt/ $HOST
synchronize scripts/swarm_container_backup.sh /opt/ $HOST

# TODO: regex lookups to allow modifications?
# m h dom mon dow user	command
run_sudo $HOST <<EOF
lineinfile "0 * * * * root /opt/swarm_service_ls.sh $KEY" /etc/crontab
lineinfile "5 * * * * root /opt/swarm_container_backup.sh $COMPANY $KEY" /etc/crontab
EOF
