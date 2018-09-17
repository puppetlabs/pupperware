#! /bin/bash

to_json() {
    printf '%s' "$1" | python -c 'import json,sys; print(json.dumps(sys.stdin.read()))'
}

die() {
    msg=$(to_json "$2")
    printf '{ "_error": { "kind": "%s", "msg": %s } }' "$1" "$msg"
    exit 1
}

if [ ! -f /etc/yum.repos.d/puppet5.repo ]; then
    sudo rpm -Uvh \
         https://yum.puppet.com/puppet5/puppet5-release-el-7.noarch.rpm ||
        die puppet-repo "Failed to add puppet5 yum repo"
fi

export PATH=/opt/puppetlabs/bin:$PATH

if ! type -p puppet >/dev/null; then
    sudo yum -y -q install puppet-agent || die puppet-install "Failed to install puppet-agent"
fi

sudo /opt/puppetlabs/puppet/bin/augtool -s -l /etc/hosts > /dev/null <<EOF
rm /files/etc/hosts/*[ipaddr="$PT_docker_ip" or canonical="$PT_docker_host" or alias="puppet"]
set /files/etc/hosts/01/ipaddr $PT_docker_ip
set /files/etc/hosts/01/canonical $PT_docker_host
set /files/etc/hosts/01/alias puppet
EOF
