#! /bin/bash

to_json() {
    printf '%s' "$1" | python -c 'import json,sys; print(json.dumps(sys.stdin.read()))'
}

die() {
    printf '{ "_error": { "kind": "%s", "msg": "%s" } }' "$1" "$2"
    exit 1
}

export PATH=/opt/puppetlabs/bin:$PATH

FILE=/tmp/mark.txt

if [[ -f "$FILE" ]]; then
    old=$(< "$FILE")
else
    old="$FILE does not exist yet"
fi

out=$(puppet agent -t --color=false 2>&1)
rc=$?
if [[ $rc = 1 ]]; then
    out=$(to_json "$out")
    printf '{ "_error": { "kind": "agent-failed", "msg": %s } }' "$out"
    exit 1
fi

new=$(< "$FILE")
old=$(to_json "$old")
new=$(to_json "$new")
if [[ "$old" = "$new" ]]; then
    printf '{ "_error": { "msg": "file %s did not change", "details": { "old": %s, "new": %s } } }' "$FILE" "$old" "$new"
    exit 1
else
    printf '{ "old": %s, "new": %s, "rc": "%s" }' "$old" "$new" "$rc"
fi
