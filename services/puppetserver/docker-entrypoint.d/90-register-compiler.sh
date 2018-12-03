#!/bin/bash

# Additional compilers should not run a CA, but have to register themselves
# with consul. When they are done, they need to remove themselves from
# consul; this requires a bit of shell gymnastics since this script is run
# as a separate command but needs to stick around to receive signals

cleanup() {
    echo "Unregistering $ip"
    curl -X DELETE "http://consul:8500/v1/kv/services/compiler/$ip"
}

worker() {
    trap cleanup EXIT
    while true; do
        sleep 86400
    done
}

[[ -n "$MAIN_PUPPET" ]] && exit 0

echo "turning off CA"
cat > /etc/puppetlabs/puppetserver/services.d/ca.cfg <<EOF
puppetlabs.services.ca.certificate-authority-disabled-service/certificate-authority-disabled-service
puppetlabs.trapperkeeper.services.watcher.filesystem-watch-service/filesystem-watch-service
EOF

ip=$(facter networking.ip)

# Fork this script and have it wait for a signal; dumb-init makes sure
# we'll get signals for the container forwarded to us
worker &

echo "Registering $ip"
curl -X PUT --silent -o /dev/null --data up \
     "http://consul:8500/v1/kv/services/compiler/$ip"
