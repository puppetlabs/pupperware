#!/bin/sh
#
# Used by a "sidecar" container to get SSL certificates for the
# parent container.
#
# Required environment variables:
#   CERTNAME      Subject name to get a certificate for
#   SSLDIR        Directory on disk to store the SSL certificates and keys
#
# Optional environment variables:
#   SSLDIR_UID             Desired owner UID of the SSLDIR
#   SSLDIR_GID             Desired group GID of the SSLDIR
#   PUPPETSERVER_HOSTNAME  Hostname of Puppet Server CA, defaults to "puppet"
#   CONSUL_ENABLED         Whether to query Consul for Puppet Server status,
#                          defaults to false
#   CONSUL_HOSTNAME        Hostname of the Consul server, defaults to "consul"
#   CONSUL_PORT            Port of Consul server, defaults to 8500

CERTNAME=${CERTNAME?}
SSLDIR=${SSLDIR?}
SSLDIR_UID=${SSLDIR_UID}
SSLDIR_GID=${SSLDIR_GID}

PUPPETSERVER_HOSTNAME="${PUPPETSERVER_HOSTNAME:-puppet}"
CONSUL_HOSTNAME="${CONSUL_HOSTNAME:-consul}"
CONSUL_PORT="${CONSUL_PORT:-8500}"

master_running() {
    if [ "$CONSUL_ENABLED" = "true" ]; then
        status=$(curl --silent --fail \
            "http://${CONSUL_HOSTNAME}:${CONSUL_PORT}/v1/health/checks/puppet" \
            | grep -q '"Status": "passing"')
        test "$?" = "0"
    else
        status=$(curl --silent --fail --insecure \
            "https://${PUPPETSERVER_HOSTNAME}:8140/status/v1/simple")
        test "$status" = "running"
    fi
}

if [ ! -f "${SSLDIR}/certs/${CERTNAME}.pem" ]; then
    while ! master_running; do
        echo "Waiting for CA to be up to get SSL certificate for ${CERTNAME}..."
        sleep 1
    done
    set -e
    SSLDIR=$SSLDIR /ssl.sh $CERTNAME

    # Set the SSLDIR ownership if a UID and GID have been provided
    if [ ! -z $SSLDIR_UID ] && [ ! -z $SSLDIR_GID ]; then
        chown -R $SSLDIR_UID:$SSLDIR_GID $SSLDIR
    fi
fi
