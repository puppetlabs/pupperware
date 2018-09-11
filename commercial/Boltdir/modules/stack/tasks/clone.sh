#! /bin/bash

to_json() {
    printf '%s' "$1" | python -c 'import json,sys; print(json.dumps(sys.stdin.read()))'
}

die() {
    msg=$(to_json "$2")
    printf '{ "_error": { "kind": "%s", "msg": %s } }' "$1" "$msg"
    exit 1
}

if ! type -p git >/dev/null ; then
    sudo yum -y install git || die git-install "Failed to installl git"
fi

# Check that agent forwarding is turned on
if ! ssh-add -l > /dev/null; then
    die ssh-agent "Could not connect to your ssh-agent.\\n You have to set up agent forwarding and use an agent that can access https://github.com/puppetlabs/pupperware"
    exit 1
fi

if [ ! -d pupperware ]; then
    git clone git@github.com:puppetlabs/pupperware.git || die clone "Failed to clone pupperware repo"
    cd pupperware
    echo '{ "status": "cloned" }'
else
    cd pupperware
    msg=$(git pull 2>&1)
    if [[ $? != 0 ]]; then
        die pull "Failed to pull: $msg"
    fi
    msg=$(to_json "$msg")
    printf '{ "status": "pulled", "message": %s }' "$msg"
fi

# Pull the latest images
if ! docker-compose pull > /dev/null 2>&1; then
    die docker-pull "Failed to run 'docker-compose pull'"
fi
