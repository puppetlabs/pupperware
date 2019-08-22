#!/bin/sh

set -x
set -e

# our last entrypoint script unlocks admin account, so wait for that
psql --dbname=pe-rbac --username=puppetdb --variable=ON_ERROR_STOP=1 <<EOF
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM subjects WHERE login = 'admin' AND is_revoked = 'f') THEN
    RAISE EXCEPTION 'admin account is still revoked';
  END IF;
END;
\$\$ LANGUAGE plpgsql;
EOF
