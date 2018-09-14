#! /bin/bash

die() {
    printf '{ "_error": { "kind": "%s", "msg": "%s" } }' "$1" "$2"
    exit 1
}

cd pupperware || die no-repo "run the clone task first to set up pupperware"

host=$(getent hosts $(hostname -s))
export DNS_ALT_NAMES="puppet,${host##* }"

case $PT_action in
    up)
        docker-compose up -d > /dev/null 2>&1
        if [[ "$PT_wait" = "true" ]]; then
            cont=$(docker-compose ps -q puppet)
            while [[ $(docker inspect $cont --format '{{.State.Health.Status}}') != 'healthy' ]]; do
                sleep 1
            done
        fi
        echo '{ "status": "started" }'
        ;;
    ps)
        svc=$(docker-compose ps --services)
        printf '{ "services": ["%s"] }' "${svc//$'\n'/\",\"}"
        ;;
    down)
        docker-compose down
        echo '{ "status": "stopped" }'
        ;;
    status)
        cont=$(docker-compose ps -q puppet)
        if [[ -z "$cont" ]]; then
            echo '{ "status": "down" }'
        else
            docker inspect "$cont" \
                   --format '{ "status": {{ json .State.Health.Status }} }'
        fi
        ;;
    *)
        die illegal-action "illegal action $PT_action"
        exit 1
esac
