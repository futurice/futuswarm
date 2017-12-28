#!/usr/bin/env bash
# development vs production
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $DIR/../commands.sh 2>/dev/null||source /opt/commands.sh 2>/dev/null
#

set -u
F=/tmp/container_inspect_backups
KEY="${KEY:-service-inspect}"

create_file_if_not_exists "$F"

# loop docker services
# - local file (F) holds information on performed backups
# - each service has latest 'inspect' json stored in cloud

if [ $(docker_version_num "$(docker_version)") -lt 1706 ]; then
C="$(docker service ls|sed 1d)"
else
C="$(docker service ls --format '{{json .}}'|jq -r -M -c '{ID,Name,Image}')"
fi

while IFS= read -r line; do
    if [ $(docker_version_num "$(docker_version)") -lt 1706 ]; then
        name="$(echo $line|awk '{print $2}')"
    else
        name="$(echo $line|jq -r '.Name')"
    fi
    match="$name=$line"
    file_contains_str "$F" "$match"
    if [[ ! "$?" -eq 0 ]]; then
        SERVICE_KEY="$KEY-$name"
        INSPECT="$(docker service inspect "$name" --format '{{json .}}')"
        secret put $SERVICE_KEY "$INSPECT" -P futuswarm
    fi
    replaceOrAppendInFile $F "^$name=.*" "$match"
done <<< "$C"
