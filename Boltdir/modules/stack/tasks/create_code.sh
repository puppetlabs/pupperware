#! /bin/bash

die() {
    printf '{ "_error": { "kind": "%s", "msg": "%s" } }' "$1" "$2"
    exit 1
}

cd pupperware || die no-repo "run the clone task first to set up pupperware"

if [[ -d code/ ]]; then
    sudo chown -R "$USER" code/
    rm -rf code/*
fi
mkdir -p code/environments/production/manifests
cat > code/environments/production/manifests/site.pp <<'EOF'
$timestamp = strftime('%Y-%m-%dT%H:%M:%S')

node default {
  file { '/tmp/mark.txt':
    content => "Puppet ran at $timestamp\n"
  }
}
EOF
