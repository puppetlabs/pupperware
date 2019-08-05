#!/bin/sh

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
        sleep 1
    done

    # Can't use DNS alt names because the version of openssl
    # available on this postgres image isn't new enough to
    # support the flags that ssl.sh uses
    /ssl.sh "$CERTNAME"

    chown -R "$SSLDIR_UID":"$SSLDIR_GID" "$SSLDIR"

    # Postgres wants these files to have restricted access
    chmod 600 \
        "${SSLDIR}/certs/ca.pem" \
        "${SSLDIR}/certs/${CERTNAME}.pem" \
        "${SSLDIR}/private_keys/${CERTNAME}.pem"
fi
