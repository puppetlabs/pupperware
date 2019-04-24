#! /bin/bash

cd pupperware || exit 1

body=$(printf '{ "query": "nodes { certname = \\"%s\\" }" }' "$PT_agent")

out=""
while [ -z "$out" ]; do
    out=$(docker-compose exec -T puppet \
                         curl -s -X POST http://puppetdb.internal:8080/pdb/query/v4 \
                         -H 'Content-Type:application/json' \
                         -d "$body")
    if [ -z "$out" ]; then
        sleep 1
    fi
done
printf '{ "nodes": %s }' "$out"
