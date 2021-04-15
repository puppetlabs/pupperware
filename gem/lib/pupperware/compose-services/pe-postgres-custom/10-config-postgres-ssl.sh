#!/bin/sh

cat << EOF > "${PGDATA}/pg_ident.conf"
# MAPNAME       SYSTEM-USERNAME         PG-USERNAME
EOF

if [ -n "${ALLOWED_CERT_NAMES}" ]; then
    for name in $(printf "%s" "${ALLOWED_CERT_NAMES}" | tr "," " "); do
        printf "usermap ${name} ${POSTGRES_USER}\n" >> "${PGDATA}/pg_ident.conf"
    done
fi

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
    "${SSLDIR}/certs/server.crt" \
    "${SSLDIR}/private_keys/server.key"
