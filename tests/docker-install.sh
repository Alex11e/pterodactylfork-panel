#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")/.."
source ./install.sh
INSTALL_DIR=$PWD
[[ ! -f deploy/.env ]] || die 'Docker smoke test requires a disposable checkout without deploy/.env.'
mkdir -p deploy/state
{
    printf 'APP_URL=http://localhost:8080\nAPP_KEY=base64:%s\n' "$(openssl rand -base64 32)"
    printf 'HASHIDS_SALT=%s\nDB_PASSWORD=%s\nDB_ROOT_PASSWORD=%s\n' "$(openssl rand -hex 24)" "$(openssl rand -hex 24)" "$(openssl rand -hex 24)"
    printf 'TLS_ENABLED=false\nAPP_TIMEZONE=Europe/Budapest\n'
} > deploy/.env
chmod 600 deploy/.env
# Avoid the interactive account prompt, but exercise the installer implementation itself.
docker() {
    if [[ " $* " == *' p:user:make '* ]]; then return 0; fi
    command docker "$@"
}
initialize_panel
curl --fail --silent --show-error http://127.0.0.1:8080/auth/login -o /tmp/alex-login.html
grep -q '<html' /tmp/alex-login.html
compose exec -T --workdir /tmp panel php /app/artisan --version
# Check an already-initialized repair keeps app key, DB content, and credentials.
before=$(sha256sum deploy/.env)
initialize_panel repair
[[ $(sha256sum deploy/.env) == "$before" ]]
curl --fail --silent --show-error http://127.0.0.1:8080/auth/login -o /dev/null
echo 'PASS: Docker build, migration, HTTP login, absolute artisan path and repeat initialization.'
