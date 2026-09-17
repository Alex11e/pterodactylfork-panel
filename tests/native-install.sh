#!/usr/bin/env bash
set -Eeuo pipefail
[[ ${GITHUB_ACTIONS:-} == true && ${RUNNER_ENVIRONMENT:-} == github-hosted ]] || { echo 'Run only on a disposable GitHub-hosted runner.' >&2; exit 1; }
[[ $EUID == 0 ]] || { echo 'Root required on disposable runner.' >&2; exit 1; }
cd "$(dirname "$0")/.."
INSTALL_DIR=/opt/alex-panel
[[ ! -e $INSTALL_DIR ]] || exit 1
umask 077
git clone --no-hardlinks "$PWD" "$INSTALL_DIR"
cd "$INSTALL_DIR"
source ./install.sh
source deploy/install/native.sh
mkdir -p deploy/state
printf 'native\n' > deploy/state/backend
{
    printf 'APP_URL=http://localhost:8080\nAPP_KEY=base64:%s\n' "$(openssl rand -base64 32)"
    printf 'HASHIDS_SALT=%s\nDB_PASSWORD=%s\n' "$(openssl rand -hex 24)" "$(openssl rand -hex 32)"
    printf 'TLS_ENABLED=false\nAPP_TIMEZONE=Europe/Budapest\nMAIL_MAILER=log\n'
} > deploy/.env
native_artisan() {
    if [[ $1 == p:user:make ]]; then return 0; fi
    (cd "$INSTALL_DIR" && runuser -u www-data -- php "$INSTALL_DIR/artisan" "$@")
}
native_initialize
runuser -u www-data -- php "$INSTALL_DIR/artisan" --version
curl -fsS http://127.0.0.1:8080/auth/login -o /tmp/alex-native-login.html
grep -q '<html' /tmp/alex-native-login.html
before=$(sha256sum deploy/.env)
native_initialize
[[ $(sha256sum deploy/.env) == "$before" ]]
echo 'PASS: native Nginx/PHP-FPM/MariaDB/Redis install, HTTP login and preserved credentials on repeat.'

# Exercise the TLS nginx template without contacting a public certificate authority.
domain=alex-panel-ci.example.com
mkdir -p "/etc/letsencrypt/live/$domain"
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj "/CN=$domain" -addext "subjectAltName=DNS:$domain" \
    -keyout "/etc/letsencrypt/live/$domain/privkey.pem" -out "/etc/letsencrypt/live/$domain/fullchain.pem" >/dev/null 2>&1
saved_env=$(mktemp)
cp deploy/.env "$saved_env"
sed -i 's/^TLS_ENABLED=false/TLS_ENABLED=true/' deploy/.env
printf 'PANEL_DOMAIN=%s\n' "$domain" >> deploy/.env
native_nginx_config
http_status=$(curl --noproxy '*' -sS -o /dev/null -w '%{http_code}' --resolve "$domain:80:127.0.0.1" "http://$domain/auth/login" || true)
printf 'TLS HTTP redirect status: %s\n' "$http_status"
[[ $http_status == 301 ]] || { nginx -T; exit 1; }
curl --noproxy '*' -fsS --cacert "/etc/letsencrypt/live/$domain/fullchain.pem" --resolve "$domain:443:127.0.0.1" "https://$domain/auth/login" -o /dev/null
cp "$saved_env" deploy/.env
rm -f "$saved_env"
native_nginx_config
echo 'PASS: native HTTPS vhost and HTTP redirect with a local test certificate.'
source deploy/install/all-in-one.sh
install_dependencies() { docker info >/dev/null; }
all_in_one_wings <<'INPUT'
127.0.0.1
25565
2048
10240
i
INPUT
panel_artisan p:installer:node --check
echo 'PASS: native Wings systemd service and authenticated panel connection.'
token_before=$(sed -n 's/^token: //p' /etc/pterodactyl/config.yml)
all_in_one_wings <<'INPUT'
127.0.0.1
25565
2048
10240
i
INPUT
[[ $(sed -n 's/^token: //p' /etc/pterodactyl/config.yml) == "$token_before" ]]
panel_artisan p:installer:node --check
echo 'PASS: replace a running native Wings binary and preserve the node token.'
