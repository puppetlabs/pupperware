#!/bin/sh

# Migrates "./foo" to "./persistence/foo"
function migrate_v1() {
    local from="$1"
    local to="persistence/$1"
    if [ -d "$from" ]; then
        if [ -d "$to" ]; then
            echo "$to already exists; skipping"
        else
            echo "Moving $from to $to"
            mv "$from" "$to"
        fi
    fi
}

# Migrates "./persistence/foo" to "./volumes/foo"
function migrate_v2() {
    local from="persistence/$1"
    local to="volumes/$1"
    if [ -d "$from" ]; then
        if [ -d "$to" ]; then
            echo "$to already exists; skipping"
        else
            echo "Moving $from to $to"
            mv "$from" "$to"
        fi
    fi
}

# Moves top-level directories into persistence/*
function migrate_v1_v2() {
    echo "Migrating from v1 to v2 ..."
    if [ ! -d ./persistence/ ]; then
        echo "Creating persistence/ directory"
        mkdir persistence
    fi
    migrate_v1 code
    migrate_v1 puppet
    migrate_v1 serverdata
    migrate_v1 puppetdb
    migrate_v1 puppetdb-postgres
}

# Moves persistence/* directories into volume/*
function migrate_v2_v3() {
    echo "Migrating from v2 to v3 ..."
    if [ ! -d ./volumes/ ]; then
        echo "Creating volumes/ directory"
        mkdir volumes
    fi
    migrate_v2 code
    migrate_v2 puppet
    migrate_v2 serverdata
    migrate_v2 puppetdb
    migrate_v2 puppetdb-postgres
    if [ -d ./persistence/ ]; then
        echo "Renaming persistence/ directory to persistence_v1/"
        echo "* The persistence_v1/ directory can now be manually removed"
        mv persistence persistence_v1
    fi
}

cd /pupperware/

# Detect initial version: top-level directories
# Migrate to v2 if necessary
[ -d ./code ] && migrate_v1_v2

# Detect v2: persistence/ directory
# Migrate to v3 if necessary
[ -d ./persistence/ ] && migrate_v2_v3

echo "Migration finished"
