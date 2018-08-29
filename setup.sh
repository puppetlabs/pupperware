#!/bin/bash

PERSISTENT_VOLUME_DIRS=(code puppet puppetdb/ssl puppetdb-postgres serverdata)

echo "Creating directories for persistent volumes..."
mkdir -p "${PERSISTENT_VOLUME_DIRS[*]}"

echo

echo "On OSX, you must now add all of the following directories to your Docker>Preferences>File Sharing:"
echo "${PERSISTENT_VOLUME_DIRS[*]}"
