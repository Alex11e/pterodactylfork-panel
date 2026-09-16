#!/bin/sh
set -eu
cd /app
: "${APP_KEY:?APP_KEY must be set and kept in deploy/.env}"
mkdir -p storage/logs storage/framework/cache/data storage/framework/sessions storage/framework/views bootstrap/cache /etc/nginx/gateway /run/nginx
chown -R www-data:www-data storage bootstrap/cache
su-exec www-data php artisan package:discover --no-ansi
su-exec www-data php artisan config:cache --no-ansi
if [ "${1:-}" != serve ]; then exec "$@"; fi
# No implicit database migration during restarts. The installer initializes explicitly.
php artisan p:remote-access:nginx --no-ansi > /etc/nginx/gateway/nodes.conf
nginx -t
exec supervisord -n -c /etc/supervisord.conf
