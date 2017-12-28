#!/usr/bin/env bash
# Backup COMPANY -namespaced images from running services to a private registry
set -u
NS="$1"
KEY="$2"

F=/opt/backups

# 1:file
create_file_if_not_exists() {
    [[ ! -f "$1" ]] && echo "" > "$1"
}
create_file_if_not_exists "$F"

# 1:str 2:file
lineinfile() {
    grep -q -F "$1" "$2"
}
# 1:str 2:file
lineinfile_ensure() {
    grep -q -F "$1" $2 || echo $1 >> $2
}

C=$(secret get $KEY)
while IFS= read -r line; do
    _image="$(echo $line|jq -r '.Image')"
    if [[ -n $(echo "$_image"|grep "^$NS/") ]]; then
        lineinfile "$_image" "$F"
        if [[ ! "$?" -eq 0 ]]; then
            lineinfile_ensure "$_image" $F
            # image might not exist locally
            # TODO: log backups
            docker push "$_image"||true
        fi
    fi
done <<< "$C"
