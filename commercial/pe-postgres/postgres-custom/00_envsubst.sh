#!/bin/sh

# NOTE: define ENV variables and defaults in the Dockerfile

for f in /etc/postgresql/config/*; do
    envsubst < "$f" > "${f}.new"
    mv --force "${f}.new" "$f"
done
