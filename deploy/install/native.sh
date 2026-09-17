#!/usr/bin/env bash
# Loaded by install.sh after the repository has been downloaded.
native_env() { sed -n "s/^$1=//p" "$INSTALL_DIR/deploy/.env" | tail -n 1; }

native_dependencies() {
    . /etc/os-release
    case "$ID:$VERSION_ID" in ubuntu:24.04|debian:12|debian:13) ;; *) die 'A natív mód Ubuntu 24.04, Debian 12 vagy Debian 13 rendszert támogat. Más rendszeren válaszd a Docker módot.' ;; esac
    if command -v mysqld >/dev/null && ! mysqld --version | grep -q MariaDB; then
        die 'Meglévő MySQL telepítés található. A natív telepítő nem cseréli le; válaszd a Docker módot vagy külön tiszta gépet.'
    fi
    apt-get update
    apt-get install -y nginx mariadb-server redis-server php-fpm php-cli php-mysql php-mbstring php-xml php-curl php-zip php-bcmath php-gd composer unzip xz-utils certbot
    php -r 'exit(version_compare(PHP_VERSION, "8.2", ">=") ? 0 : 1);' || die 'Legalább PHP 8.2 szükséges.'
    systemctl enable --now mariadb redis-server
}

native_node_tools() {
    local arch version archive tools=/opt/alex-panel-tools staging
    case "$(uname -m)" in x86_64) arch=x64 ;; aarch64) arch=arm64 ;; *) die 'A frontend fordításához x86_64 vagy arm64 gép kell.' ;; esac
    mkdir -p "$tools"
    staging=$(mktemp -d "$tools/download.XXXXXX")
    curl -fsSL https://nodejs.org/dist/latest-v22.x/SHASUMS256.txt -o "$staging/SHASUMS256.txt"
    archive=$(awk -v suffix="linux-$arch.tar.xz" '$2 ~ suffix"$" {print $2}' "$staging/SHASUMS256.txt")
    [[ $archive =~ ^node-v22\.[0-9]+\.[0-9]+-linux-(x64|arm64)\.tar\.xz$ ]] || die 'Érvénytelen Node.js kiadáslista.'
    curl -fsSL "https://nodejs.org/dist/latest-v22.x/$archive" -o "$staging/$archive"
    (cd "$staging" && grep " $archive$" SHASUMS256.txt | sha256sum -c -)
    tar -xJf "$staging/$archive" -C "$staging"
    version=${archive%.tar.xz}
    export PATH="$staging/$version/bin:$PATH"
    export npm_config_cache="$INSTALL_DIR/deploy/cache/npm"
    npm install --prefix "$tools/yarn" --ignore-scripts --no-audit --no-fund yarn@1.22.22
    export PATH="$tools/yarn/node_modules/.bin:$PATH"
}

native_permissions() {
    # git checkout inherits umask 077; PHP-FPM must be able to traverse and read the app.
    find "$INSTALL_DIR" -path "$INSTALL_DIR/.git" -prune -o -path "$INSTALL_DIR/deploy" -prune -o -type d -exec chmod 755 {} +
    find "$INSTALL_DIR" -path "$INSTALL_DIR/.git" -prune -o -path "$INSTALL_DIR/deploy" -prune -o -type f ! -name .env -exec chmod a+rX {} +
    chown root:www-data "$INSTALL_DIR/deploy" "$INSTALL_DIR/deploy/.env"
    chmod 750 "$INSTALL_DIR/deploy"
    chmod 640 "$INSTALL_DIR/deploy/.env"
    mkdir -p "$INSTALL_DIR/storage/logs" "$INSTALL_DIR/storage/framework/cache/data" "$INSTALL_DIR/storage/framework/sessions" "$INSTALL_DIR/storage/framework/views" "$INSTALL_DIR/bootstrap/cache"
    chown -R www-data:www-data "$INSTALL_DIR/storage" "$INSTALL_DIR/bootstrap/cache"
}

native_artisan() { (cd "$INSTALL_DIR" && runuser -u www-data -- php "$INSTALL_DIR/artisan" "$@"); }

native_database() {
    local password
    password=$(native_env DB_PASSWORD)
    [[ $password =~ ^[a-f0-9]{64}$ ]] || die 'A natív adatbázis-beállításhoz a telepítő által generált DB_PASSWORD szükséges.'
    if [[ ! -f $INSTALL_DIR/deploy/state/native-db-owned ]]; then
        [[ $(mariadb -NBe "SELECT COUNT(*) FROM mysql.user WHERE User='alex_panel'") == 0 ]] || die 'Az alex_panel adatbázis-felhasználó már létezik, nem módosítom.'
        [[ $(mariadb -NBe "SELECT COUNT(*) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='alex_panel'") == 0 ]] || die 'Az alex_panel adatbázis már létezik, nem módosítom.'
        touch "$INSTALL_DIR/deploy/state/native-db-owned"
    fi
    # SQL is sent on stdin, never as command-line arguments containing a password.
    mariadb <<SQL
CREATE DATABASE IF NOT EXISTS alex_panel CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'alex_panel'@'localhost' IDENTIFIED BY '$password';
GRANT ALL PRIVILEGES ON alex_panel.* TO 'alex_panel'@'localhost';
SQL
}

native_nginx_config() {
    local domain tls socket listen cert=''
    domain=$(native_env PANEL_DOMAIN)
    tls=$(native_env TLS_ENABLED)
    socket="/run/php/php$(php -r 'echo PHP_MAJOR_VERSION,".",PHP_MINOR_VERSION;')-fpm.sock"
    listen='127.0.0.1:8080'
    if [[ $tls == true ]]; then
        valid_domain "$domain" || die 'Érvénytelen panel domain a mentett konfigurációban.'
        listen=80
        if [[ -f /etc/letsencrypt/live/$domain/fullchain.pem ]]; then
            listen='443 ssl'
            cert="ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem; ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;"
        fi
    else domain=localhost; fi
    mkdir -p /etc/nginx/alex-panel
    native_artisan p:remote-access:nginx --no-ansi > /etc/nginx/alex-panel/nodes.conf
    chmod 644 /etc/nginx/alex-panel/nodes.conf
    cat > /etc/nginx/sites-available/alex-panel.conf <<NGINX
server {
    listen $listen;
    $cert
    server_name $domain;
    root $INSTALL_DIR/public;
    index index.php;
    client_max_body_size 100m;
    include /etc/nginx/alex-panel/nodes.conf;
    location / { try_files \$uri \$uri/ /index.php?\$query_string; }
    location ~ \\.php$ {
        try_files \$uri =404;
        include fastcgi_params;
        fastcgi_pass unix:$socket;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
        fastcgi_param PHP_VALUE "upload_max_filesize=100M\\npost_max_size=100M";
    }
    location ~ /\\.(?!well-known) { deny all; }
}
NGINX
    if [[ -n $cert ]]; then
        cat >> /etc/nginx/sites-available/alex-panel.conf <<NGINX
server {
    listen 80;
    server_name $domain;
    root $INSTALL_DIR/public;
    location ^~ /.well-known/acme-challenge/ { try_files \$uri =404; }
    location / { return 301 https://$domain\$request_uri; }
}
NGINX
    fi
    chmod 644 /etc/nginx/sites-available/alex-panel.conf
    ln -sfn /etc/nginx/sites-available/alex-panel.conf /etc/nginx/sites-enabled/alex-panel.conf
    nginx -t
    systemctl enable --now nginx
    systemctl reload nginx
}

native_services() {
    local version
    if [[ ! -f $INSTALL_DIR/deploy/state/native-services-owned ]]; then
        [[ ! -e /etc/systemd/system/alex-panel-queue.service && ! -e /etc/nginx/sites-available/alex-panel.conf && ! -e /usr/local/sbin/alex-panel-gateway ]] || die 'Másik Alex Panel natív szolgáltatásai már léteznek. Nem írom felül őket.'
        touch "$INSTALL_DIR/deploy/state/native-services-owned"
    fi
    version=$(php -r 'echo PHP_MAJOR_VERSION,".",PHP_MINOR_VERSION;')
    systemctl enable --now "php$version-fpm"
    for kind in queue scheduler; do
        local command='queue:work --queue=high,standard,low --sleep=3 --tries=3 --timeout=120'
        [[ $kind != scheduler ]] || command='schedule:work'
        cat > "/etc/systemd/system/alex-panel-$kind.service" <<UNIT
[Unit]
Description=Alex Panel $kind
After=network.target mariadb.service redis-server.service
[Service]
User=www-data
Group=www-data
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/php $INSTALL_DIR/artisan $command
Restart=always
RestartSec=5
TimeoutStopSec=150
[Install]
WantedBy=multi-user.target
UNIT
    done
    # Nginx must regenerate its fixed upstreams after a node is created/updated.
    cat > /usr/local/sbin/alex-panel-gateway <<SCRIPT
#!/bin/bash
set -euo pipefail
cd '$INSTALL_DIR'
candidate=\$(mktemp /etc/nginx/alex-panel/candidate.XXXXXX)
trap 'rm -f "\$candidate"' EXIT
runuser -u www-data -- php '$INSTALL_DIR/artisan' p:remote-access:nginx --no-ansi > "\$candidate"
if cmp -s "\$candidate" /etc/nginx/alex-panel/nodes.conf; then exit 0; fi
cp /etc/nginx/alex-panel/nodes.conf /etc/nginx/alex-panel/previous.conf
install -m 644 "\$candidate" /etc/nginx/alex-panel/nodes.conf
if nginx -t; then systemctl reload nginx; else cp /etc/nginx/alex-panel/previous.conf /etc/nginx/alex-panel/nodes.conf; exit 1; fi
SCRIPT
    chmod 755 /usr/local/sbin/alex-panel-gateway
    cat > /etc/systemd/system/alex-panel-gateway.service <<'UNIT'
[Unit]
Description=Refresh Alex Panel Wings gateway
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/alex-panel-gateway
UNIT
    cat > /etc/systemd/system/alex-panel-gateway.timer <<'UNIT'
[Unit]
Description=Refresh Alex Panel Wings gateway every minute
[Timer]
OnBootSec=60
OnUnitActiveSec=60
[Install]
WantedBy=timers.target
UNIT
    systemctl daemon-reload
    systemctl enable --now alex-panel-queue alex-panel-scheduler alex-panel-gateway.timer
    systemctl restart alex-panel-queue alex-panel-scheduler
}

native_initialize() {
    existing
    validate_source "$INSTALL_DIR"
    [[ $INSTALL_DIR =~ ^/[a-zA-Z0-9_/-]+$ ]] || die 'A natív mód telepítési útvonala csak betűt, számot, aláhúzást és kötőjelet tartalmazhat.'
    local was_installed=false tls domain email
    [[ ! -f $INSTALL_DIR/deploy/state/installed ]] || was_installed=true
    native_dependencies
    if [[ ! -L $INSTALL_DIR/.env ]]; then
        [[ ! -e $INSTALL_DIR/.env ]] || die 'Meglévő .env fájl található, nem írom felül.'
        cat >> "$INSTALL_DIR/deploy/.env" <<'ENV'
APP_ENV=production
APP_DEBUG=false
APP_NAME="Alex Panel"
APP_LOCALE=hu
APP_ENVIRONMENT_ONLY=true
WINGS_BROWSER_MODE=proxy
DB_CONNECTION=mysql
DB_HOST=localhost
DB_DATABASE=alex_panel
DB_USERNAME=alex_panel
CACHE_STORE=redis
CACHE_DRIVER=redis
SESSION_DRIVER=redis
QUEUE_CONNECTION=redis
REDIS_HOST=127.0.0.1
ENV
        ln -s deploy/.env "$INSTALL_DIR/.env"
    fi
    native_database
    (cd "$INSTALL_DIR" && COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --no-interaction --prefer-dist --optimize-autoloader --no-scripts && composer check-platform-reqs --no-dev)
    native_node_tools
    (cd "$INSTALL_DIR" && yarn install --frozen-lockfile --non-interactive && yarn build:production)
    native_permissions
    native_artisan package:discover --no-ansi
    native_artisan config:cache --no-ansi
    native_artisan migrate --force
    if [[ $was_installed == false && ! -f $INSTALL_DIR/deploy/state/seeded ]]; then
        native_artisan db:seed --force
        touch "$INSTALL_DIR/deploy/state/seeded"
    fi
    native_services
    native_nginx_config
    tls=$(native_env TLS_ENABLED)
    if [[ $tls == true ]]; then
        domain=$(native_env PANEL_DOMAIN); email=$(native_env ACME_EMAIL)
        valid_email "$email" || die 'Érvénytelen tanúsítvány e-mail.'
        certbot certonly --webroot -w "$INSTALL_DIR/public" -d "$domain" --email "$email" --agree-tos --non-interactive --keep-until-expiring
        native_nginx_config
        mkdir -p /etc/letsencrypt/renewal-hooks/deploy
        printf '#!/bin/sh\nsystemctl reload nginx\n' > /etc/letsencrypt/renewal-hooks/deploy/alex-panel
        chmod 755 /etc/letsencrypt/renewal-hooks/deploy/alex-panel
        curl --fail --silent --show-error --resolve "$domain:443:127.0.0.1" "https://$domain/auth/login" -o /dev/null
    else curl --fail --silent --show-error http://127.0.0.1:8080/auth/login -o /dev/null; fi
    touch "$INSTALL_DIR/deploy/state/installed"
    if [[ $was_installed == false ]]; then native_artisan p:user:make --admin=1; fi
    printf '\nNatív Nginx + PHP-FPM panel elindult. Cím: %s\n' "$(native_env APP_URL)"
}

native_backup() {
    local target="$INSTALL_DIR/deploy/backups/$(date -u +%Y%m%dT%H%M%SZ)"
    mkdir -p "$target"
    cp "$INSTALL_DIR/deploy/.env" "$target/deploy.env"
    mariadb-dump --single-transaction --routines --triggers alex_panel | gzip > "$target/panel.sql.gz"
    tar -czf "$target/storage.tar.gz" -C "$INSTALL_DIR" storage
    printf 'Panelmentés: %s (a játékfájlokat külön mentsd)\n' "$target"
}
