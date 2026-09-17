#!/bin/sh
set -eu
cd /app
while sleep 30; do
    candidate=$(mktemp /etc/nginx/gateway/.candidate.XXXXXX)
    if ! php /app/artisan p:remote-access:nginx --no-ansi > "$candidate"; then
        rm -f "$candidate"
        echo 'Gateway refresh failed; keeping the previous configuration.' >&2
        continue
    fi
    if cmp -s "$candidate" /etc/nginx/gateway/nodes.conf; then rm -f "$candidate"; continue; fi
    cp /etc/nginx/gateway/nodes.conf /etc/nginx/gateway/.previous
    mv "$candidate" /etc/nginx/gateway/nodes.conf
    if nginx -t; then
        nginx -s reload
    else
        mv /etc/nginx/gateway/.previous /etc/nginx/gateway/nodes.conf
        echo 'Invalid gateway configuration; rolled back.' >&2
    fi
done
