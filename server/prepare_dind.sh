#!/bin/bash
# update dind container (local Docker Swarm)
# - bash, SSH
# - user accounts
C="$NAME"
if [ -z "$NAME" ]; then
    echo "Usage: NAME=docker-container-name ./prepare_dind.sh"
    exit 1
fi


docker exec $C sh -c "apk update && apk add --no-cache sudo openssh vim bash ncurses"

docker exec $C sh -c "find /etc/passwd -type f -exec sed -i "s~/bin/ash~/bin/bash~g" {} \;"

docker cp server.sh $C:/srv/
docker exec $C sh -c "echo 'source /etc/profile' >> /root/.bashrc"

docker exec $C sh -c "ssh-keygen -A"
docker exec $C sh -c "nohup /usr/sbin/sshd > /dev/null 2>&1 &"

docker exec $C sh -c "mkdir -p /root/.ssh/ && touch /root/.ssh/authorized_keys && chmod 0600 /root/.ssh/authorized_keys"
docker cp server-key-for-tests.pub $C:/root/.ssh/authorized_keys
docker exec $C sh -c "chown -R root /root/.ssh/"

docker exec $C adduser client -D -s /bin/bash
docker exec $C passwd -u client
docker exec $C sh -c "mkdir -p /home/client/.ssh/ && touch /home/client/.ssh/authorized_keys && chmod 0600 /home/client/.ssh/authorized_keys"
docker cp server-key-for-tests.pub $C:/home/client/.ssh/authorized_keys
docker exec $C sh -c "chown -R client /home/client/.ssh/"
docker exec $C sh -c "echo 'source /etc/profile' >> /home/client/.bashrc"
docker exec $C sh -c "echo 'client ALL=(ALL) NOPASSWD: /usr/bin/docker, /usr/bin/timeout, /usr/local/bin/secret, /bin/bash' >> /etc/sudoers"

# PATH= is missing local on non-interactive shells
docker exec $C sh -c "ln -s /usr/local/bin/docker /usr/bin/docker"

# prepare_host
docker exec $C apk add --no-cache curl rsync jq python
docker exec $C sh -c "mkdir -p /opt/"
docker cp ../setup/commands.sh $C:/opt/commands.sh
docker cp ../setup/commands.py $C:/opt/commands.py

