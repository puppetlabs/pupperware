#!/bin/sh

SSLDIR=/etc/postgresql/ssl
CERTNAME=${CERTNAME:-${HOSTNAME}}

# Wait for the sidecar container to volume-mount our cert
while [ ! -f "${SSLDIR}/certs/${CERTNAME}.pem" ]; do
  echo "Waiting for my SSL certificate (${SSLDIR}/certs/${CERTNAME}.pem) ..."
  sleep 1
done

# Postgres wants these files to have restricted access
chmod 600 \
    "${SSLDIR}/certs/ca.pem" \
    "${SSLDIR}/certs/${CERTNAME}.pem" \
    "${SSLDIR}/private_keys/${CERTNAME}.pem"
