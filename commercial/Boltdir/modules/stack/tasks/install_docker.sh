#! /bin/bash

exec 3>&1 > /var/tmp/install.txt 2>&1

to_json() {
    printf '%s' "$1" | python -c 'import json,sys; print(json.dumps(sys.stdin.read()))'
}

COMPOSE=1.22.0
KERNEL=$(uname -s)
ARCH=$(uname -m)

set -x

test -n "$PT_compose" && COMPOSE="$PT_compose"

cd /var/tmp

sudo yum -y -q update

sudo yum -y -q install yum-utils device-mapper-persistent-data lvm2

test -f /etc/yum.repos.d/docker-ce.repo || \
    sudo yum-config-manager \
        --add-repo https://download.docker.com/linux/centos/docker-ce.repo

sudo yum -y -q install docker-ce

sudo systemctl enable docker
sudo systemctl start docker

getent group docker || sudo groupadd docker
sudo usermod -aG docker centos

if [[ ! -f /usr/local/bin/docker-compose ]]; then
    sudo curl -L https://github.com/docker/compose/releases/download/"$COMPOSE"/docker-compose-"$KERNEL"-"$ARCH" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
fi

out=$(< /var/tmp/install.txt)
js_out=$(to_json "$out")

host=$(getent hosts $(hostname))

exec 1>&3

printf '{ "out": %s, "ip": "%s", "host": "%s" }' \
       "$js_out" "${host%% *}" "${host##* }"
