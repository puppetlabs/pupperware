#! /bin/bash

die() {
    printf '{ "_error": { "kind": "%s", "msg": "%s" } }' "$1" "$2"
    exit 1
}

cd pupperware || die no-repo "run the clone task first to set up pupperware"

code_vol=volumes/code

if [[ -d "$code_vol" ]]; then
    sudo chown -R "$USER" "$code_vol"
    rm -rf "$code_vol"/*
fi
mkdir -p "$code_vol"/environments/production/manifests
cat > "$code_vol"/environments/production/manifests/site.pp <<'EOF'
$timestamp = strftime('%Y-%m-%dT%H:%M:%S')

node default {
  file { '/tmp/mark.txt':
    content => "Puppet ran at $timestamp\n"
  }
}
EOF
