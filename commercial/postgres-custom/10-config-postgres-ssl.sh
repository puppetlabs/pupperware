#!/bin/sh

cat << EOF > "${PGDATA}/pg_ident.conf"
# MAPNAME       SYSTEM-USERNAME         PG-USERNAME
usermap ${PE_CONSOLE_SERVICES_CERTNAME} puppetdb
usermap ${PE_ORCHESTRATION_SERVICES_CERTNAME} puppetdb
usermap ${PUPPETDB_CERTNAME} puppetdb

EOF

# pg_hba.conf is read on server startup / after SIGHUP
# containers don't use pg_ctl, but a SQL function can be used instead
# https://www.postgresql.org/docs/9.6/config-setting.html
# psql --username=puppetdb --dbname=postgres --command "SELECT pg_reload_conf();" 2>&1
cat << EOF > "${PGDATA}/pg_hba.conf"
# TYPE  DATABASE        USER            ADDRESS                 METHOD

# "local" is for Unix domain socket connections only
local   all             all                                     trust
# IPv4 local connections:
host    all             all             127.0.0.1/32            trust
# IPv6 local connections:
host    all             all             ::1/128                 trust
# Allow replication connections from localhost, by a user with the
# replication privilege.
#local   replication     puppetdb                                trust
#host    replication     puppetdb        127.0.0.1/32            trust
#host    replication     puppetdb        ::1/128                 trust

# host all all all md5

hostssl all all all cert map=usermap
EOF

# NOTE: this does nothing when certs are pre-loaded into VOLUME
# as Postgres drops permissions with gosu when running this script
chown -R 999:999 "$SSLDIR"

# Postgres wants these files to have restricted access
chmod 600 \
    "${SSLDIR}/certs/ca.pem" \
    "${SSLDIR}/certs/${CERTNAME}.pem" \
    "${SSLDIR}/private_keys/${CERTNAME}.pem"

# for Postgres to use statically named files at default locations
# https://www.postgresql.org/docs/10/ssl-tcp.html#SSL-SERVER-FILES
# ssl_key_file
# server private key  proves server certificate was sent by the owner; does not indicate certificate owner is trustworthy
ln -s -f "${SSLDIR}/private_keys/${CERTNAME}.pem" "${PGDATA}/server.key"
# ssl_cert_file
# server certificate  sent to client to indicate server's identity
ln -s -f "${SSLDIR}/certs/${CERTNAME}.pem" "${PGDATA}/server.crt"
# ssl_ca_file
# trusted certificate authorities checks that client certificate is signed by a trusted certificate authority
ln -s -f "${SSLDIR}/certs/ca.pem" "${PGDATA}/root.crt"
# ssl_crl_file
# certificates revoked by certificate authorities client certificate must not be on this list
ln -s -f "${SSLDIR}/crl.pem" "${PGDATA}/root.crl"
