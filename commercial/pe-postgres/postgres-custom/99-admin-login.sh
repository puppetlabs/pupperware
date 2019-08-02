#!/bin/sh
#
# Temporary until we determine how to handle console username/password
# creation by end users.
#
# This will setup a default username/password of "admin/admin" so the
# PE console is accessible to the user once the stack comes up.
#
# This database update won't work until after other containers have
# started up and created the various tables/users/etc, so we have
# to put this in the background and run it until it succeeds.
#
# NOTE these admin/admin credentials are hardcoded in our shared gem too

setup_login() {
    # Print to stderr because background processes can't print to stdout
    echo "Attempting to create admin login -- ERRORs are expected/okay" >&2
    psql --username=puppetdb --dbname=pe-rbac \
        -c "UPDATE subjects SET is_revoked = 'f' WHERE login='admin' AND is_revoked = 't'"
}

try_until_success_or_timeout() {
    sleeptime=2
    timewaited=0
    timeout=600 # 10 minutes
    while true; do
        if [ $timewaited -ge $timeout ]; then
            echo "Admin login not created after $timeout seconds" >&2
            break
        fi
        if [ "$(setup_login)" = "UPDATE 1" ]; then
            echo "Admin login successfully created" >&2
            break
        fi
        sleep $sleeptime
        timewaited=$((timewaited+sleeptime))
    done
}

try_until_success_or_timeout &
